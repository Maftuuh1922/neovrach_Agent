#!/usr/bin/env node
'use strict';
// `neovarch`: launches the Neovarch Agent desktop app, downloading it on first run.

const fs = require('fs');
const { spawn } = require('child_process');
const app = require('../lib/app');

const HELP = `Neovarch Agent ${app.PKG_VERSION}

Usage:
  neovarch              Open Neovarch Agent (downloads it on first run)
  neovarch --update     Re-download the app for this package version
  neovarch --uninstall  Remove the downloaded app (~/.neovarch/app)
  neovarch --version    Show versions
  neovarch --help       Show this help

Environment:
  NEOVARCH_VERSION      Release tag to use, e.g. v1.1.0 (default: v${app.PKG_VERSION})
`;

async function main(argv) {
  if (argv.includes('-h') || argv.includes('--help')) { process.stdout.write(HELP); return 0; }
  if (argv.includes('--uninstall')) { app.uninstallApp(); return 0; }

  const target = app.detectTarget();
  if (argv.includes('-v') || argv.includes('--version')) {
    console.log(`neovarch-agent npm ${app.PKG_VERSION}, app ${app.installedTag() || 'not downloaded'}`);
    return 0;
  }
  if (target.unsupported) { app.printUnsupported(target.unsupported); return 1; }

  const force = argv.includes('--update');
  try {
    await app.installApp(target, { force });
  } catch (err) {
    app.log.warn(`download failed: ${err.message}`);
    console.log(`      Download it manually from ${app.RELEASES_URL}/latest`);
    return 1;
  }
  if (force) return 0;
  if (!fs.existsSync(target.exe)) { app.log.warn(`app not found at ${target.exe}`); return 1; }

  const args = argv.filter((a) => !a.startsWith('--') || a === '--');
  const child = spawn(target.exe, args, {
    cwd: app.APP_DIR,
    detached: true,
    stdio: 'ignore',
    windowsHide: false,
  });
  child.on('error', (err) => {
    app.log.warn(`could not start Neovarch Agent: ${err.message}`);
    process.exitCode = 1;
  });
  child.unref();
  return 0;
}

main(process.argv.slice(2)).then((code) => { if (code) process.exitCode = code; });
