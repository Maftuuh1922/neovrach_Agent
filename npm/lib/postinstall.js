'use strict';
// Fetches the Neovarch Agent desktop app right after `npm install -g`.
// Never fails the npm install: if anything goes wrong, `neovarch` retries on first run.

const app = require('./app');

async function main() {
  if (process.env.NEOVARCH_SKIP_DOWNLOAD) return;
  const target = app.detectTarget();
  if (target.unsupported) {
    app.printUnsupported(target.unsupported);
    return;
  }
  try {
    await app.installApp(target);
    console.log('Neovarch Agent is ready. Run: neovarch');
  } catch (err) {
    app.log.warn(`could not download the app now (${err.message}).`);
    console.log('      It will be downloaded the first time you run: neovarch');
  }
}

main().finally(() => process.exit(0));
