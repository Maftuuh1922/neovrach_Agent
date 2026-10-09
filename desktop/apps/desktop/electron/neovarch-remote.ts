// Neovarch Remote: lets the Neovarch phone app (Flutter, remote-only) drive this
// desktop over the LAN.
//
// The desktop's own backend binds 127.0.0.1 and only accepts loopback peers, and
// the Hermes core refuses a non-loopback bind unless a dashboard auth provider is
// registered (`--insecure` is a no-op since the June 2026 hardening). So when the
// user enables remote access we spawn a SECOND, dedicated
//   neovarch serve --host 0.0.0.0 --port 9319 --isolated
// (9319, not Hermes' 9119: a co-installed Hermes dashboard/gateway keeps its
// port. If the port is already taken we report it and never touch the owner.)
// with the core's bundled username/password provider (plugins/dashboard_auth/basic)
// configured through HERMES_DASHBOARD_BASIC_AUTH_* env vars. We own its signing
// secret, so we mint the phone's access token ourselves in the exact format the
// provider's `verify_session` accepts:
//   base64url(json({sub, kind:"access", exp}) + HMAC-SHA256(secret, json))
// (urlsafe base64 WITH padding, compact JSON, signature appended without separator).
// The gated middleware accepts it as `Authorization: Bearer` on REST and as
// `?token=` on /api/ws. Rotating the secret ("Buat token baru") invalidates every
// paired phone.

import { type ChildProcess, execFile, spawn } from 'node:child_process'
import crypto from 'node:crypto'
import fs from 'node:fs'
import net from 'node:net'
import os from 'node:os'
import path from 'node:path'

export const REMOTE_DEFAULT_PORT = 9319
/** Hermes Agent's dashboard/gateway default; Neovarch must never take it. */
export const HERMES_DEFAULT_PORT = 9119
const TOKEN_SUBJECT = 'neovarch-remote'
const TOKEN_TTL_SECONDS = 5 * 365 * 24 * 60 * 60

export interface RemoteSettings {
  enabled: boolean
  port: number
  secret: string // base64, >= 32 bytes
  issuedAt: number // unix seconds; token exp = issuedAt + TTL (stable QR between renders)
  preferredAddress: string | null
  deviceName: string
}

export interface RemoteAddress {
  address: string
  iface: string
  /** lan: private LAN IPv4; tailscale: tailnet IPv4 (100.64.0.0/10); magicdns: Tailscale MagicDNS name */
  kind?: 'lan' | 'magicdns' | 'tailscale'
}

export interface TailscaleInfo {
  dnsName: string | null
  ips: string[]
}

export interface RemoteStatus {
  enabled: boolean
  running: boolean
  starting: boolean
  port: number
  addresses: RemoteAddress[]
  address: string | null
  url: string | null
  token: string | null
  pairingUri: string | null
  /** fallback origins the phone tries after `url`, in order (other LAN, MagicDNS, tailnet IP) */
  altUrls: string[]
  tailscale: TailscaleInfo | null
  deviceName: string
  profile: string | null
  error: string | null
  logTail: string
}

export interface RemoteSpawnSpec {
  command: string
  args: string[]
  env: NodeJS.ProcessEnv
  cwd?: string
  shell?: boolean | string
}

export interface RemoteControllerDeps {
  settingsPath: string
  /** Build the spawn spec for the given hermes argv (after `hermes`). */
  resolveSpawn: (args: string[]) => Promise<RemoteSpawnSpec>
  currentProfile: () => string | null
  log: (line: string) => void
  onChanged?: (status: RemoteStatus) => void
}

// ---- token minting (mirrors plugins/dashboard_auth/basic `_sign`) ----------

export function decodeSecret(secret: string): Buffer {
  return Buffer.from(secret, 'base64')
}

export function mintAccessToken(secret: Buffer, issuedAtSeconds = Math.floor(Date.now() / 1000)): string {
  // Python: json.dumps(payload, separators=(",", ":")) keeps insertion order.
  const raw = Buffer.from(JSON.stringify({ sub: TOKEN_SUBJECT, kind: 'access', exp: issuedAtSeconds + TOKEN_TTL_SECONDS }))
  const sig = crypto.createHmac('sha256', secret).update(raw).digest()

  // Python's urlsafe_b64encode keeps '=' padding.
  return Buffer.concat([raw, sig]).toString('base64').replace(/\+/g, '-').replace(/\//g, '_')
}

export function verifyAccessToken(token: string, secret: Buffer, nowSeconds = Math.floor(Date.now() / 1000)): boolean {
  try {
    const blob = Buffer.from(token.replace(/-/g, '+').replace(/_/g, '/'), 'base64')

    if (blob.length <= 32) {
      return false
    }

    const raw = blob.subarray(0, blob.length - 32)
    const sig = blob.subarray(blob.length - 32)
    const expected = crypto.createHmac('sha256', secret).update(raw).digest()

    if (!crypto.timingSafeEqual(sig, expected)) {
      return false
    }

    const payload = JSON.parse(raw.toString('utf8'))

    return payload.kind === 'access' && Number(payload.exp) > nowSeconds
  } catch {
    return false
  }
}

// ---- port ownership ---------------------------------------------------------

/** True when something already accepts connections on 127.0.0.1:<port>. */
export function portInUse(port: number, host = '127.0.0.1', timeoutMs = 800): Promise<boolean> {
  return new Promise(resolve => {
    const socket = net.connect({ port, host })
    const done = (busy: boolean) => {
      socket.removeAllListeners()
      socket.destroy()
      resolve(busy)
    }

    socket.setTimeout(timeoutMs, () => done(false))
    socket.once('connect', () => done(true))
    socket.once('error', () => done(false))
  })
}

// ---- LAN addresses ----------------------------------------------------------

const VIRTUAL_IFACE = /^(docker|br-|veth|virbr|vmnet|vboxnet|lo|utun|awdl|llw|zt|tun|tap)/i

export function lanAddresses(interfaces = os.networkInterfaces()): RemoteAddress[] {
  const out: RemoteAddress[] = []

  for (const [iface, entries] of Object.entries(interfaces)) {
    for (const entry of entries ?? []) {
      if (entry.family !== 'IPv4' || entry.internal || entry.address.startsWith('169.254.')) {
        continue
      }

      out.push({ address: entry.address, iface, kind: isTailnetIp(entry.address) ? 'tailscale' : 'lan' })
    }
  }

  const rank = (a: RemoteAddress) =>
    (VIRTUAL_IFACE.test(a.iface) ? 10 : 0) +
    (/^192\.168\./.test(a.address) ? 0 : /^10\./.test(a.address) ? 1 : /^172\.(1[6-9]|2\d|3[01])\./.test(a.address) ? 2 : /^100\./.test(a.address) ? 3 : 4)

  return out.sort((a, b) => rank(a) - rank(b))
}

/** 100.64.0.0/10: the CGNAT range Tailscale assigns tailnet addresses from. */
export function isTailnetIp(address: string): boolean {
  const m = /^100\.(\d+)\./.exec(address)

  return Boolean(m && Number(m[1]) >= 64 && Number(m[1]) <= 127)
}

/** Parse `tailscale status --json` (Self.DNSName + Self.TailscaleIPs). */
export function parseTailscaleStatus(json: string): TailscaleInfo | null {
  try {
    const self = (JSON.parse(json) as { Self?: { DNSName?: string; TailscaleIPs?: string[] } }).Self

    if (!self) {
      return null
    }

    return {
      dnsName: (self.DNSName ?? '').replace(/\.$/, '') || null,
      ips: (self.TailscaleIPs ?? []).filter(isTailnetIp)
    }
  } catch {
    return null
  }
}

export function readTailscale(): Promise<TailscaleInfo | null> {
  const exe = process.platform === 'win32' ? 'tailscale.exe' : 'tailscale'

  return new Promise(resolve => {
    execFile(exe, ['status', '--json'], { timeout: 4000, windowsHide: true }, (err, stdout) => {
      resolve(err ? null : parseTailscaleStatus(String(stdout)))
    })
  })
}

/** Phone try order after the primary `url`: other real LAN addresses, MagicDNS, tailnet IPs. */
export function fallbackUrls(input: {
  primary: string | null
  addresses: RemoteAddress[]
  tailscale: TailscaleInfo | null
  port: number
}): string[] {
  const hosts: string[] = []
  const lan = input.addresses.filter(a => !isTailnetIp(a.address) && !VIRTUAL_IFACE.test(a.iface))
  const tailnet = new Set([
    ...input.addresses.filter(a => isTailnetIp(a.address)).map(a => a.address),
    ...(input.tailscale?.ips ?? [])
  ])

  hosts.push(...lan.map(a => a.address))

  if (input.tailscale?.dnsName) {
    hosts.push(input.tailscale.dnsName)
  }

  hosts.push(...[...tailnet].sort())

  return [...new Set(hosts)].filter(h => h !== input.primary).map(h => `http://${h}:${input.port}`)
}

export function buildPairingUri(input: {
  url: string
  token: string
  name: string
  profile: string | null
  alt?: string[]
}): string {
  const q = new URLSearchParams({ v: '1', url: input.url })

  for (const alt of input.alt ?? []) {
    q.append('alt', alt)
  }

  q.set('token', input.token)
  q.set('name', input.name)

  if (input.profile) {
    q.set('profile', input.profile)
  }

  return `neovarch://pair?${q.toString()}`
}

// ---- controller -------------------------------------------------------------

function newSecret(): string {
  return crypto.randomBytes(32).toString('base64')
}

export const FALLBACK_DEVICE_NAME = 'PC Neovarch'

/**
 * The name the phone shows for this PC. Some Linux hosts (containers, minimal
 * installs) report an empty hostname or the literal "(none)"; those fall back
 * to a readable default instead of being shown to the user.
 */
export function resolveDeviceName(name: string | null | undefined = os.hostname()): string {
  const trimmed = typeof name === 'string' ? name.trim() : ''

  if (!trimmed || trimmed === '(none)') {
    return FALLBACK_DEVICE_NAME
  }

  return trimmed.slice(0, 64)
}

function defaultSettings(): RemoteSettings {
  return {
    enabled: false,
    port: REMOTE_DEFAULT_PORT,
    secret: newSecret(),
    issuedAt: Math.floor(Date.now() / 1000),
    preferredAddress: null,
    deviceName: resolveDeviceName()
  }
}

export function createRemoteController(deps: RemoteControllerDeps) {
  let settings = readSettings()
  let child: ChildProcess | null = null
  let running = false
  let starting = false
  let error: string | null = null
  let logTail = ''
  let generation = 0
  let tailscale: TailscaleInfo | null = null
  let tailscaleAt = 0

  // Tailscale is optional: read it lazily (at most once a minute) and re-emit
  // when the MagicDNS name or tailnet IPs change.
  function refreshTailscale(force = false) {
    if (!force && Date.now() - tailscaleAt < 60_000) {
      return
    }

    tailscaleAt = Date.now()
    void readTailscale().then(next => {
      if (JSON.stringify(next) !== JSON.stringify(tailscale)) {
        tailscale = next
        emit()
      }
    })
  }

  function readSettings(): RemoteSettings {
    try {
      const parsed = JSON.parse(fs.readFileSync(deps.settingsPath, 'utf8'))
      const base = defaultSettings()

      return {
        enabled: parsed.enabled === true,
        // v1.2.x defaulted to 9119, Hermes Agent's port; move those to Neovarch's own.
        port:
          Number.isInteger(parsed.port) && parsed.port > 0 && parsed.port < 65536 && parsed.port !== HERMES_DEFAULT_PORT
            ? parsed.port
            : base.port,
        secret: typeof parsed.secret === 'string' && decodeSecret(parsed.secret).length >= 32 ? parsed.secret : base.secret,
        issuedAt: Number.isInteger(parsed.issuedAt) && parsed.issuedAt > 0 ? parsed.issuedAt : base.issuedAt,
        preferredAddress: typeof parsed.preferredAddress === 'string' ? parsed.preferredAddress : null,
        deviceName: typeof parsed.deviceName === 'string' ? resolveDeviceName(parsed.deviceName) : base.deviceName
      }
    } catch {
      return defaultSettings()
    }
  }

  function writeSettings() {
    try {
      fs.mkdirSync(path.dirname(deps.settingsPath), { recursive: true })
      fs.writeFileSync(deps.settingsPath, JSON.stringify(settings, null, 2), { encoding: 'utf8', mode: 0o600 })
    } catch (err) {
      deps.log(`[remote] failed to save settings: ${(err as Error).message}`)
    }
  }

  function status(): RemoteStatus {
    const addresses = lanAddresses()

    const address =
      (settings.preferredAddress && addresses.find(a => a.address === settings.preferredAddress)?.address) ||
      addresses[0]?.address ||
      null

    const url = address ? `http://${address}:${settings.port}` : null
    const token = mintAccessToken(decodeSecret(settings.secret), settings.issuedAt)
    const profile = deps.currentProfile()
    refreshTailscale()
    const altUrls = fallbackUrls({ primary: address, addresses, tailscale, port: settings.port })

    return {
      enabled: settings.enabled,
      running,
      starting,
      port: settings.port,
      addresses,
      address,
      url,
      token: settings.enabled ? token : null,
      pairingUri:
        settings.enabled && url ? buildPairingUri({ url, token, name: settings.deviceName, profile, alt: altUrls }) : null,
      altUrls,
      tailscale,
      deviceName: settings.deviceName,
      profile,
      error,
      logTail: logTail.slice(-2000)
    }
  }

  function emit() {
    deps.onChanged?.(status())
  }

  async function waitForReady(gen: number, timeoutMs = 90_000): Promise<boolean> {
    const deadline = Date.now() + timeoutMs

    while (Date.now() < deadline) {
      if (gen !== generation || !child) {
        return false
      }

      try {
        const res = await fetch(`http://127.0.0.1:${settings.port}/api/status`, { signal: AbortSignal.timeout(2000) })

        if (res.ok) {
          return true
        }
      } catch {
        // not up yet
      }

      await new Promise(r => setTimeout(r, 750))
    }

    return false
  }

  async function start() {
    if (child || starting) {
      return
    }

    const gen = ++generation
    starting = true
    error = null
    logTail = ''
    emit()

    try {
      // Never fight another program (a co-installed Hermes on 9119, anything
      // else) for the port: refuse up front instead of spawning and probing a
      // server that is not ours.
      if (await portInUse(settings.port)) {
        error =
          settings.port === HERMES_DEFAULT_PORT
            ? `Port ${settings.port} dipakai Hermes Agent. Pilih port lain untuk Neovarch (bawaan ${REMOTE_DEFAULT_PORT}).`
            : `Port ${settings.port} sudah dipakai aplikasi lain. Pilih port lain.`
        deps.log(`[remote] port ${settings.port} busy; not starting`)

        return
      }

      const spec = await deps.resolveSpawn(['serve', '--host', '0.0.0.0', '--port', String(settings.port), '--isolated'])

      if (gen !== generation) {
        return
      }

      const env: NodeJS.ProcessEnv = {
        ...spec.env,
        HERMES_DASHBOARD_BASIC_AUTH_USERNAME: TOKEN_SUBJECT,
        // Random per start and never shown: the phone never logs in with a
        // password, it presents the HMAC token minted above.
        HERMES_DASHBOARD_BASIC_AUTH_PASSWORD: crypto.randomBytes(24).toString('base64url'),
        HERMES_DASHBOARD_BASIC_AUTH_SECRET: settings.secret
      }

      delete env.HERMES_DESKTOP // the primary backend owns cron ticks
      delete env.HERMES_DASHBOARD_SESSION_TOKEN
      deps.log(`[remote] starting LAN gateway on 0.0.0.0:${settings.port}`)

      const proc = spawn(spec.command, spec.args, {
        cwd: spec.cwd,
        env,
        shell: spec.shell,
        stdio: ['ignore', 'pipe', 'pipe'],
        windowsHide: true,
        // Own process group on POSIX so stop() also reaches a python child behind a shell shim.
        detached: process.platform !== 'win32'
      })

      child = proc

      const onData = (chunk: Buffer) => {
        logTail = (logTail + chunk.toString('utf8')).slice(-8000)
      }

      proc.stdout?.on('data', onData)
      proc.stderr?.on('data', onData)
      proc.once('error', err => {
        error = `Gagal menjalankan gateway remote: ${err.message}`
      })
      proc.once('exit', (code, signal) => {
        if (child === proc) {
          child = null
          running = false
          starting = false

          if (settings.enabled && gen === generation) {
            const tail = logTail.trim().split('\n').slice(-3).join(' ')
            error = `Gateway remote berhenti (kode ${code ?? signal}). ${tail}`.trim()
          }

          deps.log(`[remote] gateway exited code=${code} signal=${signal}`)
          emit()
        }
      })

      const ready = await waitForReady(gen)

      if (gen !== generation) {
        return
      }

      running = ready && child === proc

      if (!ready && child === proc) {
        error = error || `Gateway remote tidak merespons di port ${settings.port}. Port mungkin sudah dipakai aplikasi lain.`
      }
    } catch (err) {
      error = (err as Error).message
    } finally {
      if (gen === generation) {
        starting = false
      }

      emit()
    }
  }

  async function stop() {
    generation++
    const proc = child
    child = null
    running = false
    starting = false

    if (!proc || proc.exitCode !== null) {
      return
    }

    await new Promise<void>(resolve => {
      const timer = setTimeout(() => {
        try {
          if (process.platform !== 'win32' && proc.pid) {
            process.kill(-proc.pid, 'SIGKILL')
          } else {
            proc.kill('SIGKILL')
          }
        } catch {
          // already gone
        }

        resolve()
      }, 5000)

      proc.once('exit', () => {
        clearTimeout(timer)
        resolve()
      })

      try {
        if (process.platform === 'win32' && proc.pid) {
          spawn('taskkill', ['/pid', String(proc.pid), '/T', '/F'], { windowsHide: true })
        } else if (proc.pid) {
          try {
            process.kill(-proc.pid, 'SIGTERM')
          } catch {
            proc.kill('SIGTERM')
          }
        } else {
          proc.kill('SIGTERM')
        }
      } catch {
        clearTimeout(timer)
        resolve()
      }
    })
  }

  async function setEnabled(on: boolean) {
    settings = { ...settings, enabled: on }
    writeSettings()
    error = null

    if (on) {
      void start()
    } else {
      await stop()
    }

    emit()

    return status()
  }

  async function rotate() {
    settings = { ...settings, secret: newSecret(), issuedAt: Math.floor(Date.now() / 1000) }
    writeSettings()

    if (settings.enabled) {
      await stop()
      void start()
    }

    emit()

    return status()
  }

  function update(patch: Partial<Pick<RemoteSettings, 'deviceName' | 'preferredAddress'>>) {
    if (typeof patch.deviceName === 'string' && patch.deviceName.trim()) {
      settings.deviceName = patch.deviceName.trim().slice(0, 64)
    }

    if (patch.preferredAddress === null || typeof patch.preferredAddress === 'string') {
      settings.preferredAddress = patch.preferredAddress
    }

    writeSettings()
    emit()

    return status()
  }

  /** Probe what the phone will call: the Kanban board with the phone's token. */
  async function check(): Promise<{ ok: boolean; message: string }> {
    if (!running) {
      return { ok: false, message: 'Gateway remote belum berjalan.' }
    }

    const token = mintAccessToken(decodeSecret(settings.secret), settings.issuedAt)
    const host = status().address || '127.0.0.1'

    try {
      const res = await fetch(`http://${host}:${settings.port}/api/plugins/kanban/board`, {
        headers: { Authorization: `Bearer ${token}`, 'X-Hermes-Session-Token': token },
        signal: AbortSignal.timeout(5000)
      })

      if (res.ok) {
        return { ok: true, message: `Terhubung: ${host}:${settings.port} menerima token (Kanban OK).` }
      }

      if (res.status === 404) {
        return { ok: true, message: 'Token diterima, tetapi plugin Kanban nonaktif (tab Tugas di HP tidak akan berisi).' }
      }

      return { ok: false, message: `Gateway menjawab HTTP ${res.status}.` }
    } catch (err) {
      return { ok: false, message: `Tidak bisa menjangkau ${host}:${settings.port} (${(err as Error).message}). Periksa firewall.` }
    }
  }

  return {
    status,
    setEnabled,
    rotate,
    update,
    check,
    stop,
    /** Start at boot when the user left remote access on. */
    autostart() {
      if (settings.enabled) {
        void start()
      }
    }
  }
}

export type RemoteController = ReturnType<typeof createRemoteController>
