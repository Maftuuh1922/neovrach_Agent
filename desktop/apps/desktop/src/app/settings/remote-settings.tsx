import { useEffect, useState } from 'react'

import remotePairingArt from '@/assets/neovarch/remote-pairing.webp'
import { HaloMark } from '@/components/neovarch/halo-mark'
import { Button } from '@/components/ui/button'
import { CopyButton } from '@/components/ui/copy-button'
import { Input } from '@/components/ui/input'
import { QrCode, RefreshCw } from '@/lib/icons'
import { confirm } from '@/store/confirm'

import { ListRow, SectionHeading, SettingsContent, ToggleRow } from './primitives'

// Settings ▸ Remote / Perangkat — pair the Neovarch phone app with this PC.
// The main process (electron/neovarch-remote.ts) runs a LAN-bound, auth-gated
// `neovarch serve` on port 9319 and mints the phone's token; this page shows the
// pairing QR (neovarch://pair?v=1&url=…&token=…&name=…&profile=…).

const CAPTION = 'text-[length:var(--conversation-caption-font-size)] text-(--ui-text-tertiary)'
const MONO = 'font-mono text-[0.6875rem] leading-4 break-all text-(--ui-text-secondary)'

// Shown only outside Electron (renderer preview / screenshots), clearly labelled.
const PREVIEW_STATUS: NeovarchRemoteStatus = {
  enabled: true,
  running: true,
  starting: false,
  port: 9319,
  addresses: [
    { address: '192.168.1.5', iface: 'wlan0' },
    { address: '100.84.12.7', iface: 'tailscale0' }
  ],
  address: '192.168.1.5',
  url: 'http://192.168.1.5:9319',
  token: 'eyJzdWIiOiJuZW92YXJjaC1yZW1vdGUiLCJraW5kIjoiYWNjZXNzIiwiZXhwIjoxOTE3NjgwMDAwfdcg06aPZhiOLEAVRMba-pi23576xtM_tVRtdvf8-eZL',
  pairingUri:
    'neovarch://pair?v=1&url=http%3A%2F%2F192.168.1.5%3A9319&token=eyJzdWIiOiJuZW92YXJjaC1yZW1vdGUiLCJraW5kIjoiYWNjZXNzIiwiZXhwIjoxOTE3NjgwMDAwfdcg06aPZhiOLEAVRMba-pi23576xtM_tVRtdvf8-eZL&name=PC+Kantor&profile=default',
  deviceName: 'PC Kantor',
  profile: 'default',
  error: null,
  logTail: ''
}

async function renderQr(payload: string): Promise<string> {
  const QRCode = await import('qrcode')

  return QRCode.toDataURL(payload, {
    errorCorrectionLevel: 'M',
    margin: 2,
    width: 232,
    color: { dark: '#0d0606', light: '#f4f2ed' }
  })
}

export function RemoteSettings() {
  const api = window.hermesDesktop?.neovarchRemote
  const preview = !api
  const [status, setStatus] = useState<NeovarchRemoteStatus | null>(preview ? PREVIEW_STATUS : null)
  const [qr, setQr] = useState('')
  const [busy, setBusy] = useState(false)
  const [check, setCheck] = useState<{ ok: boolean; message: string } | null>(null)
  const [name, setName] = useState('')

  useEffect(() => {
    if (!api) {
      return
    }

    let alive = true
    void api.get().then(s => alive && setStatus(s))
    const off = api.onChanged(s => setStatus(s))

    return () => {
      alive = false
      off()
    }
  }, [api])

  useEffect(() => setName(status?.deviceName ?? ''), [status?.deviceName])

  useEffect(() => {
    let alive = true

    if (status?.pairingUri) {
      void renderQr(status.pairingUri).then(url => alive && setQr(url))
    } else {
      setQr('')
    }

    return () => {
      alive = false
    }
  }, [status?.pairingUri])

  const run = async (fn: () => Promise<NeovarchRemoteStatus>) => {
    setBusy(true)
    setCheck(null)

    try {
      setStatus(await fn())
    } finally {
      setBusy(false)
    }
  }

  const rotate = async () => {
    const ok = await confirm({
      title: 'Buat token baru?',
      description: 'Semua HP yang sudah dipasangkan akan terputus dan harus memindai QR baru.',
      confirmLabel: 'Buat token baru',
      destructive: true
    })

    if (ok && api) {
      await run(() => api.rotate())
    }
  }

  const runCheck = async () => {
    if (!api) {
      setCheck({ ok: true, message: 'Pratinjau: pemeriksaan hanya berjalan di aplikasi desktop.' })

      return
    }

    setBusy(true)

    try {
      setCheck(await api.check())
    } finally {
      setBusy(false)
    }
  }

  const stateLabel = !status?.enabled
    ? 'Nonaktif'
    : status.running
      ? `Berjalan di port ${status.port}`
      : status.starting
        ? 'Memulai gateway…'
        : 'Berhenti'

  return (
    <SettingsContent>
      <section className="nv-remote-hero" data-slot="nv-remote-hero">
        <img alt="" aria-hidden="true" className="nv-remote-art" draggable={false} src={remotePairingArt} />
        <div className="nv-remote-copy">
          <span className="nv-eyebrow">Remote / Perangkat</span>
          <h2 className="nv-remote-title">Pasangkan HP</h2>
          <div className="nv-remote-device">
            <HaloMark className={status?.running ? 'size-3 text-(--nv-red)' : 'size-3 text-[#7d7470]'} />
            <span className="nv-remote-device-name">{status?.deviceName || 'PC Neovarch'}</span>
            <span className="nv-remote-device-state">{stateLabel}</span>
          </div>
          <ol className="nv-remote-steps">
            <li>
              <span>01</span>Aktifkan akses remote
            </li>
            <li>
              <span>02</span>Pindai QR dari HP
            </li>
            <li>
              <span>03</span>Obrolan, persetujuan &amp; Kanban di HP
            </li>
          </ol>
        </div>
      </section>
      <SectionHeading icon={QrCode} meta={stateLabel} title="Detail koneksi" />
      <p className={`${CAPTION} mb-2`}>
        Kendalikan agen di PC ini dari aplikasi Neovarch di HP: obrolan, persetujuan, dan Kanban. HP harus berada di
        jaringan yang sama (Wi‑Fi/LAN) atau terhubung lewat Tailscale/VPN.
        {preview && ' (Pratinjau — data contoh.)'}
      </p>

      <ToggleRow
        checked={Boolean(status?.enabled)}
        description="Menjalankan gateway kedua yang terkunci token di 0.0.0.0:9319 agar HP bisa terhubung."
        disabled={busy || !status || preview}
        label="Aktifkan akses remote"
        onChange={on => api && void run(() => api.setEnabled(on))}
      />

      {status?.error && (
        <p className="my-2 rounded-[4px] bg-(--ui-bg-quaternary) px-3 py-2 text-xs text-destructive">{status.error}</p>
      )}

      {status?.enabled && (
        <>
          <ListRow
            description="Di HP: buka Neovarch Agent ▸ Pindai QR dari PC."
            title="Pasangkan HP"
            wide
            below={
              <div className="mt-3 flex flex-wrap items-start gap-5">
                <div className="nv-qr-frame grid size-[232px] place-items-center bg-[#f4f2ed]">
                  {qr ? (
                    <img alt="QR pemasangan Neovarch" className="size-[232px]" src={qr} />
                  ) : (
                    <span className="text-xs text-[#0d0606]/60">
                      {status.url ? 'Membuat QR…' : 'Tidak ada alamat LAN'}
                    </span>
                  )}
                </div>
                <div className="min-w-0 flex-1 space-y-3">
                  <Field copy={status.url ?? ''} label="Alamat">
                    <span className={MONO}>{status.url ?? '—'}</span>
                  </Field>
                  <Field copy={status.token ?? ''} label="Token">
                    <span className={MONO}>{status.token ?? '—'}</span>
                  </Field>
                  {status.profile && (
                    <p className={CAPTION}>
                      Profil: <span className="font-mono">{status.profile}</span>
                    </p>
                  )}
                </div>
              </div>
            }
          />

          {status.addresses.length > 1 && (
            <ListRow
              action={
                <select
                  className="h-8 rounded-[4px] bg-(--ui-bg-quaternary) px-2 text-xs text-(--ui-text-primary)"
                  disabled={busy}
                  onChange={e => api && void run(() => api.update({ preferredAddress: e.target.value }))}
                  value={status.address ?? ''}
                >
                  {status.addresses.map(a => (
                    <option key={a.address} value={a.address}>
                      {a.address} ({a.iface})
                    </option>
                  ))}
                </select>
              }
              description="PC ini punya beberapa alamat jaringan. Pilih yang bisa dijangkau HP."
              title="Alamat LAN"
            />
          )}

          <ListRow
            action={
              <Input
                className="h-8 w-56"
                disabled={busy || preview}
                onBlur={() => api && name.trim() && name !== status.deviceName && void run(() => api.update({ deviceName: name }))}
                onChange={e => setName(e.target.value)}
                value={name}
              />
            }
            description="Nama yang tampil di daftar PC pada HP."
            title="Nama PC"
          />

          <ListRow
            action={
              <Button disabled={busy || !status.running} onClick={() => void runCheck()} size="sm" variant="outline">
                Periksa koneksi
              </Button>
            }
            description={
              check ? (
                <span className={check.ok ? 'text-(--ui-text-secondary)' : 'text-destructive'}>{check.message}</span>
              ) : (
                'Memanggil /api/plugins/kanban/board dengan token HP lewat alamat LAN.'
              )
            }
            title="Status"
          />

          <ListRow
            action={
              <Button disabled={busy || preview} onClick={() => void rotate()} size="sm" variant="destructive">
                <RefreshCw />
                Buat token baru
              </Button>
            }
            description="Mengganti kunci rahasia dan memulai ulang gateway. Semua HP terputus (cara mencabut akses)."
            title="Cabut akses HP"
          />

          <p className={`${CAPTION} mt-3`}>
            Token = kendali penuh atas agen di PC ini. Di Wi‑Fi tanpa enkripsi token bisa disadap; untuk di luar
            rumah gunakan Tailscale/WireGuard. Izinkan port {status.port} di firewall bila HP tidak bisa terhubung.
          </p>
        </>
      )}
    </SettingsContent>
  )
}

function Field({ children, copy, label }: { children: React.ReactNode; copy: string; label: string }) {
  return (
    <div>
      <div className="mb-1 flex items-center justify-between gap-2">
        <span className="text-[0.6875rem] font-medium tracking-wide text-(--ui-text-tertiary) uppercase">{label}</span>
        {copy && <CopyButton appearance="inline" label={`Salin ${label.toLowerCase()}`} text={copy} />}
      </div>
      <div className="rounded-[4px] bg-(--ui-bg-quaternary) px-2.5 py-2">{children}</div>
    </div>
  )
}
