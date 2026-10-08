# Neovarch Agent (desktop app)

Electron + Vite + React + TypeScript desktop app for Neovarch Agent, derived
from Hermes Desktop by Nous Research (MIT, see `../../LICENSE` and
`../../NOTICE`). Workspace setup, build and packaging: `../../README.md`.

The app has three boundaries (unchanged from upstream):

- **Electron** (`electron/`) resolves and validates a runnable backend, owns
  native filesystem/git/window capabilities, and exposes a narrow preload bridge.
- **React** (`src/`) owns the routes, panes, interaction state and the
  `@assistant-ui/react` transcript.
- **Neovarch core (Hermes Agent)** runs as a headless `hermes serve` process
  and exposes the `tui_gateway` JSON-RPC/WebSocket API; the renderer talks to
  it through `../shared` (`@hermes/shared`).

Engineering and design rules inherited from upstream still apply:
[`AGENTS.md`](./AGENTS.md), [`DESIGN.md`](./DESIGN.md),
[`ENGINEERING.md`](./ENGINEERING.md). The default theme is the `neovarch`
preset (`../shared/src/theme-presets.ts`, `src/themes/presets.ts`).

Boot logs: `HERMES_HOME/logs/desktop.log`.
