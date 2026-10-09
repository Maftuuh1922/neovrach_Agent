"""Chat attachments from the phone: POST /api/uploads, downloads, and how the
uploaded image / file reaches the model (vision data URL or notice + path)."""

import asyncio
import base64
import json

import pytest
from aiohttp import FormData, web
from aiohttp.test_utils import TestClient, TestServer

from neovarch import config as cfgmod
from neovarch.server import Gateway, build_app

PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")
H = {"Authorization": "Bearer tok"}


@pytest.fixture
async def capture(home):
    """OpenAI-compatible provider that records every request body."""
    seen: list[dict] = []

    async def completions(request):
        seen.append(await request.json())
        return web.json_response({"choices": [{"message": {"role": "assistant", "content": "siap"},
                                               "finish_reason": "stop"}], "usage": {}})

    app = web.Application()
    app.router.add_post("/v1/chat/completions", completions)
    server = TestServer(app)
    await server.start_server()
    cfg = cfgmod.load_config()
    cfg["model"] = {"provider": "custom", "default": "gpt-4o-mini", "base_url": str(server.make_url("/v1")),
                    "context_length": 1000}
    cfgmod.save_config(cfg)
    yield seen
    await server.close()


async def _client(monkeypatch):
    monkeypatch.setenv("NEOVARCH_SESSION_TOKEN", "tok")
    gw = Gateway(isolated=False)
    c = TestClient(TestServer(build_app(gw)))
    await c.start_server()
    return gw, c


def _set_model(model: str, vision=None):
    cfg = cfgmod.load_config()
    cfg["model"]["default"] = model
    if vision is None:
        cfg["model"].pop("vision", None)
    else:
        cfg["model"]["vision"] = vision
    cfgmod.save_config(cfg)


async def _wait_idle(gw, sid, timeout=10):
    for _ in range(int(timeout * 20)):
        live = gw.live.get(sid)
        if live and live.task and live.task.done():
            return
        await asyncio.sleep(0.05)
    raise AssertionError("turn did not finish")


async def _upload(c, sid, name, data, ctype):
    fd = FormData()
    fd.add_field("session_id", sid)
    fd.add_field("file", data, filename=name, content_type=ctype)
    return await c.post("/api/uploads", data=fd, headers=H)


async def test_upload_download_and_auth(capture, monkeypatch, home):
    gw, c = await _client(monkeypatch)
    try:
        fd = FormData()
        fd.add_field("file", b"x", filename="a.txt")
        assert (await c.post("/api/uploads", data=fd)).status == 401
        r = await _upload(c, "s1", "../../etc/foto saya.png", PNG, "application/octet-stream")
        assert r.status == 200
        meta = await r.json()
        assert meta["kind"] == "image" and meta["mime"] == "image/png" and meta["size"] == len(PNG)
        assert meta["name"] == "foto saya.png" and meta["url"] == f"/api/uploads/{meta['id']}"
        assert str(home / "uploads" / "s1") in meta["path"]
        d = await c.get(meta["url"], headers=H)
        assert d.status == 200 and await d.read() == PNG and d.headers["Content-Type"] == "image/png"
        assert (await c.get(meta["url"])).status == 401
        dl = await c.get(meta["url"] + "?download=1", headers=H)
        assert dl.headers["Content-Disposition"].startswith("attachment")
        lst = await (await c.get("/api/uploads?session_id=s1", headers=H)).json()
        assert [a["id"] for a in lst["attachments"]] == [meta["id"]]
        assert (await c.delete(meta["url"], headers=H)).status == 200
        assert (await c.get(meta["url"], headers=H)).status == 404
    finally:
        await c.close()


async def test_upload_limit_25mb(capture, monkeypatch, home):
    gw, c = await _client(monkeypatch)
    try:
        big = b"0" * (25 * 1024 * 1024 + 1)
        r = await _upload(c, "s1", "big.bin", big, "application/octet-stream")
        assert r.status == 413
        assert not list((home / "uploads").rglob("*big.bin"))
        r = await c.post("/api/uploads?filename=raw.txt&session_id=s2", data=b"halo", headers={**H, "Content-Type": "text/plain"})
        assert r.status == 200 and (await r.json())["kind"] == "file"
        assert (await _upload(c, "s1", "empty.txt", b"", "text/plain")).status == 400
    finally:
        await c.close()


async def _session(c):
    ws = await c.ws_connect("/api/ws?token=tok")
    await ws.receive_json()  # gateway.ready
    n = 0

    async def call(method, params):
        nonlocal n
        n += 1
        await ws.send_json({"jsonrpc": "2.0", "id": n, "method": method, "params": params})
        while True:
            msg = await ws.receive_json(timeout=10)
            if msg.get("id") == n and "method" not in msg:
                return msg
    created = await call("session.create", {})
    return ws, call, created["result"]["session_id"]


async def test_image_goes_to_vision_model_as_data_url(capture, monkeypatch, home):
    gw, c = await _client(monkeypatch)
    try:
        ws, call, sid = await _session(c)
        meta = await (await _upload(c, sid, "layar.png", PNG, "image/png")).json()
        res = await call("prompt.submit", {"session_id": sid, "text": "apa ini?", "attachments": [meta["id"]]})
        assert res["result"]["ok"] and "notice" not in res["result"]
        await _wait_idle(gw, sid)
        user = capture[-1]["messages"][-1]
        assert user["role"] == "user" and isinstance(user["content"], list)
        assert user["content"][0]["type"] == "text" and user["content"][0]["text"].startswith("apa ini?")
        img = user["content"][1]
        assert img["type"] == "image_url"
        assert img["image_url"]["url"] == "data:image/png;base64," + base64.b64encode(PNG).decode()
        # transcript keeps a reference (not bytes) and the UI sees a downloadable attachment
        msgs = (await (await c.get(f"/api/sessions/{sid}/messages", headers=H)).json())["messages"]
        u = [m for m in msgs if m["role"] == "user"][0]
        assert u["attachments"][0]["id"] == meta["id"] and u["attachments"][0]["url"].startswith("/api/uploads/")
        assert "base64" not in json.dumps(gw.store.load(sid)["messages"])
        await ws.close()
    finally:
        await c.close()


async def test_image_without_vision_gets_notice_and_path(capture, monkeypatch, home):
    gw, c = await _client(monkeypatch)
    try:
        _set_model("deepseek-chat")
        ws, call, sid = await _session(c)
        meta = await (await _upload(c, sid, "layar.png", PNG, "image/png")).json()
        res = await call("prompt.submit", {"session_id": sid, "text": "", "attachments": [meta["id"]]})
        assert "tidak mendukung input gambar" in res["result"]["notice"]
        await _wait_idle(gw, sid)
        user = capture[-1]["messages"][-1]
        assert isinstance(user["content"], str)
        assert meta["path"] in user["content"] and "tidak mendukung input gambar" in user["content"]
        # explicit override wins over the name heuristic
        _set_model("deepseek-chat", vision=True)
        res = await call("prompt.submit", {"session_id": sid, "text": "lagi", "attachments": [meta["id"]]})
        await _wait_idle(gw, sid)
        assert isinstance(capture[-1]["messages"][-1]["content"], list)
        bad = await call("prompt.submit", {"session_id": sid, "text": "x", "attachments": ["000000000000"]})
        assert "error" in bad
        await ws.close()
    finally:
        await c.close()


async def test_text_and_code_files_are_extracted(capture, monkeypatch, home):
    gw, c = await _client(monkeypatch)
    try:
        ws, call, sid = await _session(c)
        code = await (await _upload(c, sid, "main.py", b"def halo():\n    return 42\n", "text/x-python")).json()
        blob = await (await _upload(c, sid, "data.bin", b"\x00\x01\x02binary", "application/octet-stream")).json()
        await call("prompt.submit", {"session_id": sid, "text": "review", "attachments": [code["id"], blob["id"]]})
        await _wait_idle(gw, sid)
        content = capture[-1]["messages"][-1]["content"]
        assert "def halo():" in content and code["path"] in content
        assert blob["path"] in content and "tidak bisa diekstrak" in content
        await ws.close()
    finally:
        await c.close()


async def test_upload_is_not_swallowed_by_the_quiet_fallback(capture, monkeypatch, home):
    """Regression (phone 1.4.5 on a core without the route): the compat fallback
    answered POST /api/uploads with 200 {"name": "uploads", ...} and no id, so the
    phone showed an "uploads · 0 B" card and the agent got no image."""
    gw, c = await _client(monkeypatch)
    try:
        ws, call, sid = await _session(c)
        r = await _upload(c, sid, "scaled_1000000034.jpg", PNG, "image/jpeg")
        assert r.status == 200
        meta = await r.json()
        assert meta["name"] == "scaled_1000000034.jpg" and meta["name"] != "uploads"
        assert meta["size"] == len(PNG) and len(meta["id"]) == 12 and meta["kind"] == "image"
        assert "available" not in meta
        res = await call("prompt.submit", {"session_id": sid, "text": "ini", "attachments": [meta["id"]]})
        assert res["result"]["attachments"][0]["id"] == meta["id"]
        await _wait_idle(gw, sid)
        parts = capture[-1]["messages"][-1]["content"]
        assert parts[0] == {"type": "text", "text": "ini"} and parts[1]["type"] == "image_url"
        # an empty / unknown id is refused instead of silently dropping the image
        bad = await call("prompt.submit", {"session_id": sid, "text": "ini", "attachments": [""]})
        assert "error" in bad
        await ws.close()
    finally:
        await c.close()
