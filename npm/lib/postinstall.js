'use strict';
// Right after `npm install -g`: fetch the desktop app and install the Neovarch core
// into ~/.neovarch. Never fails the npm install: `neovarch` retries on first run.

const app = require('./app');

async function main() {
  if (process.env.NEOVARCH_SKIP_DOWNLOAD) return;
  const target = app.detectTarget();
  if (target.unsupported) {
    app.printUnsupported(target.unsupported);
  } else {
    try {
      await app.installApp(target);
    } catch (err) {
      app.log.warn(`could not download the app now (${err.message}).`);
      console.log('      It will be downloaded the first time you run: neovarch');
    }
  }
  if (!app.coreInstalled() && !process.env.NEOVARCH_SKIP_CORE) {
    try {
      await app.installCore();
    } catch (err) {
      app.log.warn(`could not install the Neovarch core now (${err.message}).`);
      console.log('      Run later: neovarch --install-core');
    }
  }
  if (!process.env.NEOVARCH_SKIP_CORE && app.install9Router()) app.setup9Router();
  console.log('Neovarch Agent is ready. Run: neovarch');
}

main().finally(() => process.exit(0));
