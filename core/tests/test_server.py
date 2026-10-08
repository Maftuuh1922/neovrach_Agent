import asyncio
import base64
import hashlib
import hmac
import json
import time

import pytest
from aiohttp.test_utils import TestClient, TestServer

from neovarch.server import Gateway, build_app


async def _client(monkeypatch, **env):
    for k, v in env.items():
        monkeypatch.setenv(k, v)
    gw = Gateway(isolated=bool(env.get("HERMES_DASHBOARD_BASIC_AUTH_SECRET")))
    client = TestClient(TestServer(build_app(gw)))
    await client.start_server()
    return gw, client


class WS:
    def __init__(self, ws):
        self.ws = ws
        self.n = 0
        self.events = []
        self.requests = []
        self.results = {}

    async def call(self, method, params=None):
        self.n += 1
        rid = self.n
        await self.ws.send_json({"jsonrpc": "2.0", "id": rid, "method": method, "params": params or {}})
        while rid not in self.results:
            await self.pump()
        return self.results.pop(rid)

    async def pump(self, timeout=10):
        msg = await self.ws.receive_json(timeout=timeout)
        if msg.get("method") == "event":
            self.events.append(msg["params"])
        elif "method" in msg:
            self.requests.append(msg)
        else:
            self.results[msg["id"]] = msg
        return msg

    async def until(self, kind, timeout=10):
        deadline = time.monotonic() + timeout
        while True:
            for e in self.events:
                if e["type"] == kind:
                    return e
            await self.pump(max(deadline - time.monotonic(), 0.1))


async def test_auth_and_public_routes(mock_provider, monkeypatch):
    gw, c = await _client(monkeypatch, HERMES_DASHBOARD_SESSION_TOKEN="tok")
    try:
        assert (await c.get("/api/status")).status == 200
        st = await (await c.get("/api/status")).json()
        assert st["product"] == "Neovarch Agent" and st["model"] == "mock-model"
        assert (await c.get("/api/sessions")).status == 401
        assert (await c.get("/api/sessions", headers={"X-Hermes-Session-Token": "tok"})).status == 200
        assert (await c.get("/api/sessions?token=tok")).status == 200
        r = await c.get("/api/does-not-exist?token=tok")
        assert r.status == 404
        assert "does-not-exist" in (gw.store.root.parent / "logs" / "unhandled.log").read_text()
    finally:
        await c.close()


async def test_ws_chat_stream_and_tool(mock_provider, monkeypatch):
    gw, c = await _client(monkeypatch, HERMES_DASHBOARD_SESSION_TOKEN="tok")
    try:
        ws = WS(await c.ws_connect("/api/ws?token=tok"))
        assert (await ws.pump())["params"]["type"] == "gateway.ready"
        created = (await ws.call("session.create", {"source": "desktop"}))["result"]
        sid = created["session_id"]
        assert created["info"]["desktop_contract"] == 8
        assert (await ws.call("prompt.submit", {"session_id": sid, "text": "halo"}))["result"]["ok"]
        done = await ws.until("message.complete")
        assert done["payload"]["text"].endswith("Kamu bilang: halo")
        assert sum(1 for e in ws.events if e["type"] == "message.delta") > 3
        ws.events.clear()
        await ws.call("prompt.submit", {"session_id": sid, "text": "jalankan tool"})
        done = await ws.until("message.complete")
        assert any(e["type"] == "tool.start" and e["payload"]["name"] == "shell" for e in ws.events)
        assert any(e["type"] == "tool.complete" and "neovarch-tool-ok" in e["payload"]["result"] for e in ws.events)
        assert done["payload"]["text"] == "Selesai. Hasil alat: neovarch-tool-ok"
        listed = (await ws.call("session.list", {}))["result"]["sessions"]
        assert listed[0]["id"] == sid and listed[0]["title"] == "halo"
        resumed = (await ws.call("session.resume", {"session_id": sid}))["result"]
        assert [m["role"] for m in resumed["messages"]] == ["user", "assistant", "user", "assistant", "tool", "assistant"]
        unknown = await ws.call("voice.speak", {})
        assert unknown["error"]["code"] == -32601
        r = await c.get(f"/api/sessions/{sid}/messages?token=tok")
        assert len((await r.json())["messages"]) == 6
        assert (await (await c.delete(f"/api/sessions/{sid}?token=tok")).json())["ok"]
    finally:
        await c.close()


async def test_approval_server_request(mock_provider, monkeypatch, tmp_path):
    monkeypatch.setenv("NEOVARCH_CWD", str(tmp_path))
    gw, c = await _client(monkeypatch, HERMES_DASHBOARD_SESSION_TOKEN="tok")
    try:
        ws = WS(await c.ws_connect("/api/ws?token=tok"))
        await ws.call("client.capabilities", {"server_requests": True})
        sid = (await ws.call("session.create", {}))["result"]["session_id"]
        await ws.call("prompt.submit", {"session_id": sid, "text": "danger please"})
        while not ws.requests:
            await ws.pump()
        req = ws.requests[0]
        assert req["method"] == "approval" and "rm -rf" in req["params"]["command"]
        pending = (await ws.call("approval.pending", {"session_id": sid}))["result"]["pending"]
        assert pending and pending[0]["request_id"] == req["params"]["request_id"]
        await ws.ws.send_json({"jsonrpc": "2.0", "id": req["id"], "result": {"choice": "deny"}})
        done = await ws.until("message.complete")
        tool_done = next(e for e in ws.events if e["type"] == "tool.complete")
        assert tool_done["payload"]["result_text"].startswith("denied")
        assert done["payload"]["text"].startswith("Selesai")
    finally:
        await c.close()


def _mint(secret: bytes, exp: float) -> str:
    raw = json.dumps({"sub": "neovarch-remote", "kind": "access", "exp": exp}, separators=(",", ":")).encode()
    return base64.urlsafe_b64encode(raw + hmac.new(secret, raw, hashlib.sha256).digest()).decode()


async def test_remote_mode_signed_token_and_kanban(home, monkeypatch):
    secret = b"s" * 32
    gw, c = await _client(monkeypatch, HERMES_DASHBOARD_BASIC_AUTH_SECRET=base64.b64encode(secret).decode())
    try:
        good = _mint(secret, time.time() + 3600)
        assert (await c.get("/api/plugins/kanban/board")).status == 401
        assert (await c.get("/api/plugins/kanban/board", headers={"Authorization": f"Bearer {_mint(secret, time.time() - 1)}"})).status == 401
        assert (await c.get("/api/plugins/kanban/board", headers={"Authorization": f"Bearer {_mint(b'x' * 32, time.time() + 99)}"})).status == 401
        h = {"Authorization": f"Bearer {good}"}
        t = await (await c.post("/api/plugins/kanban/tasks", json={"title": "Dari HP"}, headers=h)).json()
        assert (await c.patch(f"/api/plugins/kanban/tasks/{t['id']}", json={"status": "done"}, headers=h)).status == 200
        assert (await c.post(f"/api/plugins/kanban/tasks/{t['id']}/comments", json={"body": "ok"}, headers=h)).status == 200
        board = await (await c.get("/api/plugins/kanban/board", headers=h)).json()
        assert board["columns"][-1]["tasks"][0]["title"] == "Dari HP"
        ws = await c.ws_connect(f"/api/ws?token={good}")
        assert (await ws.receive_json())["params"]["type"] == "gateway.ready"
        await ws.close()
    finally:
        await c.close()


async def test_boot_endpoints_answer_quietly(mock_provider, monkeypatch):
    gw, c = await _client(monkeypatch, HERMES_DASHBOARD_SESSION_TOKEN="tok")
    try:
        ws = WS(await c.ws_connect("/api/ws?token=tok"))
        await ws.pump()
        setup = (await ws.call("setup.status", {}))["result"]
        assert setup["provider_configured"] is True and setup["ready"] is True
        check = (await ws.call("setup.runtime_check", {}))["result"]
        assert check["ok"] is True and check["model"] == "mock-model"
        opts = (await ws.call("model.options", {}))["result"]
        assert opts["model"] == "mock-model" and opts["providers"][0]["is_current"] is True
        for method, key, value in (("pet.info", "enabled", False), ("free_tier.status", "enabled", False),
                                   ("wake.status", "available", False), ("projects.tree", "projects", []),
                                   ("bot_relay.roster.sync", "count", 0)):
            assert (await ws.call(method, {}))["result"][key] == value
        for path in ("/api/profiles/active", "/api/local-models/status", "/api/local-models/jobs",
                     "/api/audio/voice-live/status", "/api/tools/terminal/backends"):
            assert (await c.get(path + "?token=tok")).status == 200, path
        r = await c.post("/api/sessions/owner-backfill?token=tok", json={})
        assert (await r.json())["stamped"] == 0
        log = gw.store.root.parent / "logs" / "unhandled.log"
        assert not log.exists() or "setup.status" not in log.read_text()
    finally:
        await c.close()
