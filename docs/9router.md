# 9Router integration — gateway API contract (v1)

Branch: `feature-9router` (from `neovarch-office`). Core: `core/neovarch/router9.py`,
`core/neovarch/models.py`, routes in `core/neovarch/server.py`.
Status: implemented in the core (router9.py, models.py, server.py).


All endpoints sit on the existing Neovarch gateway (default `http://127.0.0.1:9319`) with the
existing auth (the same token/pairing the desktop and phone already use). Every event is
broadcast through the existing realtime bus: WebSocket `/api/ws` JSON-RPC notification
`{"method":"event","params":{"type":<name>,"session_id":null,"payload":{...},"seq":n}}`
and SSE `/api/events` (`event: <name>`, `id: <seq>`). All 9Router events have
`session_id: null`, so every client receives them.

## Concepts

* **9Router** — local OpenAI-compatible router (https://9router.com, MIT,
  `npm i -g 9router`). Neovarch treats it as the built-in provider with slug **`9router`**.
  Base URL default `http://localhost:20128/v1` (configurable: `router9.base_url` in
  `~/.neovarch/config.yaml`, or env `NEOVARCH_9ROUTER_URL`). Dashboard = base root +
  `/dashboard` (e.g. `http://localhost:20128/dashboard`).
* **Model id** — exactly the id 9Router's `GET /v1/models` returns, `<alias>/<model>`,
  e.g. `oc/big-pickle` (OpenCode Free), `kr/claude-sonnet-4.5` (Kiro), or a combo name.
* **Default model (global)** — `9router` + **`oc/big-pickle`** (OpenCode Free, no account,
  no API key from the user). If the live OpenCode Free list no longer contains it, the core
  falls back in order: `oc/nemotron-3-ultra-free`, `oc/ling-3.1-flash-free`,
  `oc/mimo-v2.6-flash-free`, then the first `oc/*-free` model in the live list.
* **Agent id** — the Office desk id from `GET /api/office` → `agents[].id`:
  `session:<session_id>` or `kanban:<assignee>`. A bare session id is also accepted and
  normalised to `session:<id>`.
* **Per-agent model** — optional override `{model, provider}` per agent id; when absent the
  agent uses the global default. Stored in `config.yaml` under `agents.models`.
  The override is applied when that agent's session runs its next turn.

## Shapes

```ts
type RouterState = 'running' | 'stopped' | 'starting' | 'not_installed' | 'error'

interface RouterStatus {
  state: RouterState
  installed: boolean          // 9router binary found on PATH (or router9.command)
  running: boolean            // GET <root>/api/health answered
  managed: boolean            // this core started the process (and supervises it)
  pid: number | null          // pid when managed
  base_url: string            // e.g. "http://localhost:20128/v1"
  dashboard_url: string       // e.g. "http://localhost:20128/dashboard"
  version: string | null      // 9router version from GET <root>/api/version, when running
  binary: string | null       // resolved path of the 9router command
  has_api_key: boolean        // Neovarch holds a 9Router API key (auto-provisioned or pasted)
  autostart: boolean          // core starts 9router when installed and not running (default true)
  error: string | null        // last start/health error (Indonesian text)
  setup: {
    ready: boolean            // can chat right now with the default model
    // what the UI should prompt for when not ready:
    //  'install'   -> show install command (npm i -g 9router) / "Pasang 9Router"
    //  'start'     -> show "Jalankan" button (POST /api/router/start)
    //  'api_key'   -> show "Buka dashboard 9Router" + paste-key field (PUT /api/router/config)
    //  'provider'  -> show "Buka dashboard 9Router" (connect a provider there)
    //  null        -> nothing to do
    action: 'install' | 'start' | 'api_key' | 'provider' | null
    message: string | null    // Indonesian, ready to display
    action_url: string | null // dashboard deep link for 'api_key'/'provider'
    install_command: string   // "npm install -g 9router"
  }
}

interface ModelEntry {
  id: string                  // send this back as `model`
  label: string               // display name (id without alias, prettified)
  provider: string            // "9router" | preset slug ("openai", ...) | "custom:<id>"
  provider_label: string      // "9Router", "OpenAI", ...
  group: string               // 9Router alias group: "OpenCode Free", "Kiro", ... (or provider_label)
  alias: string | null        // 9Router alias prefix ("oc", "kr", ...) or null
  free: boolean               // OpenCode Free / other no-cost tiers
  recommended: boolean        // true for the chosen default
  context_length: number | null
  owned_by: string | null
}

interface ModelRef { model: string; provider: string }
```

## REST endpoints

| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/api/router/status` | – | `RouterStatus` |
| POST | `/api/router/start` | `{}` | `RouterStatus` (after up to ~20 s wait for health) — 409 `{error}` if not installed |
| POST | `/api/router/stop` | `{}` | `RouterStatus` — only stops a process this core started (`managed`), otherwise 409 |
| PUT | `/api/router/config` | `{base_url?: string, api_key?: string, autostart?: boolean}` | `RouterStatus` (empty `api_key` "" clears it) |
| POST | `/api/router/provision` | `{}` | `RouterStatus` — retries the automatic API-key setup |
| GET | `/api/models` | query `refresh=1` forces re-fetch (cache 30 s) | `{models: ModelEntry[], default: ModelRef, router: RouterStatus, fetched_at: number, error: string\|null}` |
| GET | `/api/models/default` | – | `ModelRef & {source: 'config'\|'builtin'}` |
| PUT | `/api/models/default` | `{model: string, provider?: string}` (provider defaults to `"9router"` when the id is in the 9Router list, else the current provider) | `ModelRef & {ok: true}` |
| GET | `/api/agents/models` | – | `{default: ModelRef, agents: {[agent_id]: AgentModel}}` (only agents with an override) |
| GET | `/api/agents/{agent_id}/model` | – | `AgentModel` |
| PUT | `/api/agents/{agent_id}/model` | `{model: string\|null, provider?: string}` — `null`/`""` clears the override | `AgentModel & {ok: true}` |
| DELETE | `/api/agents/{agent_id}/model` | – | `AgentModel & {ok: true}` (override cleared) |

```ts
interface AgentModel {
  agent_id: string            // normalised "session:<id>" / "kanban:<name>"
  model: string               // effective model (override, else global default)
  provider: string            // effective provider
  override: ModelRef | null   // null when following the global default
  source: 'agent' | 'global'
}
```

`agent_id` in the path is URL-encoded (`session%3Aabc123`; a raw `:` also works).
Errors: `400 {error}` invalid body, `404 {error}` unknown route; messages are Indonesian.

## JSON-RPC (WebSocket `/api/ws`) — same data, for the phone

| method | params | result |
|---|---|---|
| `router.status` | `{}` | `RouterStatus` |
| `router.start` | `{}` | `RouterStatus` |
| `router.stop` | `{}` | `RouterStatus` (error -32010 when not started by Neovarch) |
| `router.config` | `{base_url?, api_key?, autostart?}` | `RouterStatus` |
| `router.provision` | `{}` | `RouterStatus` |
| `models.list` | `{refresh?: boolean}` | same as `GET /api/models` |
| `models.default.get` | `{}` | `ModelRef & {source}` |
| `models.default.set` | `{model, provider?}` | `ModelRef & {ok}` |
| `agent.model.get` | `{agent_id}` | `AgentModel` |
| `agent.model.set` | `{agent_id, model\|null, provider?}` | `AgentModel & {ok}` |

The existing `model.options` / `model.set` RPCs keep working; `model.options` now lists the
`9router` provider (with its live models) first.

## Desktop composer picker (existing wire, now 9Router-aware)

The desktop has ONE model selector: the composer picker. It keeps using its existing wire:

* `model.options {session_id?, refresh?}` — providers list with **`9router` first**
  (`models` = live 9Router ids, plus `free_models: string[]` and `status: RouterStatus`
  on that row). With `session_id`, `model`/`provider`/`is_current` reflect that session's
  effective model. `refresh: true` re-fetches 9Router's list (and starts 9Router if allowed).
* `config.set {session_id, key:"model", value:"<model> --provider <p> [--session]"}` — sets
  THAT session's agent model (per-agent override); answers `{ok, scope:"session", model, provider}`
  and emits `session.info` (with `model` + `provider`), `agent.model.changed`, `office.update`.
  `--global` (or no `session_id`) changes the global default instead.
* `session.create {model?, provider?}` — the new chat's agent gets that model as its own.
* `session.info` payloads now always carry `provider` next to `model`.

## Events (all `session_id: null`)

| type | payload | when |
|---|---|---|
| `router.status` | `RouterStatus` | 9Router state changes (started, stopped, crashed, became reachable, key provisioned) |
| `models.changed` | `{count: number, fetched_at: number}` | the live model list was re-fetched and differs from the previous one — refetch `GET /api/models` |
| `model.default.changed` | `ModelRef` | global default changed (also still emits legacy `model.changed`) |
| `agent.model.changed` | `AgentModel` | an agent override set or cleared |
| `office.update` | Office snapshot | follows every default/agent model change; each `agents[]` desk now carries `model` (effective), `model_override: ModelRef\|null`, `model_source: 'agent'\|'global'` |

## Office snapshot additions

Each `agents[]` entry in `GET /api/office` / `office.update`:

```ts
model: string                    // effective model this agent will use next turn
model_provider: string
model_override: ModelRef | null
model_source: 'agent' | 'global'
```

The snapshot root gains `default_model: ModelRef`.

## Setup flow the UI should implement

1. `GET /api/router/status`.
2. `setup.ready` → nothing; show "9Router berjalan · <version>" and the model picker.
3. `setup.action`:
   * `install` → label "9Router belum terpasang", show `npm install -g 9router` (copy) and a
     link to https://9router.com.
   * `start` → "9Router berhenti" + button **Jalankan** (`POST /api/router/start`).
   * `api_key` / `provider` → one-tap **Buka dashboard 9Router** opening `setup.action_url`
     (desktop: `shell.openExternal`; phone: the URL is on the PC, so show it as text / open
     only if the phone is on the same machine) + `setup.message`.
4. Listen to `router.status` events to update without polling.

## How the core gets a 9Router API key without the user

9Router requires an API key on `/v1/chat/completions` by default (`requireApiKey: true`).
The core, on the same machine, computes 9Router's local CLI token exactly like the
`9router` CLI does — `sha256(machine_id + "9r-cli-auth" + cli_secret)[:16]` from
`<9router data dir>/machine-id` and `<data dir>/auth/cli-secret` (data dir: `$DATA_DIR`,
else `~/.9router`, Windows `%APPDATA%\9router`) — and with header `x-9r-cli-token` calls
`GET /api/keys` (reuse a key named `neovarch`) or `POST /api/keys {"name":"neovarch"}`.
A fresh 9Router writes `machine-id` and `auth/cli-secret` only the first time it checks a CLI
token, so when they are missing the core first sends one request with a dummy
`x-9r-cli-token` (it gets 401 and the files now exist), then derives the real token.
The key is stored in `~/.neovarch/.env` as `NEOVARCH_9ROUTER_API_KEY`. If that fails,
`setup.action = 'api_key'` and the UI shows the dashboard prompt + paste field.

OpenCode Free is a no-auth provider in 9Router: it needs no connection, so it is usable as
soon as 9Router runs. The core also registers the live OpenCode Free model ids as custom
models (`POST /api/models/custom {providerAlias:"oc", id}`) so they appear in `/v1/models`.

## Verified against 9router 0.5.99 (2026-10-09)

* The core spawns `9router --tray --no-browser --skip-update -p <port> -H 127.0.0.1`; it is
  reachable on `127.0.0.1`/`localhost` only (not `[::1]`, not the LAN IP).
* `/v1/models` needs no key; `/v1/chat/completions` needs an API key even from loopback
  (`requireApiKey`, 401 "Missing API key"). Bound to `0.0.0.0`, a request from the LAN IP is
  refused earlier by 9Router's local-request check ("API key required for remote API access").
* OpenCode Free models answer without any account; they can return HTTP 429
  (`FreeUsageLimitError`) when the free quota for that model is used up — the chat then shows
  an Indonesian hint to retry or pick another model in the composer picker.
