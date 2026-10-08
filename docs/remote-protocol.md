# Neovarch Remote — phone ↔ desktop protocol

**Product split:** the agent runs in the **Neovarch desktop app** (a fork of Hermes Desktop: Electron + React
driving the Hermes Agent Python core). The **phone app (Android/iOS, this Flutter project) is a remote only**:
no local agent runtime, no provider/API-key settings, no local tools. It talks to the gateway the desktop
already runs — the Hermes `tui_gateway` JSON-RPC API on `/api/ws` plus a few dashboard REST routes. There is
**no Neovarch-specific server**; anything a stock `hermes serve` / `hermes dashboard` exposes works.

Code: `lib/remote/` (`pairing.dart`, `remote_gateway.dart`, `remote_transcript.dart`, `remote_controller.dart`,
`saved_desktops.dart`, `ui/`). Transport reuses `lib/data/gateway_client.dart`. Tests:
`test/remote_gateway_test.dart` (in-process mock gateway).

---

## 1. Pairing payload (what the desktop must show)

The desktop's **Remote / Perangkat** screen shows a QR and the same data as text. The phone accepts any of:

| Form | Example |
|---|---|
| **Pairing URI (preferred)** | `neovarch://pair?v=1&url=http%3A%2F%2F192.168.1.5%3A9119&token=<token>&name=PC%20Kantor&profile=default` |
| JSON | `{"url":"http://192.168.1.5:9119","token":"<token>","name":"PC Kantor","profile":"default","headers":{"CF-Access-Client-Id":"…"}}` |
| Dashboard URL with token | `http://192.168.1.5:9119/?token=<token>` |
| WebSocket URL | `ws://192.168.1.5:9119/api/ws?token=<token>` |
| Manual | address `192.168.1.5:9119` (port defaults to **9119**, scheme to `http`) + token typed separately |

Fields: `url` = gateway HTTP origin (optionally with a base path behind a reverse proxy; `ws(s)` and a trailing
`/api/ws` are normalized away), `token` = gateway auth token, `name` = label, `profile` = Hermes profile to pass
on every RPC (optional), `headers` = extra headers for access proxies (optional, JSON form only).

The phone stores `url/name/profile/headers` in shared_preferences and the **token in
flutter_secure_storage** (`remote.token.<desktopId>`). "Lupakan" deletes both.

### What the desktop does (Neovarch Desktop, `desktop/apps/desktop/electron/neovarch-remote.ts`)
Settings ▸ **Remote / Perangkat** ("Aktifkan akses remote"):
1. The desktop's own backend stays on `127.0.0.1` (loopback peers only). The Hermes core refuses any
   non-loopback bind without a dashboard auth provider (`--insecure` is a no-op since the June 2026
   hardening), so the desktop spawns a **second** process
   `hermes serve --host 0.0.0.0 --port 9119 --isolated` with the core's bundled password provider
   enabled through env: `HERMES_DASHBOARD_BASIC_AUTH_USERNAME=neovarch-remote`, a random never-shown
   `…_PASSWORD`, and `…_SECRET=<base64 32-byte secret>` stored in the desktop's userData
   (`neovarch-remote.json`, mode 0600).
2. The phone token is minted by the desktop in the exact format of the provider's `verify_session`:
   `urlsafe_b64encode(json.dumps({"sub":"neovarch-remote","kind":"access","exp":…}, separators=(",",":")) + HMAC_SHA256(secret, json))`
   (padding kept, signature appended without separator). It is accepted as `Authorization: Bearer` on REST
   and as `?token=` on `/api/ws` (gated mode). `X-Hermes-Session-Token` is ignored in gated mode (harmless).
3. The screen shows the QR (`neovarch://pair?v=1&url=http://<LAN-IP>:9119&token=…&name=<PC>&profile=<profile>`),
   address + token with copy buttons, a LAN-IP picker when the PC has several addresses, a connection check
   (`GET /api/plugins/kanban/board` with the phone token via the LAN address) and **Buat token baru**
   (new secret → gateway restart → every paired phone must re-scan). The process stops on quit and
   auto-starts on launch when left enabled.
4. Kanban is a bundled plugin and answers by default; status changes follow the board's own rules
   (e.g. `running` only via the dispatcher, some transitions answer 400/409 — the phone shows the error).

---

## 2. Transport & auth

* WebSocket: `ws(s)://<host>:<port>/api/ws?token=<token>` (native builds also send
  `Authorization: Bearer <token>` + any extra headers). JSON-RPC 2.0, one JSON object per frame.
* REST: same origin, headers `X-Hermes-Session-Token: <token>` **and** `Authorization: Bearer <token>`.
* First frame from the server: event `gateway.ready`.
* Right after connecting the phone calls **`client.capabilities {server_requests: true}`** —
  without it the gateway never sends approval requests to this connection (it fails them fast instead).
* Heartbeat: `ping` every 15 s; a missed pong closes the socket and starts reconnect.
* Reconnect: backoff 1 → 2 → 4 → 8 → 15 → 30 s; on reconnect the open chat is re-attached with
  `session.resume` (which also returns still-open server requests, i.e. approvals that were waiting).
* Frames: request `{jsonrpc, id, method, params}` → `{id, result}` | `{id, error:{code,message}}`;
  notification `{method:"event", params:{type, session_id, payload}}`; server→client request
  `{id:"srq-…", method, params}` answered with `{id, result}` (non-approval requests are declined `-32601`).

## 3. Methods the phone uses

| Purpose | Call |
|---|---|
| list chats | `session.list {limit, profile?}` → `{sessions:[{id,title,preview,message_count,last_active}]}` |
| what's running | `session.active_list {profile?}` → `{sessions:[{id,title,status,model,preview,…}]}` |
| open / re-attach | `session.resume {session_id:<stored id or exact title>, source:"mobile"}` → runtime `session_id`, `stored_session_id`, `messages[]`, `info{title,running}`, `open_requests[]`, `pending_approval` |
| new chat | `session.create {source:"mobile", profile?}` → `{session_id, stored_session_id, messages}` |
| send a command | `prompt.submit {session_id:<runtime id>, text, surface:"mobile"}` |
| stop | `session.interrupt {session_id}` |
| approvals (fallback) | `approval.pending {session_id}`; `approval.respond {session_id, request_id, choice}` (300 s timeout) |
| liveness | `ping` → `{pong:true}` |
| desktop status | `GET /api/status` (public) |
| Kanban | `GET /api/plugins/kanban/board`; `PATCH /api/plugins/kanban/tasks/{id} {status}`; `POST /api/plugins/kanban/tasks {title, body?, assignee?, priority?}`; `POST /api/plugins/kanban/tasks/{id}/comments {body}` |

## 4. Streamed agent events (session-scoped)

`message.start` · `message.delta {text}` · `reasoning.delta` / `thinking.delta {text}` ·
`tool.start {tool_id, name, args_text|preview|args}` · `tool.complete {tool_id, name, summary, result_text, duration_s}` ·
`session.title {title}` · `message.complete {text, usage{avg_tps, context_percent}, error?}` · `error {message}` ·
`sessions.changed` (reload list). They are folded into chat rows by `RemoteTranscript` (thinking block, live
tool rows, markdown answer) — the same widgets the desktop-style chat uses.

## 5. Approvals

* Arrive as server→client request **`approval`**: `{id:"srq-…", params:{session_id, request_id, command,
  description, choices:["once","session","always","deny"], tool_name}}`.
* The phone shows them in the **Setujui** tab (badge), inline in the chat of that session, and as an Android
  notification (via the app's `neovarch/device` channel; iOS: in-app only for now).
* Answer: JSON-RPC result `{choice}` on the same id (exactly what Hermes Desktop does). If the approval came
  from `approval.pending`/`pending_approval` (no request id), the phone calls `approval.respond` instead.
* Withdrawn by `request.cancel {id}` or `approval.cancelled {request_ids}` (answered elsewhere, timeout,
  interrupt) — the card disappears.
* Visibility: the gateway sends a session's approvals to connections attached to that session. The phone
  attaches to the chat it has open (and re-attaches on reconnect); approvals of other desktop sessions show up
  once that session is opened on the phone (`session.resume` returns them). A desktop-side broadcast of all
  pending approvals to paired phones would be a desktop-fork feature.

## 6. Security notes

* Token = full control of the agent on the PC (tools, terminal, files). It travels in the URL/headers; on a
  plain-`http` LAN it is visible to anyone sniffing that network → use Tailscale/WireGuard or TLS (`https`/`wss`
  URLs are supported as-is).
* Revocation in v1 = rotate the desktop's token (all phones must re-pair). Per-device tokens need the desktop's
  gated auth mode (one user session per phone).
