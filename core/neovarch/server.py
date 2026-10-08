"""`neovarch serve`: the HTTP + WebSocket gateway for the desktop and phone apps.

Wire compatibility
------------------
The Neovarch desktop is derived from Hermes Desktop and the phone remote was
written against the same protocol, so this gateway speaks that wire format
(designed by Hermes Agent, Nous Research), implemented from scratch here:

* readiness line on stdout: ``HERMES_BACKEND_READY port=<n>`` (the desktop
  waits for exactly this sentinel);
* ``/api/ws``: JSON-RPC 2.0, one object per frame; server events are
  ``{"method":"event","params":{"type","session_id","payload"}}``; approvals are
  server→client requests ``{"id":"srq-…","method":"approval",…}``;
* REST under ``/api/*``; credentials are ``Authorization: Bearer <token>``,
  ``X-Hermes-Session-Token`` or ``?token=``.

Only the routes and methods the Neovarch desktop/phone actually call are
implemented; see ``UNIMPLEMENTED`` and docs in core/README.md. Unknown calls are
answered (404 / JSON-RPC -32601) and logged to ``logs/unhandled.log``.
"""

from __future__ import annotations

import asyncio
import base64
import hashlib
import hmac
import json
import os
import platform
import secrets
import socket
import sys
import time
import traceback
from pathlib import Path
from typing import Any

from aiohttp import WSMsgType, web

from neovarch import PRODUCT, __version__
from neovarch import config as cfgmod
from neovarch.agent import Agent, default_cwd
from neovarch.paths import neovarch_home
from neovarch.store import Kanban, SessionStore, summarize
from neovarch.tools import ToolContext, list_skills, tool_schemas

APPROVAL_TIMEOUT_S = 300


def _log_unhandled(kind: str, what: str) -> None:
    try:
        with (neovarch_home() / "logs" / "unhandled.log").open("a", encoding="utf-8") as fh:
            fh.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} {kind} {what}\n")
    except OSError:
        pass


# ------------------------------------------------------------------- auth -----

class Auth:
    """Local mode: the desktop passes a session token. Remote mode (--isolated
    with a basic-auth secret): the phone presents an HMAC-signed access token."""

    def __init__(self, isolated: bool):
        self.session_token = os.environ.get("HERMES_DASHBOARD_SESSION_TOKEN") or os.environ.get("NEOVARCH_SESSION_TOKEN") or ""
        secret = os.environ.get("HERMES_DASHBOARD_BASIC_AUTH_SECRET") or os.environ.get("NEOVARCH_REMOTE_SECRET") or ""
        self.secret = base64.b64decode(secret) if secret else b""
        self.isolated = isolated
        if not self.session_token and not self.secret:
            # Never run an open gateway: mint one and print it for CLI users.
            self.session_token = secrets.token_urlsafe(24)
            print(f"session token: {self.session_token}", flush=True)

    def verify_signed(self, token: str) -> bool:
        if not self.secret:
            return False
        try:
            blob = base64.urlsafe_b64decode(token + "=" * (-len(token) % 4))
        except (ValueError, TypeError):
            return False
        if len(blob) <= 32:
            return False
        raw, sig = blob[:-32], blob[-32:]
        if not hmac.compare_digest(sig, hmac.new(self.secret, raw, hashlib.sha256).digest()):
            return False
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            return False
        return payload.get("kind") == "access" and float(payload.get("exp", 0)) > time.time()

    def ok(self, request: web.Request) -> bool:
        candidates = [request.query.get("token", "")]
        auth = request.headers.get("Authorization", "")
        if auth.lower().startswith("bearer "):
            candidates.append(auth[7:].strip())
        candidates.append(request.headers.get("X-Hermes-Session-Token", ""))
        candidates.append(request.headers.get("X-Neovarch-Session-Token", ""))
        for c in filter(None, candidates):
            if self.session_token and hmac.compare_digest(c, self.session_token):
                return True
            if self.verify_signed(c):
                return True
        return False


PUBLIC = {"/api/health", "/api/status", "/api/health/idle"}


# --------------------------------------------------------------- runtime -----

class Conn:
    def __init__(self, ws: web.WebSocketResponse):
        self.ws = ws
        self.server_requests = False
        self.attached: set[str] = set()
        self.pending: dict[str, asyncio.Future] = {}
        self.lock = asyncio.Lock()

    async def send(self, obj: dict) -> None:
        if self.ws.closed:
            return
        async with self.lock:
            try:
                await self.ws.send_str(json.dumps(obj, ensure_ascii=False, default=str))
            except (ConnectionResetError, RuntimeError):
                pass


class LiveSession:
    """A conversation opened in this gateway (runtime id == stored id)."""

    def __init__(self, gw: "Gateway", rec: dict):
        self.gw = gw
        self.rec = rec
        self.id = rec["id"]
        self.task: asyncio.Task | None = None
        self.status = "idle"
        self.approvals: dict[str, dict] = {}
        self.ctx = ToolContext(cwd=Path(rec.get("cwd") or default_cwd()), approve=self.approve)
        self.agent = Agent(rec, gw.store, self.ctx, self.emit)
        self.last_text = ""

    def emit(self, kind: str, payload: dict) -> None:
        if kind == "message.complete":
            self.last_text = payload.get("text", "")
        self.gw.broadcast_event(kind, self.id, payload)

    async def approve(self, command: str, description: str, tool: str) -> str:
        rid = "apr-" + secrets.token_hex(4)
        req = {"session_id": self.id, "request_id": rid, "command": command, "description": description,
               "choices": ["once", "session", "deny"], "tool_name": tool}
        fut: asyncio.Future = asyncio.get_running_loop().create_future()
        self.approvals[rid] = {"params": req, "future": fut}
        self.gw.broadcast_event("approval.request", self.id, req)
        for conn in self.gw.conns_for(self.id):
            if conn.server_requests:
                asyncio.create_task(self.gw.server_request(conn, "approval", req, fut))
        try:
            choice = await asyncio.wait_for(asyncio.shield(fut), APPROVAL_TIMEOUT_S)
        except asyncio.TimeoutError:
            choice = "deny"
        finally:
            self.approvals.pop(rid, None)
            self.gw.broadcast_event("approval.cancelled", self.id, {"request_ids": [rid]})
        return str(choice or "deny")

    def answer(self, rid: str | None, choice: str) -> bool:
        items = [self.approvals[rid]] if rid and rid in self.approvals else list(self.approvals.values())[:1]
        for item in items:
            if not item["future"].done():
                item["future"].set_result(choice)
                return True
        return False

    def submit(self, text: str) -> None:
        async def run():
            self.status = "running"
            self.gw.broadcast_event("session.status", self.id, {"status": "running"})
            try:
                await self.agent.run_turn(text)
            except Exception as exc:  # report, keep the gateway alive
                traceback.print_exc()
                self.emit("error", {"message": f"{type(exc).__name__}: {exc}"})
                self.emit("message.complete", {"text": "", "error": str(exc)})
            finally:
                self.status = "idle"
                self.gw.broadcast_event("session.status", self.id, {"status": "idle"})
                self.gw.broadcast_event("sessions.changed", None, {})
        self.task = asyncio.create_task(run())

    def info(self) -> dict:
        return {"title": self.rec.get("title") or "", "running": self.status == "running",
                "model": self.rec.get("model") or cfgmod.resolve_endpoint(cfgmod.load_config())["model"],
                "cwd": str(self.ctx.cwd), "status": self.status}


def to_ui_messages(rec: dict) -> list[dict]:
    out = []
    for i, m in enumerate(rec.get("messages", [])):
        role = m.get("role")
        if role not in ("user", "assistant", "tool"):
            continue
        item: dict[str, Any] = {"id": f"{rec['id']}:{i}", "role": role, "content": m.get("content") or "",
                                "text": m.get("content") or "", "timestamp": m.get("ts")}
        if m.get("tool_calls"):
            item["tool_calls"] = m["tool_calls"]
        if role == "tool":
            item["tool_call_id"] = m.get("tool_call_id")
            item["name"] = m.get("name")
        if m.get("reasoning"):
            item["reasoning"] = m["reasoning"]
        out.append(item)
    return out


class Gateway:
    def __init__(self, isolated: bool):
        self.store = SessionStore()
        self.kanban = Kanban()
        self.auth = Auth(isolated)
        self.conns: set[Conn] = set()
        self.live: dict[str, LiveSession] = {}
        self.started = time.time()
        self.port = 0

    # ---- plumbing --------------------------------------------------------
    def conns_for(self, sid: str | None) -> list[Conn]:
        return [c for c in self.conns if sid is None or sid in c.attached or not c.attached]

    def broadcast_event(self, kind: str, sid: str | None, payload: dict) -> None:
        frame = {"jsonrpc": "2.0", "method": "event", "params": {"type": kind, "session_id": sid, "payload": payload}}
        for conn in list(self.conns):
            if sid is None or sid in conn.attached:
                asyncio.create_task(conn.send(frame))

    async def server_request(self, conn: Conn, method: str, params: dict, answer: asyncio.Future) -> None:
        rid = "srq-" + secrets.token_hex(6)
        fut: asyncio.Future = asyncio.get_running_loop().create_future()
        conn.pending[rid] = fut
        await conn.send({"jsonrpc": "2.0", "id": rid, "method": method, "params": params})
        try:
            result = await asyncio.wait_for(fut, APPROVAL_TIMEOUT_S)
            if not answer.done() and isinstance(result, dict) and result.get("choice"):
                answer.set_result(result["choice"])
        except (asyncio.TimeoutError, asyncio.CancelledError):
            pass
        finally:
            conn.pending.pop(rid, None)
            if answer.done():
                await conn.send({"jsonrpc": "2.0", "method": "request.cancel", "params": {"id": rid}})

    def open(self, rec: dict) -> LiveSession:
        live = self.live.get(rec["id"])
        if not live:
            live = LiveSession(self, rec)
            self.live[rec["id"]] = live
        return live

    def model_info(self) -> dict:
        cfg = cfgmod.load_config()
        ep = cfgmod.resolve_endpoint(cfg)
        return {"model": ep["model"], "provider": ep["provider"], "base_url": ep["base_url"],
                "context_length": cfgmod.get_path(cfg, "model.context_length", 128000),
                "configured": bool(ep["base_url"])}

    # ---- JSON-RPC ----------------------------------------------------------
    async def rpc(self, conn: Conn, method: str, p: dict) -> Any:
        if method == "ping":
            return {"pong": True}
        if method == "client.capabilities":
            conn.server_requests = bool(p.get("server_requests"))
            return {"ok": True, "server_requests": conn.server_requests}
        if method == "session.list":
            return {"sessions": self.store.list(limit=int(p.get("limit") or 50), offset=int(p.get("offset") or 0))}
        if method == "session.active_list":
            return {"sessions": [{**summarize(l.rec), **l.info(), "id": l.id} for l in self.live.values()
                                 if l.status == "running"]}
        if method == "session.create":
            cwd = p.get("cwd") or str(default_cwd())
            rec = self.store.create(source=str(p.get("source") or "desktop"), cwd=cwd,
                                    model=self.model_info()["model"])
            live = self.open(rec)
            conn.attached.add(live.id)
            self.broadcast_event("sessions.changed", None, {})
            return {"session_id": live.id, "stored_session_id": live.id, "messages": [], "info": live.info()}
        if method in ("session.resume", "session.activate"):
            key = str(p.get("session_id") or p.get("stored_session_id") or "")
            rec = self.live[key].rec if key in self.live else self.store.find(key)
            if not rec:
                raise RpcError(-32004, f"session not found: {key}")
            live = self.open(rec)
            conn.attached.add(live.id)
            open_requests = [{"id": rid, "method": "approval", "params": a["params"]} for rid, a in live.approvals.items()]
            return {"session_id": live.id, "stored_session_id": live.id, "messages": to_ui_messages(rec),
                    "info": live.info(), "open_requests": open_requests,
                    "pending_approval": open_requests[0]["params"] if open_requests else None}
        if method == "session.status":
            live = self._live(p)
            return live.info()
        if method == "session.title":
            live = self._live(p)
            if p.get("title"):
                live.rec["title"] = str(p["title"])
                self.store.save(live.rec)
                self.broadcast_event("session.title", live.id, {"title": live.rec["title"]})
            return {"title": live.rec.get("title") or ""}
        if method == "session.save":
            live = self._live(p)
            self.store.save(live.rec)
            return {"ok": True, "session_id": live.id}
        if method == "session.interrupt":
            live = self._live(p)
            live.agent.interrupt()
            for a in list(live.approvals.values()):
                if not a["future"].done():
                    a["future"].set_result("deny")
            return {"ok": True}
        if method == "prompt.submit":
            live = self._live(p)
            text = str(p.get("text") or "")
            if not text.strip():
                raise RpcError(-32602, "text is required")
            if live.status == "running":
                raise RpcError(-32010, "a turn is already running in this session")
            conn.attached.add(live.id)
            live.submit(text)
            return {"ok": True, "session_id": live.id, "status": "running"}
        if method == "approval.pending":
            live = self._live(p)
            return {"pending": [a["params"] for a in live.approvals.values()]}
        if method == "approval.respond":
            live = self._live(p)
            return {"ok": live.answer(p.get("request_id"), str(p.get("choice") or "deny"))}
        if method == "config.get":
            cfg = cfgmod.load_config()
            key = p.get("key")
            return {"value": cfgmod.get_path(cfg, key) if key else cfg, "config": cfg}
        if method == "config.set":
            cfg = cfgmod.load_config()
            cfgmod.set_path(cfg, str(p["key"]), p.get("value"))
            cfgmod.save_config(cfg)
            return {"ok": True}
        if method == "commands.catalog":
            return {"commands": [{"name": "new", "description": "Start a new chat"},
                                 {"name": "model", "description": "Show the configured model"}], "skills": list_skills()}
        if method == "profiles.list":
            return {"profiles": [{"name": "default", "active": True, "path": str(neovarch_home())}], "active": "default"}
        if method == "process.list":
            return {"processes": []}
        if method == "shared_metrics.status":
            return {"enabled": False, "send": False, "decided": True}
        if method.startswith("shared_metrics."):
            return {"ok": True, "enabled": False}
        if method == "complete.path":
            return {"items": self._complete_path(str(p.get("prefix") or p.get("text") or ""))}
        if method == "complete.slash":
            return {"items": []}
        if method == "reload.mcp":
            return {"ok": True, "servers": []}
        # ---- boot / readiness: the renderer asks these before it shows the composer
        if method == "setup.status":
            info = self.model_info()
            return {"provider_configured": info["configured"], "ready": info["configured"], "ok": True,
                    "other_providers": info["configured"], "free_tier_account": False, "free_tier_route": False,
                    "inference_provider": info["provider"] or None, "profile": "default"}
        if method == "setup.runtime_check":
            info = self.model_info()
            return {"ok": info["configured"], "provider": info["provider"] or None, "model": info["model"] or None,
                    "source": "config", "free_tier_route": False, "profile": "default",
                    "error": None if info["configured"] else "No model provider configured. Run `neovarch setup`."}
        if method == "model.options":
            info = self.model_info()
            name = info["provider"] or "custom"
            return {"model": info["model"], "provider": name, "providers": [{
                "slug": name, "name": name, "models": [info["model"]] if info["model"] else [],
                "total_models": 1 if info["model"] else 0, "is_current": True, "is_user_defined": True,
                "api_url": info["base_url"] or None, "authenticated": info["configured"], "source": "config"}]}
        # ---- features the Neovarch core does not have (yet): answer "off", never an error
        if method == "pet.info":
            return {"enabled": False}
        if method == "free_tier.status":
            return {"has_guest": False, "enabled": False, "available": False, "notice_pending": False,
                    "model": "", "label": ""}
        if method == "wake.status":
            return {"listening": False, "owned_by_caller": False, "phrase": "", "provider": "",
                    "configured_surface": "", "input_device": {}, "available": False,
                    "hint": "Not available in the Neovarch core.", "enabled": False, "audio_silent": False,
                    "capture": "", "local_input_available": False, "sample_rate": 0, "frame_length": 0}
        if method == "projects.tree":
            return {"projects": [], "active_id": None, "scoped_session_ids": []}
        if method == "bot_relay.roster.sync":
            return {"count": 0}
        _log_unhandled("rpc", method + " " + json.dumps(p)[:300])
        raise RpcError(-32601, f"method not implemented in the Neovarch core: {method}")

    def _live(self, p: dict) -> LiveSession:
        sid = str(p.get("session_id") or "")
        if sid in self.live:
            return self.live[sid]
        rec = self.store.find(sid)
        if not rec:
            raise RpcError(-32004, f"session not found: {sid}")
        return self.open(rec)

    def _complete_path(self, prefix: str) -> list[dict]:
        base = Path(os.path.expanduser(prefix or "."))
        folder = base if prefix.endswith(("/", os.sep)) or base.is_dir() and not prefix else base.parent
        try:
            names = sorted(folder.iterdir())[:200]
        except OSError:
            return []
        stem = "" if folder == base else base.name
        return [{"path": str(n), "name": n.name, "is_dir": n.is_dir()} for n in names if n.name.startswith(stem)][:50]


class RpcError(Exception):
    def __init__(self, code: int, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


# ------------------------------------------------------------------ HTTP -----

def build_app(gw: Gateway) -> web.Application:
    @web.middleware
    async def auth_mw(request: web.Request, handler):
        path = request.path
        if request.method == "OPTIONS":
            return web.Response(status=204, headers=_cors(request))
        if path.startswith("/api/") and path not in PUBLIC and not gw.auth.ok(request):
            return web.json_response({"detail": "Unauthorized"}, status=401, headers=_cors(request))
        try:
            resp = await handler(request)
        except web.HTTPNotFound:
            _log_unhandled("http", f"{request.method} {path}")
            resp = web.json_response({"detail": f"Not implemented in the Neovarch core: {path}"}, status=404)
        except web.HTTPException as exc:
            resp = exc
        resp.headers.update(_cors(request))
        return resp

    app = web.Application(middlewares=[auth_mw], client_max_size=64 * 1024 * 1024)
    r = app.router

    async def health(_):
        return web.json_response({"ok": True, "status": "ok", "product": "neovarch", "version": __version__})

    async def status(_):
        info = gw.model_info()
        return web.json_response({
            "ok": True, "product": PRODUCT, "name": "neovarch", "version": __version__,
            "release_date": "", "hermes_home": str(neovarch_home()), "home": str(neovarch_home()),
            "config_path": str(cfgmod.config_path()), "env_path": str(cfgmod.env_path()),
            "gateway_running": True, "gateway_state": "running", "active_sessions": sum(
                1 for l in gw.live.values() if l.status == "running"),
            "hostname": socket.gethostname(), "platform": platform.system().lower(),
            "uptime_s": round(time.time() - gw.started), "model": info["model"], "provider": info["provider"],
            "configured": info["configured"], "auth_mode": "token", "port": gw.port,
        })

    async def ws_handler(request: web.Request):
        ws = web.WebSocketResponse(heartbeat=30, max_msg_size=64 * 1024 * 1024)
        await ws.prepare(request)
        conn = Conn(ws)
        gw.conns.add(conn)
        await conn.send({"jsonrpc": "2.0", "method": "event", "params": {
            "type": "gateway.ready", "session_id": None,
            "payload": {"product": "neovarch", "version": __version__, "skin": None}}})
        try:
            async for msg in ws:
                if msg.type != WSMsgType.TEXT:
                    continue
                try:
                    frame = json.loads(msg.data)
                except json.JSONDecodeError:
                    continue
                if "method" not in frame and frame.get("id") in conn.pending:
                    fut = conn.pending.get(frame["id"])
                    if fut and not fut.done():
                        fut.set_result(frame.get("result") if "result" in frame else {"choice": "deny"})
                    continue
                asyncio.create_task(_dispatch(gw, conn, frame))
        finally:
            gw.conns.discard(conn)
        return ws

    async def sessions_list(request):
        limit = int(request.query.get("limit", 50))
        offset = int(request.query.get("offset", 0))
        items = gw.store.list(limit=limit, offset=offset)
        return web.json_response({"sessions": items, "total": len(gw.store.list(limit=100000)), "limit": limit, "offset": offset})

    async def session_get(request):
        rec = gw.store.find(request.match_info["sid"])
        if not rec:
            return web.json_response({"detail": "not found"}, status=404)
        return web.json_response({**summarize(rec), "messages": to_ui_messages(rec)})

    async def session_messages(request):
        rec = gw.store.find(request.match_info["sid"])
        if not rec:
            return web.json_response({"detail": "not found"}, status=404)
        return web.json_response({"session_id": rec["id"], "messages": to_ui_messages(rec)})

    async def session_delete(request):
        ok = gw.store.delete(request.match_info["sid"])
        gw.live.pop(request.match_info["sid"], None)
        gw.broadcast_event("sessions.changed", None, {})
        return web.json_response({"ok": ok})

    async def session_patch(request):
        rec = gw.store.find(request.match_info["sid"])
        if not rec:
            return web.json_response({"detail": "not found"}, status=404)
        body = await _json(request)
        if "title" in body:
            rec["title"] = str(body["title"] or "")
            gw.store.save(rec)
        return web.json_response({"ok": True, **summarize(rec)})

    async def config_get(_):
        return web.json_response(cfgmod.load_config())

    async def config_put(request):
        body = await _json(request)
        cfg = cfgmod.load_config()
        data = body.get("config", body)
        if isinstance(data, dict):
            cfg = cfgmod._merge(cfg, data)
            cfgmod.save_config(cfg)
        return web.json_response({"ok": True})

    async def config_defaults(_):
        return web.json_response(cfgmod.DEFAULTS)

    async def model_info(_):
        return web.json_response(gw.model_info())

    async def model_options(_):
        cfg = cfgmod.load_config()
        info = gw.model_info()
        providers = [{"name": n, "base_url": s.get("base_url", ""), "models": [s.get("model")] if s.get("model") else []}
                     for n, s in cfgmod.provider_entries(cfg).items()]
        return web.json_response({"current": info, "providers": providers,
                                  "models": [{"id": info["model"], "provider": info["provider"]}] if info["model"] else []})

    async def model_set(request):
        body = await _json(request)
        cfg = cfgmod.load_config()
        if body.get("model"):
            cfgmod.set_path(cfg, "model.default", body["model"])
        if body.get("provider"):
            cfgmod.set_path(cfg, "model.provider", body["provider"])
        cfgmod.save_config(cfg)
        return web.json_response({"ok": True, **gw.model_info()})

    async def skills(_):
        return web.json_response({"skills": list_skills()})

    async def tools(_):
        return web.json_response({"toolsets": [{"name": "core", "enabled": True,
                                                "tools": [t["function"]["name"] for t in tool_schemas()]}]})

    async def profiles(_):
        return web.json_response({"profiles": [{"name": "default", "active": True, "path": str(neovarch_home())}],
                                  "active": "default"})

    async def empty_list(request):
        key = request.path.rstrip("/").rsplit("/", 1)[-1]
        return web.json_response({key: [], "items": []})

    async def kanban_board(_):
        return web.json_response(gw.kanban.board())

    async def kanban_create(request):
        b = await _json(request)
        if not b.get("title"):
            return web.json_response({"detail": "title required"}, status=422)
        return web.json_response(gw.kanban.create(str(b["title"]), str(b.get("body") or ""), b.get("assignee"), b.get("priority")))

    async def kanban_patch(request):
        t = gw.kanban.update(request.match_info["tid"], await _json(request))
        return web.json_response(t) if t else web.json_response({"detail": "not found"}, status=404)

    async def kanban_comment(request):
        b = await _json(request)
        c = gw.kanban.comment(request.match_info["tid"], str(b.get("body") or ""))
        return web.json_response(c) if c else web.json_response({"detail": "not found"}, status=404)

    async def fs_list(request):
        p = Path(os.path.expanduser(request.query.get("path") or str(default_cwd())))
        try:
            entries = [{"name": e.name, "path": str(e), "is_dir": e.is_dir(), "type": "dir" if e.is_dir() else "file"}
                       for e in sorted(p.iterdir(), key=lambda e: (not e.is_dir(), e.name.lower()))[:2000]]
        except OSError as exc:
            return web.json_response({"detail": str(exc)}, status=400)
        return web.json_response({"path": str(p), "entries": entries})

    async def fs_read(request):
        p = Path(os.path.expanduser(request.query.get("path") or ""))
        try:
            return web.json_response({"path": str(p), "content": p.read_text(encoding="utf-8", errors="replace")[:2_000_000]})
        except OSError as exc:
            return web.json_response({"detail": str(exc)}, status=400)

    async def fs_default(_):
        return web.json_response({"path": str(default_cwd())})

    r.add_get("/api/health", health)
    r.add_get("/api/health/idle", health)
    r.add_get("/api/status", status)
    r.add_get("/api/ws", ws_handler)
    r.add_get("/api/sessions", sessions_list)
    r.add_get("/api/profiles/sessions", sessions_list)
    r.add_get("/api/sessions/{sid}", session_get)
    r.add_get("/api/sessions/{sid}/messages", session_messages)
    r.add_delete("/api/sessions/{sid}", session_delete)
    r.add_patch("/api/sessions/{sid}", session_patch)
    r.add_get("/api/config", config_get)
    r.add_put("/api/config", config_put)
    r.add_post("/api/config", config_put)
    r.add_get("/api/config/defaults", config_defaults)
    r.add_get("/api/model/info", model_info)
    r.add_get("/api/model/options", model_options)
    r.add_post("/api/model/set", model_set)
    r.add_get("/api/skills", skills)
    r.add_get("/api/tools/toolsets", tools)
    r.add_get("/api/profiles", profiles)
    for p in ("/api/cron/jobs", "/api/mcp/servers", "/api/webhooks", "/api/agents", "/api/plugins"):
        r.add_get(p, empty_list)
    r.add_get("/api/plugins/kanban/board", kanban_board)
    r.add_post("/api/plugins/kanban/tasks", kanban_create)
    r.add_patch("/api/plugins/kanban/tasks/{tid}", kanban_patch)
    r.add_post("/api/plugins/kanban/tasks/{tid}/comments", kanban_comment)
    # Boot-time REST reads for features the core does not have: valid "off" answers.
    async def profiles_active(_):
        return web.json_response({"active": "default", "current": "default"})

    async def local_models_status(_):
        return web.json_response({"enabled": False, "tag": "", "configured_tag": "", "update_available": False,
                                  "runtime_installed": False, "runtime_backend": None, "server_running": False,
                                  "server_base_url": None, "active_model_id": None, "loaded_models": {},
                                  "models": [], "models_dir": ""})

    async def local_models_jobs(_):
        return web.json_response({"jobs": []})

    async def voice_live_status(_):
        return web.json_response({"ok": False, "available": False, "reason": "Not available in the Neovarch core."})

    async def terminal_backends(_):
        return web.json_response({"active": "local", "backends": [{
            "name": "local", "label": "Local", "description": "Commands run on this computer.",
            "active": True, "status": "ready", "detail": ""}]})

    async def owner_backfill(request):
        body = await _json(request)
        return web.json_response({"ok": True, "profile": body.get("profile") or "default", "stamped": 0})

    r.add_get("/api/profiles/active", profiles_active)
    r.add_get("/api/local-models/status", local_models_status)
    r.add_get("/api/local-models/jobs", local_models_jobs)
    r.add_get("/api/audio/voice-live/status", voice_live_status)
    r.add_get("/api/tools/terminal/backends", terminal_backends)
    r.add_post("/api/sessions/owner-backfill", owner_backfill)
    r.add_get("/api/fs/list", fs_list)
    r.add_get("/api/fs/read", fs_read)
    r.add_get("/api/fs/default", fs_default)
    return app


def _cors(request: web.Request) -> dict:
    origin = request.headers.get("Origin")
    if not origin:
        return {}
    return {"Access-Control-Allow-Origin": origin, "Access-Control-Allow-Credentials": "true",
            "Access-Control-Allow-Headers": "Authorization, Content-Type, X-Hermes-Session-Token, X-Neovarch-Session-Token",
            "Access-Control-Allow-Methods": "GET, POST, PUT, PATCH, DELETE, OPTIONS"}


async def _json(request: web.Request) -> dict:
    try:
        body = await request.json()
        return body if isinstance(body, dict) else {}
    except (json.JSONDecodeError, UnicodeDecodeError):
        return {}


async def _dispatch(gw: Gateway, conn: Conn, frame: dict) -> None:
    fid = frame.get("id")
    method = str(frame.get("method") or "")
    params = frame.get("params") or {}
    try:
        result = await gw.rpc(conn, method, params if isinstance(params, dict) else {})
        if fid is not None:
            await conn.send({"jsonrpc": "2.0", "id": fid, "result": result})
    except RpcError as exc:
        if fid is not None:
            await conn.send({"jsonrpc": "2.0", "id": fid, "error": {"code": exc.code, "message": exc.message}})
    except Exception as exc:
        traceback.print_exc()
        if fid is not None:
            await conn.send({"jsonrpc": "2.0", "id": fid, "error": {"code": -32603, "message": f"{type(exc).__name__}: {exc}"}})


def serve(host: str, port: int, *, isolated: bool = False) -> int:
    async def main() -> None:
        gw = Gateway(isolated)
        runner = web.AppRunner(build_app(gw), access_log=None)
        await runner.setup()
        site = web.TCPSite(runner, host, port, reuse_address=True)
        try:
            await site.start()
        except OSError as exc:
            print(f"neovarch serve: cannot listen on {host}:{port}: {exc}", file=sys.stderr, flush=True)
            raise SystemExit(98)
        sockets = getattr(site._server, "sockets", None) or []
        gw.port = sockets[0].getsockname()[1] if sockets else port
        # The desktop waits for this exact sentinel (wire-compatible with Hermes Desktop).
        print(f"HERMES_BACKEND_READY port={gw.port}", flush=True)
        print(f"Neovarch gateway listening on {host}:{gw.port} (home {neovarch_home()})", flush=True)
        await asyncio.Event().wait()

    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
    return 0
