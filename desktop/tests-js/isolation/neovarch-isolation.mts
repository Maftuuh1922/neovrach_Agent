// Neovarch <-> Hermes isolation: launch the built Neovarch desktop as a user
// who also has Hermes Agent (fake ~/.hermes, `hermes` on PATH, HERMES_HOME
// exported, a Hermes gateway on :9119), run two chats against the Neovarch
// core through its mock LLM (core/tests/mock_llm.py: streamed words, one tool
// call), optionally turn on remote access, and record what the app used.
// SHOTS=<dir> saves screenshots there; renderer errors go to $ISO/console.log.
//
//   ISO=/tmp/neovarch-iso scripts/isolation-test/run.sh setup && ... install
//   cd desktop && xvfb-run -a npx tsx tests-js/isolation/neovarch-isolation.mts
//   ISO=/tmp/neovarch-iso scripts/isolation-test/run.sh verify
//
// NEOVARCH_ISO_APP=<path to a packaged executable> launches that build;
// otherwise the built (dist/) app is run with this repo's Electron.
import fs from 'node:fs'
import path from 'node:path'

import { spawn } from 'node:child_process'

import { _electron } from '@playwright/test'

const ISO = process.env.ISO ?? '/tmp/neovarch-iso'
const HOME = path.join(ISO, 'home')
const NV_HOME = path.join(HOME, '.neovarch')
const REPORT = path.join(ISO, 'desktop-report.json')
const SHOTS = process.env.SHOTS ?? ISO
const LLM_PORT = Number(process.env.MOCK_LLM_PORT ?? 18080)
const CHAT1 = 'Halo Neovarch, tes isolasi.'
const REPLY1 = `Kamu bilang: ${CHAT1}`
const CHAT2 = 'Coba jalankan tool sekarang.'
const REPLY2 = 'Selesai. Hasil alat: neovarch-tool-ok'
const report: Record<string, unknown> = {}
const sleep = (ms: number) => new Promise(r => setTimeout(r, ms))
fs.mkdirSync(SHOTS, { recursive: true })

// The core's own OpenAI-compatible mock provider.
const mock = spawn(process.env.PYTHON ?? 'python3', [path.resolve('../core/tests/mock_llm.py'), '--port', String(LLM_PORT)], {
  stdio: 'ignore'
})
fs.mkdirSync(NV_HOME, { recursive: true })
fs.writeFileSync(
  path.join(NV_HOME, 'config.yaml'),
  `model:\n  provider: custom\n  default: mock-model\n  base_url: http://127.0.0.1:${LLM_PORT}/v1\n`
)
await sleep(1500)
report.mockUrl = `http://127.0.0.1:${LLM_PORT}/v1`

const desktopRoot = path.resolve('apps/desktop')
const packaged = process.env.NEOVARCH_ISO_APP
const executablePath = packaged ?? process.env.NEOVARCH_ISO_ELECTRON ?? [path.resolve('apps/desktop/node_modules/electron/dist/electron'), path.resolve('node_modules/electron/dist/electron')].find(p => fs.existsSync(p))!
report.launched = packaged ? { packaged } : { electron: executablePath, app: desktopRoot }

// The environment of someone who also runs Hermes: only HOME/PATH/HERMES_HOME
// are set here; nothing Neovarch-specific is passed in.
const env: Record<string, string> = {}
for (const [k, v] of Object.entries(process.env)) if (v !== undefined && !/^(HERMES_|NEOVARCH_)/.test(k)) env[k] = v
Object.assign(env, {
  HOME,
  HERMES_HOME: path.join(HOME, '.hermes'),
  PATH: `${path.join(HOME, '.local/bin')}:${process.env.PATH}`,
  NO_PROXY: '*',
  no_proxy: '*'
})
delete env.XDG_CONFIG_HOME
delete env.XDG_DATA_HOME
delete env.XDG_STATE_HOME

const app = await _electron.launch({
  executablePath,
  args: [...(packaged ? [] : [desktopRoot]), '--disable-gpu', '--no-sandbox'],
  cwd: packaged ? path.dirname(packaged) : desktopRoot,
  env,
  timeout: 180_000
})
const log = path.join(ISO, 'electron.log')
app.process().stdout?.on('data', d => fs.appendFileSync(log, d))
app.process().stderr?.on('data', d => fs.appendFileSync(log, d))

report.main = await app.evaluate(({ app: a }) => ({
  userData: a.getPath('userData'),
  isPackaged: a.isPackaged,
  NEOVARCH_HOME: process.env.NEOVARCH_HOME,
  HERMES_HOME_seen_by_children: process.env.HERMES_HOME,
  NEOVARCH_CORE: process.env.NEOVARCH_CORE
}))
console.log('main', report.main)

const page = await app.firstWindow()
const CONSOLE = path.join(ISO, 'console.log')
fs.writeFileSync(CONSOLE, '')
page.on('pageerror', e => fs.appendFileSync(CONSOLE, `\n=== pageerror: ${e.message}\n${(e.stack || '').slice(0, 1500)}\n`))
page.on('console', m => {
  if (m.type() === 'error' || m.type() === 'warning') fs.appendFileSync(CONSOLE, `\n--- console.${m.type()}: ${m.text().slice(0, 1500)}\n`)
})
const shot = (name: string) => page.screenshot({ path: path.join(SHOTS, name) }).catch(() => {})

const composerReady = async () => {
  const composer = page.locator('[contenteditable="true"]').first()
  await composer.waitFor({ timeout: 300_000 })
  for (let i = 0; i < 240; i++) {
    if (!(await page.locator('[class*="z-(--z-onboarding)"]').count())) break
    await sleep(1000)
  }
  return composer
}

const chat = async (text: string, reply: string, key: string) => {
  const composer = await composerReady()
  await sleep(1500)
  await composer.click()
  await composer.type(text)
  await page.keyboard.press('Enter')
  // Streaming: the reply grows in place before it is complete.
  const seen = new Set<number>()
  for (let i = 0; i < 180; i++) {
    await sleep(500)
    const body: string = await page.evaluate(() => document.body.innerText)
    const at = body.lastIndexOf(reply.split(' ')[0])
    if (at >= 0) seen.add(body.length)
    if (body.includes(reply)) {
      report[`${key}Seconds`] = (i + 1) / 2
      report[`${key}Frames`] = seen.size
      return true
    }
  }
  return false
}

await composerReady()
await sleep(4000)
await shot('01-home.png')
report.chat1Replied = await chat(CHAT1, REPLY1, 'chat1')
await sleep(1500)
await shot('02-chat1-streamed.png')
console.log('chat 1 replied:', report.chat1Replied)

// A second, separate chat: back to the start page, which opens a new session.
await page.evaluate(() => { window.location.hash = '#/' })
await sleep(2500)
report.chat2Replied = await chat(CHAT2, REPLY2, 'chat2')
await sleep(1500)
await shot('03-chat2-tool.png')
console.log('chat 2 replied:', report.chat2Replied)
const replied = Boolean(report.chat1Replied && report.chat2Replied)
report.chatReplied = replied
fs.copyFileSync(path.join(SHOTS, '03-chat2-tool.png'), path.join(ISO, 'chat.png'))

// Remote access: must come up on Neovarch's own port, never on Hermes' 9119.
if (process.env.ISO_REMOTE !== '0') {
  await page.evaluate(() => { window.location.hash = '#/settings?tab=remote' })
  await sleep(3000)
  const toggle = page.getByRole('switch', { name: 'Aktifkan akses remote' })
  try {
    await toggle.click()
    for (let i = 0; i < 90; i++) {
      await sleep(1000)
      if (await page.locator('text=Berjalan di port').count()) break
    }
    report.remoteText = (await page.locator('text=Berjalan di port').first().textContent({ timeout: 2000 }).catch(() => null)) ?? null
    await page.screenshot({ path: path.join(ISO, 'remote.png') }).catch(() => {})
    await shot('04-remote.png')
    const remoteFile = path.join(String((report.main as any).userData), 'neovarch-remote.json')
    report.remotePort = fs.existsSync(remoteFile) ? JSON.parse(fs.readFileSync(remoteFile, 'utf8')).port : null
    report.remoteHttp = await fetch(`http://127.0.0.1:${report.remotePort}/api/status`).then(r => r.status).catch(e => String(e))
  } catch (e) {
    report.remoteError = String(e)
  }
}

// Which processes did Neovarch run? (cmdline + HERMES_HOME/NEOVARCH_HOME of each child)
const ps: any[] = []
for (const pid of fs.readdirSync('/proc').filter(p => /^\d+$/.test(p))) {
  try {
    const environ = fs.readFileSync(`/proc/${pid}/environ`, 'utf8').split('\0')
    if (!environ.includes('NEOVARCH_CORE=1')) continue
    const cmd = fs.readFileSync(`/proc/${pid}/cmdline`, 'utf8').split('\0').join(' ').trim()
    ps.push({ pid: Number(pid), cmd: cmd.slice(0, 200), HERMES_HOME: environ.find(e => e.startsWith('HERMES_HOME=')), NEOVARCH_HOME: environ.find(e => e.startsWith('NEOVARCH_HOME=')) })
  } catch {
    // gone / not ours
  }
}
report.neovarchProcesses = ps

await shot('05-after-remote.png')
const consoleText = fs.readFileSync(CONSOLE, 'utf8')
report.maxUpdateDepthErrors = (consoleText.match(/Maximum update depth/g) || []).length
report.pageErrors = (consoleText.match(/=== pageerror/g) || []).length

await app.close().catch(() => {})
await sleep(3000)
mock.kill()
fs.writeFileSync(REPORT, JSON.stringify(report, null, 2))
console.log(JSON.stringify(report, null, 2))
process.exit(replied ? 0 : 1)
