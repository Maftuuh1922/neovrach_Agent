'use strict';
// Shared logic for the neovarch npm package: platform detection, download, unpack.
// Installs the portable Electron builds (Linux tar.gz, Windows zip) from GitHub Releases.
// Zero dependencies; Node >= 18 (global fetch).

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const REPO = 'Maftuuh1922/neovrach_Agent';
const RELEASES_URL = `https://github.com/${REPO}/releases`;
const PKG_VERSION = require('../package.json').version;

// Neovarch's own data home (same rule as the core and the desktop): NEOVARCH_HOME,
// else ~/.neovarch (%LOCALAPPDATA%\neovarch on Windows). Never ~/.hermes.
function neovarchHome() {
  if (process.env.NEOVARCH_HOME) return path.resolve(process.env.NEOVARCH_HOME);
  if (process.platform === 'win32') {
    return path.join(process.env.LOCALAPPDATA || path.join(os.homedir(), 'AppData', 'Local'), 'neovarch');
  }
  return path.join(os.homedir(), '.neovarch');
}
const HOME_DIR = neovarchHome();
const APP_DIR = path.join(HOME_DIR, 'app');
const CORE_DIR = path.join(HOME_DIR, 'neovarch-agent');
const CORE_CLI = process.platform === 'win32'
  ? path.join(CORE_DIR, 'venv', 'Scripts', 'neovarch.exe')
  : path.join(CORE_DIR, 'venv', 'bin', 'neovarch');
const VERSION_FILE = path.join(APP_DIR, '.neovarch-version');

const useColor = process.stdout.isTTY && !process.env.NO_COLOR;
const c = (code, s) => (useColor ? `\x1b[${code}m${s}\x1b[0m` : s);
const log = {
  step: (m) => console.log(`${c('1;31', '==>')} ${m}`),
  ok: (m) => console.log(`${c('32', ' ok')} ${m}`),
  warn: (m) => console.error(`${c('33', 'warn')} ${m}`),
  dim: (m) => console.log(c('2', m)),
};

/** Which release asset fits this machine, or null with a reason. */
function detectTarget() {
  const platform = process.platform;
  const arch = process.env.NEOVARCH_FORCE_ARCH || process.arch; // FORCE_ARCH: testing only
  const isX64 = arch === 'x64' || arch === 'x86_64' || arch === 'amd64';
  if (platform === 'linux' && isX64) {
    return { asset: 'neovarch-agent-linux-x64.tar.gz', exe: path.join(APP_DIR, 'neovarch-agent'), kind: 'tar' };
  }
  if (platform === 'win32' && (isX64 || arch === 'arm64')) {
    // Windows on ARM runs the x64 build under emulation.
    return { asset: 'neovarch-agent-windows-x64.zip', exe: path.join(APP_DIR, 'Neovarch Agent.exe'), kind: 'zip' };
  }
  const osName = { darwin: 'macOS', linux: 'Linux', win32: 'Windows' }[platform] || platform;
  const archName = arch === 'arm64' ? 'ARM64' : arch;
  const name = platform === 'darwin' ? 'macOS' : `${osName} ${archName}`;
  return { unsupported: name };
}

function wantedTag() {
  let v = process.env.NEOVARCH_VERSION || `v${PKG_VERSION}`;
  if (!v.startsWith('v')) v = `v${v}`;
  return v;
}

function installedTag() {
  try { return fs.readFileSync(VERSION_FILE, 'utf8').trim(); } catch { return null; }
}

function isInstalled(target) {
  return fs.existsSync(target.exe) && installedTag() === wantedTag();
}

function printUnsupported(name) {
  console.log(`Neovarch Agent for ${name} is not available yet.`);
  console.log('Builds for Linux x86_64, Windows x64 and Android are on the releases page:');
  console.log(`  ${RELEASES_URL}/latest`);
}

async function download(url, dest) {
  const res = await fetch(url, { redirect: 'follow', headers: { 'User-Agent': 'neovarch-agent-npm' } });
  if (!res.ok) throw new Error(`HTTP ${res.status} for ${url}`);
  const buf = Buffer.from(await res.arrayBuffer());
  fs.writeFileSync(dest, buf);
  return buf.length;
}

function run(cmd, args) {
  const r = spawnSync(cmd, args, { stdio: 'inherit', windowsHide: true });
  return r.status === 0;
}

function unpack(kind, archive, into) {
  if (kind === 'tar') {
    if (!run('tar', ['-xzf', archive, '-C', into])) throw new Error('tar failed to unpack the archive');
    return;
  }
  // zip on Windows: bsdtar ships with Windows 10+; fall back to PowerShell.
  if (run('tar', ['-xf', archive, '-C', into])) return;
  const ps = `Expand-Archive -LiteralPath '${archive.replace(/'/g, "''")}' -DestinationPath '${into.replace(/'/g, "''")}' -Force`;
  if (!run('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', ps])) {
    throw new Error('could not unpack the zip archive');
  }
}

function findDirContaining(root, file) {
  const candidate = path.join(root, file);
  if (fs.existsSync(candidate) && fs.statSync(candidate).isFile()) return root;
  for (const e of fs.readdirSync(root, { withFileTypes: true })) {
    if (e.isDirectory()) {
      const hit = findDirContaining(path.join(root, e.name), file);
      if (hit) return hit;
    }
  }
  return null;
}

function hasLinuxLib(soname) {
  const r = spawnSync('sh', ['-c', `ldconfig -p 2>/dev/null | grep -q '${soname}'`]);
  if (r.status === 0) return true;
  return ['/usr/lib', '/usr/lib64', '/usr/lib/x86_64-linux-gnu', '/lib/x86_64-linux-gnu', '/usr/local/lib']
    .some((d) => fs.existsSync(path.join(d, soname)));
}

function checkRuntime() {
  if (process.platform !== 'linux') return;
  const missing = [];
  if (!hasLinuxLib('libgtk-3.so.0')) missing.push('gtk3');
  if (!hasLinuxLib('libnss3.so')) missing.push('nss');
  if (!hasLinuxLib('libasound.so.2')) missing.push('alsa');
  if (!hasLinuxLib('libsecret-1.so.0')) missing.push('libsecret');
  if (missing.length) {
    log.warn(`missing runtime libraries: ${missing.join(' ')}`);
    console.log('      Debian/Ubuntu: sudo apt-get install -y libgtk-3-0 libnss3 libasound2 libsecret-1-0');
    console.log('      Fedora:        sudo dnf install -y gtk3 nss alsa-lib libsecret');
    console.log('      Arch:          sudo pacman -S --needed gtk3 nss alsa-lib libsecret');
  }
}

/**
 * Linux: Chromium needs a root-owned setuid chrome-sandbox or unprivileged user
 * namespaces (restricted by default on Ubuntu 23.10+). When neither is there,
 * the launcher starts the app with --no-sandbox.
 */
function needsNoSandbox() {
  if (process.platform !== 'linux') return false;
  const sb = path.join(APP_DIR, 'chrome-sandbox');
  try {
    const st = fs.statSync(sb);
    if (st.uid === 0 && (st.mode & 0o4000)) return false;
  } catch {
    return false;
  }
  const r = spawnSync('unshare', ['--user', '--map-root-user', 'true'], { stdio: 'ignore' });
  return r.status !== 0;
}

/** Download and install the app into ~/.neovarch/app. */
async function installApp(target, { force = false } = {}) {
  if (!force && isInstalled(target)) return false;
  const tag = wantedTag();
  // The package version pins the release (v<package version>); NEOVARCH_VERSION overrides it.
  const url = `${RELEASES_URL}/download/${tag}/${target.asset}`;

  log.step(`Downloading Neovarch Agent (${tag})`);
  log.dim(`    ${url}`);
  fs.mkdirSync(HOME_DIR, { recursive: true });
  const tmp = fs.mkdtempSync(path.join(HOME_DIR, '.tmp-'));
  try {
    const archive = path.join(tmp, target.asset);
    const bytes = await download(url, archive);
    log.ok(`downloaded ${(bytes / 1048576).toFixed(1)} MB`);

    log.step('Unpacking');
    const out = path.join(tmp, 'x');
    fs.mkdirSync(out);
    unpack(target.kind, archive, out);
    const src = findDirContaining(out, path.basename(target.exe));
    if (!src) throw new Error(`archive layout unexpected (no ${path.basename(target.exe)})`);

    fs.rmSync(APP_DIR, { recursive: true, force: true });
    fs.renameSync(src, APP_DIR);
    if (process.platform !== 'win32') fs.chmodSync(target.exe, 0o755);
    fs.writeFileSync(VERSION_FILE, `${tag}\n`);
    log.ok(`installed to ${APP_DIR}`);
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
  checkRuntime();
  return true;
}

// ---- core ------------------------------------------------------------------

function coreInstalled() {
  // An install of the original core: its CLI module and the venv entry point.
  return fs.existsSync(CORE_CLI) && fs.existsSync(path.join(CORE_DIR, 'neovarch', 'cli.py'));
}

/** Run scripts/install.sh --core-only (install.ps1 -CoreOnly on Windows) from this repo. */
async function installCore() {
  const win = process.platform === 'win32';
  const script = win ? 'install.ps1' : 'install.sh';
  const refs = [...new Set([process.env.NEOVARCH_REF, wantedTag(), 'main'].filter(Boolean))];
  fs.mkdirSync(HOME_DIR, { recursive: true });
  const tmp = fs.mkdtempSync(path.join(HOME_DIR, '.tmp-'));
  try {
    const dest = path.join(tmp, script);
    let ref = null;
    for (const candidate of refs) {
      try {
        await download(`https://raw.githubusercontent.com/${REPO}/${candidate}/scripts/${script}`, dest);
        ref = candidate;
        break;
      } catch {
        // this tag has no core installer yet; try the next ref
      }
    }
    if (!ref) throw new Error(`could not download scripts/${script}`);
    log.step(`Installing the Neovarch core (${ref}) into ${CORE_DIR}`);
    // The core installer ignores HERMES_* by itself; drop them here too.
    const env = { ...process.env, NEOVARCH_REF: ref, NEOVARCH_HOME: HOME_DIR };
    for (const k of Object.keys(env)) if (k.startsWith('HERMES_')) delete env[k];
    const r = win
      ? spawnSync('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', dest, '-CoreOnly'], { stdio: 'inherit', env, windowsHide: true })
      : spawnSync('sh', [dest, '--core-only'], { stdio: 'inherit', env });
    if (r.status !== 0) throw new Error(`core installer exited with ${r.status}`);
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

/** Remove everything Neovarch owns: the data home and the `neovarch` shim that points into it. */
function uninstallAll() {
  const shim = path.join(os.homedir(), '.local', 'bin', 'neovarch');
  try {
    const target = fs.readlinkSync(shim);
    if (path.resolve(path.dirname(shim), target).startsWith(HOME_DIR + path.sep)) {
      fs.unlinkSync(shim);
      log.ok(`removed ${shim}`);
    }
  } catch {
    // no shim, or not ours
  }
  if (path.basename(HOME_DIR).toLowerCase().includes('hermes') || HOME_DIR === os.homedir()) {
    throw new Error(`refusing to remove ${HOME_DIR}`);
  }
  if (fs.existsSync(HOME_DIR)) {
    fs.rmSync(HOME_DIR, { recursive: true, force: true });
    log.ok(`removed ${HOME_DIR}`);
  } else {
    console.log('Neovarch Agent is not installed.');
  }
  console.log('A Hermes Agent install, if any, was not touched.');
  console.log('To remove the command too: npm uninstall -g neovarch-agent');
}

module.exports = {
  APP_DIR, HOME_DIR, CORE_DIR, CORE_CLI, RELEASES_URL, PKG_VERSION,
  detectTarget, installApp, uninstallAll, installCore, coreInstalled, isInstalled, installedTag, wantedTag, printUnsupported, needsNoSandbox, log,
};
