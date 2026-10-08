# Neovarch Agent — Desktop

The desktop app is the core of Neovarch Agent: an Electron + Vite + React +
TypeScript app (chat-first, left sidebar with sessions, skills, cron,
profiles, settings, previews and a file browser). The phone app is a remote
for it.

It is a fork of **Hermes Desktop** by Nous Research (MIT) — see `NOTICE` and
`LICENSE` — and it drives the **Hermes Agent** Python core (`hermes serve` /
gateway), which we call the *Neovarch core*.

## Layout

This directory keeps the upstream workspace layout so relative imports keep
working:

```
desktop/
  package.json, package-lock.json   npm workspace root (apps/desktop, apps/shared)
  apps/desktop/                       the Electron app (electron/, src/, scripts/)
  apps/shared/                        @hermes/shared (transport, theme presets, i18n helpers)
  scripts/                            build helpers the app imports (msix-shared, build/*)
  tests/, tests-js/                   fixtures used by the unit/e2e tests
  HERMES_CORE_COMMIT                  upstream Hermes Agent revision the first-run
                                      bootstrap installs (matches this fork)
  tools/                              Neovarch rebrand + icon generation helpers
```

## Develop

Requires Node 22.22+ and npm 11 (npm 10 cannot install this lockfile).

```bash
cd desktop
npm ci
cd apps/desktop
npm run dev              # Vite renderer + Electron; boots the Hermes Agent core
npm run typecheck
npm run test:ui          # vitest (jsdom)
npm run test:desktop:platforms
```

## Package

```bash
cd desktop/apps/desktop
npm run build
npx electron-builder --config electron-builder.config.cjs --linux AppImage tar.gz deb --x64 --publish never
npx electron-builder --config electron-builder.config.cjs --win nsis zip --x64 --publish never
```

CI does this in `.github/workflows/desktop-electron.yml`.

## Runtime (Neovarch core)

On first launch, if no Hermes Agent install or saved remote gateway is found,
the app offers to connect to an existing gateway or to install the Neovarch
core (Hermes Agent) locally. The installer is Hermes Agent's own
`scripts/install.sh` / `install.ps1`, pinned to `HERMES_CORE_COMMIT`. User data
lives in `HERMES_HOME` (default `~/.hermes`, `%LOCALAPPDATA%\hermes` on Windows),
shared with the `hermes` CLI.
