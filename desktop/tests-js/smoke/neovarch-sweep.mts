// Neovarch desktop smoke sweep: launch the built app against this checkout's core
// (core/) and the core's mock LLM, then
//   1. open every rail page and every Settings section, and fail on any console
//      error, page error, "failed to load" text, or a 4xx/5xx API response
//      (the core writes every /api response to $NEOVARCH_ACCESS_LOG);
//   2. run the real Add model flow twice through Settings ▸ Penyedia ▸ Endpoint
//      kustom: a local http endpoint (bare root, models discovered) and an https
//      gateway with a self-signed certificate, API key and a custom header; select
//      it, chat, and check the reply came from that endpoint.
//
//   cd desktop && xvfb-run -a npx tsx tests-js/smoke/neovarch-sweep.mts
//   env: SWEEP_DIR (scratch, default /tmp/neovarch-sweep), PYTHON (with aiohttp+PyYAML),
//        SHOTS (screenshots), NEOVARCH_SWEEP_ELECTRON (electron binary).
import fs from 'node:fs'
import net from 'node:net'
import path from 'node:path'

import { execFileSync, spawn } from 'node:child_process'

import { _electron, type Page } from '@playwright/test'

const DIR = process.env.SWEEP_DIR ?? '/tmp/neovarch-sweep'
const HOME = path.join(DIR, 'home')
const NV_HOME = path.join(HOME, '.neovarch')
const SHOTS = process.env.SHOTS ?? path.join(DIR, 'shots')
const ACCESS = path.join(DIR, 'access.log')
const PY = process.env.PYTHON ?? 'python3'
const CORE = path.resolve('../core')
const sleep = (ms: number) => new Promise(r => setTimeout(r, ms))
const report: Record<string, unknown> = { failures: [] as string[] }
const fail = (msg: string) => {
  ;(report.failures as string[]).push(msg)
  console.log('FAIL', msg)
}

fs.rmSync(DIR, { recursive: true, force: true })
fs.mkdirSync(NV_HOME, { recursive: true })
fs.mkdirSync(SHOTS, { recursive: true })

const freePort = () =>
  new Promise<number>(resolve => {
    const s = net.createServer().listen(0, '127.0.0.1', () => {
      const port = (s.address() as net.AddressInfo).port
      s.close(() => resolve(port))
    })
  })

// Self-signed certificate for the https gateway.
const tls = path.join(DIR, 'tls')
fs.mkdirSync(tls)
execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', 'k.pem', '-out', 'c.pem', '-days', '2',
  '-subj', '/CN=127.0.0.1', '-addext', 'subjectAltName=IP:127.0.0.1'], { cwd: tls, stdio: 'ignore' })

const mockScript = path.join(CORE, 'tests/mock_llm.py')
const basePort = await freePort()
const localPort = await freePort()
const tlsPort = await freePort()
const kids = [
  // the model configured at first launch
  spawn(PY, [mockScript, '--port', String(basePort), '--delay', '0.02'], { stdio: 'ignore' }),
  // "LiteLLM lokal": plain http on localhost, odd port, no key
  spawn(PY, [mockScript, '--port', String(localPort), '--delay', '0.02'], { stdio: 'ignore' }),
  // "9router": https, self-signed, key + header required
  spawn(PY, [mockScript, '--port', String(tlsPort), '--delay', '0.02', '--api-key', 'sk-sweep-123',
    '--header', 'X-Router-Tenant: neo', '--cert', path.join(tls, 'c.pem'), '--key', path.join(tls, 'k.pem')], { stdio: 'ignore' })
]
// Fake GitHub "releases/latest" so the update banner has something newer to show.
const releasesDir = path.join(DIR, 'releases')
fs.mkdirSync(releasesDir)
fs.writeFileSync(path.join(releasesDir, 'latest'), JSON.stringify({ tag_name: 'v9.9.0', html_url: 'https://example.test/v9.9.0', assets: [] }))
const releasesPort = await freePort()
kids.push(spawn(PY, ['-m', 'http.server', String(releasesPort), '--bind', '127.0.0.1', '--directory', releasesDir], { stdio: 'ignore' }))
// A small Obsidian vault for the viewer.
const VAULT = path.join(DIR, 'Kuliah')
fs.mkdirSync(path.join(VAULT, 'Bab'), { recursive: true })
fs.writeFileSync(path.join(VAULT, 'Skripsi.md'), '# Skripsi\nLihat [[Bab/Pendahuluan]] dan [[Metode]].\n')
fs.writeFileSync(path.join(VAULT, 'Bab', 'Pendahuluan.md'), 'Kembali ke [[Skripsi]].\n')
fs.writeFileSync(path.join(VAULT, 'Metode.md'), 'Metode, rujuk [[Skripsi]].\n')
fs.writeFileSync(path.join(NV_HOME, 'config.yaml'),
  `model:\n  provider: custom\n  default: mock-model\n  base_url: http://127.0.0.1:${basePort}/v1\nmemory:\n  obsidian_vault: ${VAULT}\n`)
await sleep(1500)

const desktopRoot = path.resolve('apps/desktop')
const executablePath = process.env.NEOVARCH_SWEEP_ELECTRON ?? [path.resolve('apps/desktop/node_modules/electron/dist/electron'),
  path.resolve('node_modules/electron/dist/electron')].find(p => fs.existsSync(p))!
const env: Record<string, string> = {}
for (const [k, v] of Object.entries(process.env)) if (v !== undefined && !/^(HERMES_|NEOVARCH_)/.test(k)) env[k] = v
Object.assign(env, {
  HOME,
  NO_PROXY: '*',
  no_proxy: '*',
  NEOVARCH_DESKTOP_CORE_ROOT: CORE,
  HERMES_DESKTOP_PYTHON: PY,
  NEOVARCH_ACCESS_LOG: ACCESS,
  NEOVARCH_RELEASES_URL: `http://127.0.0.1:${releasesPort}/latest`
})
for (const k of ['XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME', 'HTTP_PROXY', 'HTTPS_PROXY', 'http_proxy', 'https_proxy']) delete env[k]

const app = await _electron.launch({ executablePath, args: [desktopRoot, '--disable-gpu', '--no-sandbox'], cwd: desktopRoot, env, timeout: 180_000 })
const page: Page = await app.firstWindow()
const consoleErrors: string[] = []
page.on('pageerror', e => consoleErrors.push(`pageerror: ${e.message}`))
page.on('console', m => {
  if (m.type() === 'error') consoleErrors.push(`console.error: ${m.text().slice(0, 400)}`)
})
const shot = (name: string) => page.screenshot({ path: path.join(SHOTS, name) }).catch(() => {})
const HERMES_TEXT = /hermes|nousresearch/i
const FAILED_TEXT = /failed to load|could not load|couldn['’]t load|gagal memuat|tidak dapat memuat|no such api endpoint|not found/i

const composer = page.locator('[contenteditable="true"]').first()
await composer.waitFor({ timeout: 300_000 })
for (let i = 0; i < 120 && (await page.locator('[class*="z-(--z-onboarding)"]').count()); i++) await sleep(1000)
await sleep(3000)

// ---- first run: colour picker -> saved in the core (phone follows) -> painted
{
  let picker = 0
  for (let i = 0; i < 20 && !(picker = await page.locator('[data-nv-first-run-theme]').count()); i++) await sleep(500)
  report.firstRunPicker = picker > 0
  if (!picker) fail('first-run theme picker not shown')
  else {
    await page.locator('[data-nv-first-run-theme] [data-nv-accent="Biru"]').click()
    await sleep(1500)
    const red = await page.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue('--nv-red').trim())
    const cfg = fs.readFileSync(path.join(NV_HOME, 'config.yaml'), 'utf8')
    report.pickedAccent = red
    if (red.toUpperCase() !== '#2563EB') fail(`theme: --nv-red is "${red}" after picking Biru`)
    if (!/accent: .#2563EB/i.test(cfg)) fail('theme: accent not saved in config.yaml')
    await shot('first-run-theme-biru.png')
    await page.locator('[data-nv-first-run-theme] [data-nv-accent="Merah"]').click()
    await sleep(800)
    await page.locator('[data-nv-theme-done]').click()
    await sleep(800)
    if (await page.locator('[data-nv-first-run-theme]').count()) fail('theme: picker did not close')
  }
}

// ---- v1.4 start screen: greeting + composer only; tab says "Sesi baru"; update banner
{
  const body: string = await page.evaluate(() => document.body.innerText)
  report.homeGreeting = /Selamat (pagi|siang|sore|malam)/.test(body)
  if (!report.homeGreeting) fail('home: greeting missing')
  for (const gone of ['Obrolan baru\nMulai percakapan', 'INDEKS SESI', 'Ask a question']) if (body.includes(gone)) fail(`home: should be minimal, found "${gone}"`)
  if (/NEW SESSION/.test(body)) fail('tab still says NEW SESSION')
  if (!/Sesi baru/.test(body)) fail('tab "Sesi baru" missing')
  let banner = 0
  for (let i = 0; i < 20 && !(banner = await page.locator('[data-nv-update-banner="9.9.0"]').count()); i++) await sleep(500)
  report.updateBanner = banner > 0
  if (!banner) fail('update banner (v9.9.0) not shown')
  await shot('home-minimal.png')
}

const accessMark = () => (fs.existsSync(ACCESS) ? fs.readFileSync(ACCESS, 'utf8').split('\n').length : 0)
const badSince = (mark: number) =>
  (fs.existsSync(ACCESS) ? fs.readFileSync(ACCESS, 'utf8').split('\n').slice(mark - 1) : []).filter(l => /^[45]\d\d /.test(l))

async function visit(label: string, go: () => Promise<unknown>) {
  const mark = accessMark()
  const errs = consoleErrors.length
  await go()
  await sleep(2500)
  const body: string = await page.evaluate(() => document.body.innerText)
  const m = body.match(FAILED_TEXT)
  const bad = badSince(mark)
  const newErrs = consoleErrors.slice(errs)
  const slug = label.replace(/[^a-z0-9]+/gi, '-').toLowerCase()
  await shot(`sweep-${slug}.png`)
  const row = { label, failedText: m?.[0] ?? null, http: bad, console: newErrs }
  ;(report.pages as unknown[] | undefined)?.push(row) ?? (report.pages = [row])
  if (m) fail(`${label}: text "${m[0]}"`)
  const iframes = await page.locator('iframe[src*="nousresearch"]').count()
  if (iframes) fail(`${label}: embeds a Hermes site`)
  const h = body.match(HERMES_TEXT)
  if (h) (report.hermesText as string[] | undefined)?.push(`${label}: ${h[0]}`) ?? (report.hermesText = [`${label}: ${h[0]}`])
  for (const b of bad) fail(`${label}: ${b}`)
  for (const e of newErrs) fail(`${label}: ${e}`)
}

const RAIL = ['sessions', 'office', 'skills', 'kanban', 'artifacts', 'cron', 'vault', 'pair-phone', 'settings', 'home', 'new-chat']
if (await page.locator('[data-nv-rail="messaging"]').count()) fail('rail: Messaging should be removed')
for (const need of ['office', 'vault', 'skills', 'kanban', 'artifacts', 'cron']) {
  if (!(await page.locator(`[data-nv-rail="${need}"]`).count())) fail(`rail: ${need} button missing`)
}
for (const id of RAIL) {
  const btn = page.locator(`[data-nv-rail="${id}"]`)
  if (!(await btn.count())) continue
  await visit(`rail ${id}`, () => btn.first().click())
  if (id === 'sessions') await btn.first().click()
}

// Office page opens from the rail and lists the agents (the open chat is one desk).
await page.locator('[data-nv-rail="office"]').first().click()
await sleep(2500)
{
  const body: string = await page.evaluate(() => document.body.innerText)
  report.officePage = /Kantor/.test(body) && !/Kantor belum bisa dimuat/.test(body)
  if (!report.officePage) fail('office page did not load')
  await shot('office.png')
}

// Vault viewer: tree -> note with backlinks -> wikilink -> graph.
await page.locator('[data-nv-rail="vault"]').first().click()
await sleep(2000)
{
  const note = page.locator('[data-nv-vault-note="Skripsi.md"]')
  if (!(await note.count())) fail('vault: tree did not list Skripsi.md')
  else {
    await note.click()
    await sleep(1500)
    const body: string = await page.evaluate(() => document.body.innerText)
    if (!/Backlink \(2\)/.test(body)) fail('vault: Skripsi should show 2 backlinks')
    if (!/Buka di Obsidian/.test(body)) fail('vault: "Buka di Obsidian" button missing')
    await shot('vault-note.png')
    await page.locator('.nv-vault-wikilink', { hasText: 'Metode' }).first().click()
    await sleep(1200)
    if (!(await page.locator('[data-nv-vault-open="Metode.md"]').count())) fail('vault: wikilink did not open Metode.md')
  }
  await page.locator('[data-nv-vault-tab="graph"]').click()
  await sleep(1200)
  const nodes = await page.locator('[data-nv-vault-graph]').getAttribute('data-nv-vault-graph').catch(() => null)
  report.vaultGraphNodes = nodes
  if (nodes !== '3') fail(`vault: graph should have 3 nodes, got ${nodes}`)
  await shot('vault-graph.png')
}

// Scheduled jobs: create one through the real dialog, see it listed and in the core.
await page.locator('[data-nv-rail="cron"]').first().click()
await sleep(2000)
{
  const add = page.getByRole('button', { name: /^Jadwal baru$/ }).first()
  if (!(await add.count())) fail('cron: "Jadwal baru" button missing')
  else {
    await add.click()
    await sleep(800)
    await page.locator('#cron-name').fill('Ringkasan sweep')
    await page.locator('#cron-prompt').fill('Rangkum berita hari ini')
    await page.getByRole('button', { name: /^Buat jadwal$/ }).click()
    await sleep(2000)
    const body: string = await page.evaluate(() => document.body.innerText)
    report.cronCreated = body.includes('Ringkasan sweep')
    if (!report.cronCreated) fail('cron: created job not listed')
    const jobs = JSON.parse(fs.readFileSync(path.join(NV_HOME, 'cron.json'), 'utf8') || '{}')
    const list = Array.isArray(jobs) ? jobs : jobs.jobs ?? []
    if (!list.some((j: { name?: string }) => j.name === 'Ringkasan sweep')) fail('cron: job not saved in ~/.neovarch/cron.json')
    await shot('cron-created.png')
  }
  await page.keyboard.press('Escape')
  await sleep(500)
}

// Document preview: a DOCX (made by Pandoc) and a PDF, rendered in the app.
{
  const docDir = path.join(DIR, 'docs')
  fs.mkdirSync(docDir, { recursive: true })
  const docx = path.join(docDir, 'laporan.docx')
  fs.writeFileSync(path.join(docDir, 'laporan.md'), '# BAB I Pendahuluan\n\nIni laporan uji pratinjau.\n\n# BAB II Metode\n\nTeks.\n')
  try { execFileSync('pandoc', ['laporan.md', '-o', docx], { cwd: docDir }) } catch { fail('preview: pandoc missing, cannot make a docx') }
  const objs = ['<< /Type /Catalog /Pages 2 0 R >>', '<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R /Resources << /Font << /F1 6 0 R >> >> >>',
    '<< /Length 44 >>\nstream\nBT /F1 24 Tf 72 760 Td (Halaman satu) Tj ET\nendstream',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 7 0 R /Resources << /Font << /F1 6 0 R >> >> >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /Length 43 >>\nstream\nBT /F1 24 Tf 72 760 Td (Halaman dua) Tj ET\nendstream']
  let pdf = '%PDF-1.4\n'
  const offs: number[] = []
  objs.forEach((o, i) => { offs.push(pdf.length); pdf += `${i + 1} 0 obj\n${o}\nendobj\n` })
  const xref = pdf.length
  pdf += `xref\n0 ${objs.length + 1}\n0000000000 65535 f \n` + offs.map(o => `${String(o).padStart(10, '0')} 00000 n \n`).join('')
  pdf += `trailer\n<< /Size ${objs.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`
  const pdfPath = path.join(docDir, 'laporan.pdf')
  fs.writeFileSync(pdfPath, pdf)
  for (const [file, kind] of [[pdfPath, 'pdf'], [docx, 'docx']] as const) {
    await page.evaluate(p => window.dispatchEvent(new CustomEvent('neovarch:preview-doc', { detail: { path: p } })), file)
    let ok = false
    for (let i = 0; i < 30 && !ok; i++) {
      await sleep(500)
      ok = kind === 'pdf'
        ? (await page.locator('[data-nv-doc-preview="pdf"] canvas[data-nv-pdf-page]').count()) === 2
        : (await page.locator('[data-nv-doc-preview="docx"] section.nv-docx').count()) > 0
    }
    ;(report as Record<string, unknown>)[`preview_${kind}`] = ok
    if (!ok) fail(`preview: ${kind} did not render`)
    if (kind === 'docx' && ok) {
      const text = await page.locator('[data-nv-doc-preview]').innerText()
      if (!text.includes('BAB I Pendahuluan')) fail('preview: docx text missing')
    }
    await shot(`preview-${kind}.png`)
    await page.keyboard.press('Escape')
    await sleep(500)
  }
}

const SETTINGS = ['config:model', 'providers', 'config:chat', 'config:appearance', 'config:workspace', 'notifications',
  'keybinds', 'config:voice', 'remote', 'gateway', 'config:safety', 'vault', 'keys', 'config:memory', 'sessions', 'plugins',
  'config:advanced', 'config:browser', 'billing', 'about']
for (const tab of SETTINGS) {
  await visit(`settings ${tab}`, () => page.evaluate(t => { window.location.hash = `#/settings?tab=${encodeURIComponent(t)}` }, tab))
}
// Provider sub-pages are chosen with ?pview=, and the nav item is clicked as a
// user would, so the sweep proves the sidebar entry itself opens the page.
const PROVIDER_NAV: Record<string, RegExp> = { keys: /^kunci api$|^api keys$/i, 'custom-endpoints': /^endpoint kustom$/i }
async function openProviderPage(sub: string) {
  await page.evaluate(() => { window.location.hash = '#/settings?tab=providers' })
  await sleep(1500)
  const nav = page.getByText(PROVIDER_NAV[sub], { exact: false }).first()
  if (await nav.isVisible().catch(() => false)) await nav.click()
  else await page.evaluate(s => { window.location.hash = `#/settings?tab=providers&pview=${s}` }, sub)
}
for (const sub of Object.keys(PROVIDER_NAV)) await visit(`settings providers/${sub}`, () => openProviderPage(sub))

// ---- Add model, end to end, through the real form ---------------------------
async function addEndpoint(o: { name: string; url: string; key?: string; headers?: string; insecure?: boolean }) {
  await openProviderPage('custom-endpoints')
  await sleep(2500)
  if (!(await page.locator('[data-nv-field="endpoint-headers"]').isVisible().catch(() => false))) {
    fail(`add model (${o.name}): Endpoint kustom page did not open`)
    await shot(`addmodel-${o.name.replace(/\W+/g, '-').toLowerCase()}-noform.png`)
    return { model: '', cfg: fs.readFileSync(path.join(NV_HOME, 'config.yaml'), 'utf8') }
  }
  const newBtn = page.getByRole('button', { name: /new endpoint|endpoint baru/i })
  if (await newBtn.isVisible().catch(() => false)) await newBtn.click()
  const field = (label: RegExp) => page.locator('label').filter({ hasText: label }).locator('input').first()
  await field(/^name$|^nama$/i).fill(o.name)
  await field(/endpoint url|url endpoint/i).fill(o.url)
  if (o.key) await field(/api key/i).fill(o.key)
  if (o.headers) await page.locator('[data-nv-field="endpoint-headers"]').fill(o.headers)
  if (o.insecure) await page.locator('[data-nv-field="endpoint-insecure-tls"]').click()
  await page.getByRole('button', { name: /^test$|^tes/i }).click()
  for (let i = 0; i < 40; i++) {
    await sleep(500)
    const body: string = await page.evaluate(() => document.body.innerText)
    if (/models|model ditemukan|reachable|terhubung/i.test(body) && (await field(/default model|model bawaan/i).inputValue().catch(() => '')) !== '') break
  }
  const modelInput = page.locator('label').filter({ hasText: /default model|model bawaan/i }).locator('input').first()
  const model = await modelInput.inputValue().catch(() => '')
  await shot(`addmodel-${o.name.replace(/\W+/g, '-').toLowerCase()}-tested.png`)
  await page.getByRole('button', { name: /^save$|^simpan$/i }).click()
  await sleep(2500)
  await shot(`addmodel-${o.name.replace(/\W+/g, '-').toLowerCase()}-saved.png`)
  const cfg = fs.readFileSync(path.join(NV_HOME, 'config.yaml'), 'utf8')
  return { model, cfg }
}

async function chatReply(text: string, expect: string) {
  await page.evaluate(() => { window.location.hash = '#/' })
  await sleep(2000)
  const c = page.locator('[contenteditable="true"]').first()
  await c.click()
  await c.type(text)
  await page.keyboard.press('Enter')
  for (let i = 0; i < 120; i++) {
    await sleep(250)
    if ((await page.evaluate(() => document.body.innerText)).includes(expect)) return true
  }
  return false
}

const local = await addEndpoint({ name: 'LiteLLM lokal', url: `http://127.0.0.1:${localPort}` })
report.localModel = local.model
if (local.model !== 'mock-model') fail(`add model (http local): discovered model "${local.model}"`)
if (!local.cfg.includes(`http://127.0.0.1:${localPort}/v1`) || !local.cfg.includes('provider: custom:litellm-lokal')) fail('add model (http local): config not saved/selected')
report.localChat = await chatReply('Halo endpoint lokal', 'Kamu bilang: Halo endpoint lokal')
if (!report.localChat) fail('add model (http local): chat reply missing')

const remote = await addEndpoint({ name: '9router', url: `https://127.0.0.1:${tlsPort}/v1`, key: 'sk-sweep-123', headers: 'X-Router-Tenant: neo', insecure: true })
report.tlsModel = remote.model
if (remote.model !== 'mock-model') fail(`add model (https): discovered model "${remote.model}"`)
if (!remote.cfg.includes('provider: custom:9router') || remote.cfg.includes('sk-sweep-123')) fail('add model (https): config not selected or key leaked into config.yaml')
report.tlsChat = await chatReply('Halo gateway https', 'Kamu bilang: Halo gateway https')
if (!report.tlsChat) fail('add model (https): chat reply missing')
await shot('addmodel-chat-https.png')

const finalCfg = fs.readFileSync(path.join(NV_HOME, 'config.yaml'), 'utf8')
if (!finalCfg.includes('id: litellm-lokal') || !finalCfg.includes('id: 9router')) fail('both custom endpoints should stay saved')

report.consoleErrorsTotal = consoleErrors.length
report.http4xx5xx = badSince(1)
report.hermesHomeTouched = fs.existsSync(path.join(HOME, '.hermes'))
if (report.hermesHomeTouched) fail('a ~/.hermes directory was created')

await app.close().catch(() => {})
for (const k of kids) k.kill()
fs.writeFileSync(path.join(DIR, 'sweep-report.json'), JSON.stringify(report, null, 2))
console.log(JSON.stringify({ ...report, pages: undefined }, null, 2))
console.log(`pages visited: ${(report.pages as unknown[]).length}, failures: ${(report.failures as string[]).length}`)
process.exit((report.failures as string[]).length ? 1 : 0)
