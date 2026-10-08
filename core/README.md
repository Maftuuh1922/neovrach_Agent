# Neovarch core

The agent "brain" of Neovarch Agent: original Python code (MIT), about 2,000
lines, two dependencies (`aiohttp`, `PyYAML`). It runs the chat loop with tool
calling, keeps sessions, memory notes and skills under `~/.neovarch`, and serves
the desktop app and the phone remote through `neovarch serve`.

Design and wire protocol are inspired by [Hermes Agent](https://github.com/NousResearch/hermes-agent)
(Nous Research). No Hermes Agent code is included; see `../NOTICE`.

## Layout

| Module | What it does |
|---|---|
| `neovarch/paths.py` | `~/.neovarch` (or `$NEOVARCH_HOME`, `%LOCALAPPDATA%\neovarch`) and the guard that refuses every file operation on Hermes paths (`~/.hermes`, `~/.local/bin/hermes*`, `~/.local/state/hermes`) |
| `neovarch/config.py` | `config.yaml` + `.env` (API keys), provider presets, endpoint resolution, `SOUL.md` |
| `neovarch/llm.py` | streaming client for any OpenAI-compatible `/chat/completions` (text, reasoning, tool calls) |
| `neovarch/tools.py` | `shell`, `read_file`, `write_file`, `edit_file`, `web_fetch`, `memory`, `skill`; dangerous commands go through approval |
| `neovarch/store.py` | sessions (`sessions/<id>.json`) and the Kanban board (`kanban.json`) |
| `neovarch/agent.py` | the loop: stream, run tools, repeat; emits events |
| `neovarch/server.py` | `neovarch serve`: HTTP + WebSocket gateway for the desktop and phone |
| `neovarch/cli.py` | `neovarch` command line |

## Commands

```
neovarch                      # interactive chat in the terminal
neovarch -q "prompt"          # one prompt, then exit
neovarch setup                # choose a provider (openai, openrouter, groq, deepseek, ollama, custom)
neovarch config [show|get|set|path] [key] [value]
neovarch sessions [list|show|delete] [id]
neovarch serve [--host 127.0.0.1] [--port 9319] [--isolated]
neovarch uninstall [--yes]    # removes ~/.neovarch only
neovarch --version
```

`python -m neovarch …` is the same as `neovarch …` (the desktop uses this form).

## Gateway (`neovarch serve`)

* Prints `HERMES_BACKEND_READY port=<n>` when listening (the readiness line the desktop waits for).
* Auth: the desktop hands the gateway a per-launch session token; clients send it as
  `Authorization: Bearer`, `X-Hermes-Session-Token` / `X-Neovarch-Session-Token` or `?token=`. Remote mode
  (`--isolated` with a signing secret from the desktop) accepts the phone's HMAC-signed access token
  (see `../docs/remote-protocol.md`). Without any token the gateway mints one and prints it; it never runs open.
* `/api/ws`: JSON-RPC 2.0. Implemented: `ping`, `client.capabilities`,
  `session.list|active_list|create|resume|activate|status|title|save|interrupt`, `prompt.submit`,
  `approval.pending|respond`, `config.get|set`, `commands.catalog`, `profiles.list`, and the desktop's boot
  checks `setup.status`, `setup.runtime_check`, `model.options` (answered from `config.yaml`), plus "off"
  answers for features the core does not have (`pet.info`, `free_tier.status`, `wake.status`, `projects.tree`,
  `subagent.list`, `billing.state`, `plugins.manage`, …). Session info carries `desktop_contract` (the
  desktop session-protocol level this core speaks).
* REST: `/api/health`, `/api/status`, sessions, config, model info/options/set, skills, toolsets, profiles,
  Kanban (`/api/plugins/kanban/*`), a small read-only file browser (`/api/fs/*`).
* Features of Hermes Agent the core does not implement (voice, image generation, OAuth providers, MCP, cron,
  webhooks, plugins, messaging platforms) answer with empty lists, so the desktop shows them empty instead of
  failing. Any other unknown call is answered with 404 / JSON-RPC `-32601` and logged to `logs/unhandled.log`.

## Data

```
~/.neovarch/
  config.yaml  .env  SOUL.md  kanban.json
  sessions/<id>.json   memory/*.md   skills/<name>/SKILL.md   logs/
```

## Development

```
uv venv .venv && uv pip install -p .venv -e '.[test]'
.venv/bin/pytest -q
python tests/mock_llm.py --port 18080   # OpenAI-compatible mock provider for manual runs
python scripts/smoke_serve.py --port 9319   # neovarch serve + mock: session.create, prompt.submit, streamed reply + one tool call
```

`neovarch --profile <name> …` keeps that profile's data in `~/.neovarch/profiles/<name>` (the desktop passes
`--profile` when one is pinned).
