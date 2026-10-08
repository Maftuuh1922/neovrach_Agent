"""Add model: presets, custom OpenAI-compatible endpoints over http and https, selection, chat."""
import re
import ssl
import subprocess
from pathlib import Path

import pytest
from aiohttp import web
from aiohttp.test_utils import TestClient, TestServer

import mock_llm
from neovarch import config as cfgmod
from neovarch.server import Gateway, build_app

from test_server import WS


async def _client(monkeypatch):
    monkeypatch.setenv("HERMES_DASHBOARD_SESSION_TOKEN", "tok")
    gw = Gateway(isolated=False)
    c = TestClient(TestServer(build_app(gw)))
    await c.start_server()
    return gw, c


@pytest.fixture(scope="module")
def certs(tmp_path_factory):
    d = tmp_path_factory.mktemp("tls")
    def run(*a):
        subprocess.run(["openssl", *a], check=True, capture_output=True, cwd=d)
    run("req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", "ca.key", "-out", "ca.pem", "-days", "2",
        "-subj", "/CN=Neovarch Test CA")
    run("req", "-newkey", "rsa:2048", "-nodes", "-keyout", "srv.key", "-out", "srv.csr", "-subj", "/CN=127.0.0.1")
    (d / "ext.cnf").write_text("subjectAltName=IP:127.0.0.1,DNS:localhost\n")
    run("x509", "-req", "-in", "srv.csr", "-CA", "ca.pem", "-CAkey", "ca.key", "-CAcreateserial", "-out", "srv.pem",
        "-days", "2", "-extfile", "ext.cnf")
    return d


async def _serve(app, certs=None):
    runner = web.AppRunner(app)
    await runner.setup()
    ctx = None
    if certs:
        ctx = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
        ctx.load_cert_chain(str(certs / "srv.pem"), str(certs / "srv.key"))
    site = web.TCPSite(runner, "127.0.0.1", 0, ssl_context=ctx)
    await site.start()
    port = site._server.sockets[0].getsockname()[1]
    return runner, f"{'https' if certs else 'http'}://127.0.0.1:{port}"


async def _chat(c, text="halo"):
    ws = WS(await c.ws_connect("/api/ws?token=tok"))
    await ws.pump()
    sid = (await ws.call("session.create", {}))["result"]["session_id"]
    await ws.call("prompt.submit", {"session_id": sid, "text": text})
    return (await ws.until("message.complete", timeout=20))["payload"]


async def test_http_local_endpoint_add_validate_select_and_chat(home, monkeypatch):
    runner, base = await _serve(mock_llm.build_app(delay=0, api_key=None))
    gw, c = await _client(monkeypatch)
    try:
        # bare root without /v1: the probe finds {root}/v1/models and reports it
        v = await (await c.post("/api/providers/custom-endpoints/validate?token=tok",
                                json={"name": "LiteLLM lokal", "base_url": base})).json()
        assert v["ok"] and v["models"] == ["mock-model"] and v["resolved_base_url"] == base + "/v1"
        saved = await (await c.post("/api/providers/custom-endpoints?token=tok", json={
            "name": "LiteLLM lokal", "base_url": v["resolved_base_url"], "model": "mock-model",
            "models": v["models"], "make_default": True})).json()
        assert saved["id"] == "litellm-lokal"
        ep = saved["endpoints"][0]
        assert ep["is_current"] and ep["has_api_key"] is False and ep["base_url"] == base + "/v1"
        cfg = cfgmod.load_config()
        assert cfg["model"]["provider"] == "custom:litellm-lokal" and cfg["model"]["default"] == "mock-model"
        opts = await (await c.get("/api/model/options?token=tok")).json()
        row = next(p for p in opts["providers"] if p["slug"] == "custom:litellm-lokal")
        assert row["is_current"] and row["models"] == ["mock-model"] and opts["model"] == "mock-model"
        done = await _chat(c, "halo lokal")
        assert done["text"].endswith("Kamu bilang: halo lokal")
        assert not (Path.home() / ".hermes" / "config.yaml").exists() or "litellm" not in (Path.home() / ".hermes" / "config.yaml").read_text()
    finally:
        await c.close()
        await runner.cleanup()


async def test_https_gateway_with_key_and_custom_header(home, monkeypatch, certs):
    app = mock_llm.build_app(delay=0, api_key="sk-router-123", headers={"X-Router-Tenant": "neo"})
    runner, base = await _serve(app, certs)
    gw, c = await _client(monkeypatch)
    try:
        body = {"name": "9router", "base_url": base + "/v1"}
        # untrusted self-signed CA, no tick -> clear TLS error
        r = await (await c.post("/api/providers/custom-endpoints/validate?token=tok", json=body)).json()
        assert not r["ok"] and not r["reachable"] and "self-signed" in r["message"]
        # ticked: reachable but key + header are required
        r = await (await c.post("/api/providers/custom-endpoints/validate?token=tok",
                                json={**body, "allow_insecure_tls": True})).json()
        assert r["reachable"] and not r["ok"] and "HTTP 401" in r["message"]
        full = {**body, "allow_insecure_tls": True, "api_key": "sk-router-123", "headers": "X-Router-Tenant: neo"}
        r = await (await c.post("/api/providers/custom-endpoints/validate?token=tok", json=full)).json()
        assert r["ok"] and r["models"] == ["mock-model"]
        saved = await (await c.post("/api/providers/custom-endpoints?token=tok",
                                    json={**full, "model": "mock-model", "make_default": True})).json()
        ep = saved["endpoints"][0]
        assert ep["has_api_key"] and ep["header_names"] == ["X-Router-Tenant"] and ep["allow_insecure_tls"]
        env = cfgmod.read_env_file()
        assert env["NEOVARCH_EP_9ROUTER_API_KEY"] == "sk-router-123"
        assert "sk-router-123" not in cfgmod.config_path().read_text()
        done = await _chat(c, "halo router")
        assert done["text"].endswith("Kamu bilang: halo router"), done
    finally:
        await c.close()
        await runner.cleanup()


async def test_https_trusted_ca_without_insecure(home, monkeypatch, certs):
    monkeypatch.setenv("SSL_CERT_FILE", str(certs / "ca.pem"))
    runner, base = await _serve(mock_llm.build_app(delay=0), certs)
    gw, c = await _client(monkeypatch)
    try:
        r = await (await c.post("/api/providers/custom-endpoints/validate?token=tok",
                                json={"name": "gw", "base_url": base + "/v1"})).json()
        assert r["ok"], r
        await c.post("/api/providers/custom-endpoints?token=tok",
                     json={"name": "gw", "base_url": base + "/v1", "model": "mock-model", "make_default": True})
        assert (await _chat(c, "tls"))["text"].endswith("Kamu bilang: tls")
    finally:
        await c.close()
        await runner.cleanup()


async def test_no_models_route_allows_manual_model(home, monkeypatch):
    runner, base = await _serve(mock_llm.build_app(delay=0, models_route=False))
    gw, c = await _client(monkeypatch)
    try:
        r = await (await c.post("/api/providers/custom-endpoints/validate?token=tok",
                                json={"name": "ollama", "base_url": base + "/v1"})).json()
        assert r["reachable"] and not r["ok"] and "manual" in r["message"]
        await c.post("/api/providers/custom-endpoints?token=tok",
                     json={"name": "ollama", "base_url": base + "/v1", "model": "llama3-ketik-manual", "make_default": True})
        assert cfgmod.load_config()["model"]["default"] == "llama3-ketik-manual"
        assert (await _chat(c, "manual"))["text"].endswith("Kamu bilang: manual")
    finally:
        await c.close()
        await runner.cleanup()


async def test_unreachable_and_bad_input_messages(home, monkeypatch):
    gw, c = await _client(monkeypatch)
    try:
        r = await (await c.post("/api/providers/custom-endpoints/validate?token=tok",
                                json={"name": "x", "base_url": "http://127.0.0.1:9/v1"})).json()
        assert not r["ok"] and not r["reachable"] and "Tidak bisa terhubung" in r["message"]
        r = await c.post("/api/providers/custom-endpoints?token=tok", json={"name": "x", "base_url": "ftp://a/b"})
        assert r.status == 422 and "ftp" in (await r.json())["detail"]
        r = await c.post("/api/providers/custom-endpoints?token=tok",
                         json={"name": "x", "base_url": "http://a:1/v1", "headers": "tanpa titik dua"})
        assert r.status == 422
        # LAN IP + odd port and scheme-less localhost are accepted
        for url, want in (("http://192.168.1.50:20128/v1", "http://192.168.1.50:20128/v1"),
                          ("localhost:1234/v1", "http://localhost:1234/v1")):
            saved = await (await c.post("/api/providers/custom-endpoints?token=tok",
                                        json={"name": url, "base_url": url, "model": "m"})).json()
            assert any(e["base_url"] == want for e in saved["endpoints"])
    finally:
        await c.close()


async def test_preset_key_select_and_delete_endpoint(home, monkeypatch):
    gw, c = await _client(monkeypatch)
    try:
        assert (await c.put("/api/env?token=tok", json={"key": "GROQ_API_KEY", "value": "gsk_abcdefgh1234"})).status == 200
        env = await (await c.get("/api/env?token=tok")).json()
        assert env["GROQ_API_KEY"]["is_set"] and env["GROQ_API_KEY"]["redacted_value"].endswith("1234")
        opts = await (await c.get("/api/model/options?token=tok")).json()
        assert any(p["slug"] == "groq" and p["authenticated"] for p in opts["providers"])
        res = await (await c.post("/api/model/set?token=tok", json={"scope": "main", "provider": "groq",
                                                                     "model": "llama-3.1-8b-instant"})).json()
        assert res["ok"] and res["base_url"] == "https://api.groq.com/openai/v1"
        rec = await (await c.get("/api/model/recommended-default?provider=openai&token=tok")).json()
        assert rec["model"] == "gpt-4o-mini"
        await c.post("/api/providers/custom-endpoints?token=tok", json={"name": "Hapus", "base_url": "http://127.0.0.1:1/v1",
                                                                        "model": "m", "api_key": "k"})
        r = await (await c.delete("/api/providers/custom-endpoints/hapus?token=tok")).json()
        assert r["endpoints"] == [] and not cfgmod.secret("NEOVARCH_EP_HAPUS_API_KEY")
        oauth = await (await c.post("/api/providers/oauth/nous/start?token=tok", json={})).json()
        assert oauth["ok"] is False and "tidak didukung" in oauth["message"]
        assert (await (await c.get("/api/providers/oauth?token=tok")).json()) == {"providers": []}
    finally:
        await c.close()


async def test_model_switch_rpc(home, monkeypatch):
    gw, c = await _client(monkeypatch)
    try:
        ws = WS(await c.ws_connect("/api/ws?token=tok"))
        await ws.pump()
        await c.post("/api/providers/custom-endpoints?token=tok", json={"name": "A", "base_url": "http://127.0.0.1:1/v1",
                                                                        "model": "a1", "models": ["a1", "a2"]})
        res = (await ws.call("model.set", {"provider": "custom:a", "model": "a2"}))["result"]
        assert res["ok"] and cfgmod.load_config()["model"]["default"] == "a2"
        opts = (await ws.call("model.options", {}))["result"]
        assert opts["provider"] == "custom:a" and opts["model"] == "a2"
    finally:
        await c.close()


# Every REST path the desktop renderer calls answers with 2xx (never 404/500).
RENDERER_GETS = [
    "/api/status", "/api/config", "/api/config/defaults", "/api/config/schema", "/api/env", "/api/model/info",
    "/api/model/options", "/api/model/auxiliary", "/api/model/moa", "/api/model/recommended-default?provider=openai",
    "/api/providers/custom-endpoints", "/api/providers/oauth", "/api/cron/jobs", "/api/cron/delivery-targets",
    "/api/local-models/status", "/api/local-models/hardware", "/api/local-models/jobs", "/api/mcp/servers",
    "/api/mcp/catalog", "/api/messaging/platforms", "/api/pairing", "/api/webhooks", "/api/analytics/usage?days=30",
    "/api/profiles", "/api/profiles/active", "/api/profiles/sessions", "/api/profiles/sessions/sidebar",
    "/api/profiles/projects/tree", "/api/sessions", "/api/sessions/search?q=x", "/api/skills",
    "/api/skills/content?name=x", "/api/skills/hub/sources", "/api/skills/hub/search?q=x", "/api/learning/graph",
    "/api/memory", "/api/curator", "/api/hermes/update/check", "/api/actions/doctor/status?lines=10",
    "/api/audio/elevenlabs/voices", "/api/audio/voice-config", "/api/audio/voice-live/status", "/api/tools/toolsets",
    "/api/tools/toolsets/web/config", "/api/tools/toolsets/web/models", "/api/tools/terminal/backends",
    "/api/tools/computer-use/status", "/api/git/gh-auth", "/api/logs", "/api/system", "/api/fs/default",
    "/api/memory/providers/x/config", "/api/plugins/kanban/board", "/api/models", "/api/whatever/new",
]


async def test_every_renderer_get_is_2xx(home, monkeypatch):
    gw, c = await _client(monkeypatch)
    try:
        for path in RENDERER_GETS:
            r = await c.get(path + ("&" if "?" in path else "?") + "token=tok")
            assert r.status < 400, path
            await r.json()
        assert isinstance(await (await c.get("/api/skills?token=tok")).json(), list)
        assert isinstance(await (await c.get("/api/tools/toolsets?token=tok")).json(), list)
        assert isinstance(await (await c.get("/api/cron/jobs?token=tok")).json(), list)
        for method, path in (("POST", "/api/ops/doctor"), ("PUT", "/api/messaging/platforms/x"),
                             ("DELETE", "/api/providers/oauth/x"), ("POST", "/api/skills/hub/install")):
            r = await c.request(method, path + "?token=tok", json={})
            assert r.status < 400, (method, path)
    finally:
        await c.close()


async def test_kanban_desktop_contract(home, monkeypatch):
    gw, c = await _client(monkeypatch)
    try:
        boards = await (await c.get("/api/plugins/kanban/boards?token=tok")).json()
        assert boards["current"] == "default" and boards["boards"][0]["slug"] == "default"
        made = await (await c.post("/api/plugins/kanban/tasks?token=tok", json={"title": "Tulis laporan"})).json()
        tid = made["task"]["id"]
        assert made["id"] == tid  # phone reads the flat shape, desktop reads {task}
        ws = await c.ws_connect(f"/api/plugins/kanban/events?since=0&token=tok")
        first = await ws.receive_json(timeout=5)
        assert first["cursor"] >= 1
        await c.patch(f"/api/plugins/kanban/tasks/{tid}?token=tok", json={"status": "running"})
        frame = await ws.receive_json(timeout=5)
        assert frame["events"][-1]["task_id"] == tid and frame["events"][-1]["payload"]["to"] == "running"
        await ws.close()
        detail = await (await c.get(f"/api/plugins/kanban/tasks/{tid}?token=tok")).json()
        assert detail["task"]["title"] == "Tulis laporan" and detail["runs"] == []
        board = await (await c.get("/api/plugins/kanban/board?token=tok")).json()
        assert board["latest_event_id"] >= 2 and board["tenants"] == [] and board["columns"][3]["name"] == "running"
        for p in ("profiles", "projects", "orchestration", f"tasks/{tid}/log"):
            assert (await c.get(f"/api/plugins/kanban/{p}?token=tok")).status == 200
        assert (await (await c.delete(f"/api/plugins/kanban/tasks/{tid}?token=tok")).json())["ok"]
    finally:
        await c.close()
