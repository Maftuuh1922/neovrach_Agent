"""Remote composer: catalog, completions and prompt.submit picks (phone parity
with the desktop composer). Additive: old clients see no change."""
from pathlib import Path

import mock_llm
from aiohttp.test_utils import TestClient, TestServer

from neovarch import composer
from neovarch.server import Gateway, build_app
from test_server import WS


def _skill(home: Path, name: str, desc: str) -> None:
    d = home / "skills" / name
    d.mkdir(parents=True, exist_ok=True)
    (d / "SKILL.md").write_text(f"---\nname: {name}\ndescription: {desc}\n---\n# {name}\n", encoding="utf-8")


async def _client(monkeypatch, tmp_path):
    monkeypatch.setenv("NEOVARCH_SESSION_TOKEN", "tok")
    monkeypatch.setenv("NEOVARCH_CWD", str(tmp_path / "proj"))
    gw = Gateway(isolated=False)
    c = TestClient(TestServer(build_app(gw)))
    await c.start_server()
    return gw, c


async def test_catalog_requires_auth_and_lists_desktop_controls(mock_provider, home, monkeypatch, tmp_path):
    _skill(home, "code-review", "Tinjau perubahan")
    _skill(home, "deploy", "Rilis ke server")
    gw, c = await _client(monkeypatch, tmp_path)
    try:
        assert (await c.get("/api/composer/catalog")).status == 401
        r = await c.get("/api/composer/catalog", headers={"Authorization": "Bearer tok"})
        assert r.status == 200
        cat = await r.json()
        assert cat["version"] == composer.CATALOG_VERSION
        assert [s["name"] for s in cat["skills"]] == ["code-review", "deploy"]
        assert cat["skills"][0]["description"] == "Tinjau perubahan"
        assert {c["name"] for c in cat["commands"]} == {"new", "model"}
        assert [s["id"] for s in cat["snippets"]] == ["codeReview", "implementationPlan", "explainThis"]
        assert cat["models"]["model"] == "mock-model"
        assert cat["reasoning"]["levels"] == ["none", "minimal", "low", "medium", "high", "xhigh"]
        assert cat["reasoning"]["default"] == "default"
        assert set(cat["features"]["prompt_fields"]) == {"skills", "reasoning_effort"}
        assert any(m["text"] == "@url:" for m in cat["mentions"])
        # same over the WebSocket
        ws = WS(await c.ws_connect("/api/ws?token=tok"))
        await ws.pump()
        assert (await ws.call("composer.catalog"))["result"]["version"] == composer.CATALOG_VERSION
    finally:
        await c.close()


async def test_complete_path_and_slash(mock_provider, home, monkeypatch, tmp_path):
    _skill(home, "code-review", "Tinjau perubahan")
    proj = tmp_path / "proj"
    (proj / "src").mkdir(parents=True)
    (proj / "src" / "main.py").write_text("print(1)\n")
    (proj / "README.md").write_text("# x\n")
    (proj / ".secret").write_text("x")
    (tmp_path / "outside.txt").write_text("no")
    gw, c = await _client(monkeypatch, tmp_path)
    h = {"Authorization": "Bearer tok"}
    try:
        assert (await c.get("/api/composer/complete?kind=path&q=")).status == 401
        items = (await (await c.get("/api/composer/complete?kind=path&q=", headers=h)).json())["items"]
        assert [i["text"] for i in items] == ["@folder:src/", "@file:README.md"]  # folders first, no dotfiles
        items = (await (await c.get("/api/composer/complete", params={"kind": "path", "q": "@file:src/ma"},
                                    headers=h)).json())["items"]
        assert items == [{"text": "@file:src/main.py", "display": "main.py", "meta": "src", "is_dir": False}]
        # never escapes the session folder
        out = (await (await c.get("/api/composer/complete", params={"kind": "path", "q": "../"}, headers=h)).json())
        assert out["items"] == []
        sl = (await (await c.get("/api/composer/complete?kind=slash&q=rev", headers=h)).json())["items"]
        assert sl == [{"text": "/code-review", "name": "code-review", "description": "Tinjau perubahan", "kind": "skill"}]
        assert (await c.get("/api/composer/complete?kind=nope", headers=h)).status == 400
    finally:
        await c.close()


async def test_submit_with_skills_and_reasoning_effort(mock_provider, home, monkeypatch, tmp_path):
    _skill(home, "code-review", "Tinjau perubahan")
    gw, c = await _client(monkeypatch, tmp_path)
    reqs = mock_provider.app[mock_llm.REQUESTS]
    try:
        ws = WS(await c.ws_connect("/api/ws?token=tok"))
        await ws.pump()
        sid = (await ws.call("session.create", {"source": "mobile"}))["result"]["session_id"]
        res = await ws.call("prompt.submit", {"session_id": sid, "text": "cek login", "surface": "mobile",
                                              "skills": ["code-review", "not-installed", "code-review"],
                                              "reasoning_effort": "high"})
        assert res["result"]["ok"]
        done = await ws.until("message.complete")
        assert done["payload"]["text"].endswith("Kamu bilang: /code-review cek login")
        assert reqs[-1]["reasoning_effort"] == "high"
        assert reqs[-1]["messages"][-1]["content"] == "/code-review cek login"
        # a later plain submit (old client) is untouched: no effort, no prefix
        ws.events.clear()
        await ws.call("prompt.submit", {"session_id": sid, "text": "halo"})
        await ws.until("message.complete")
        assert "reasoning_effort" not in reqs[-1]
        assert reqs[-1]["messages"][-1]["content"] == "halo"
        # unknown effort values are ignored
        ws.events.clear()
        await ws.call("prompt.submit", {"session_id": sid, "text": "lagi", "reasoning_effort": "turbo"})
        await ws.until("message.complete")
        assert "reasoning_effort" not in reqs[-1]
    finally:
        await c.close()


async def test_profile_reasoning_effort_from_desktop_pill(mock_provider, home, monkeypatch, tmp_path):
    from neovarch import config as cfgmod
    cfg = cfgmod.load_config()
    cfgmod.set_path(cfg, "agent.reasoning_effort", "low")
    cfgmod.save_config(cfg)
    gw, c = await _client(monkeypatch, tmp_path)
    reqs = mock_provider.app[mock_llm.REQUESTS]
    try:
        ws = WS(await c.ws_connect("/api/ws?token=tok"))
        await ws.pump()
        sid = (await ws.call("session.create", {}))["result"]["session_id"]
        await ws.call("prompt.submit", {"session_id": sid, "text": "halo"})
        await ws.until("message.complete")
        assert reqs[-1]["reasoning_effort"] == "low"
        ws.events.clear()
        await ws.call("prompt.submit", {"session_id": sid, "text": "lagi", "reasoning_effort": "xhigh"})
        await ws.until("message.complete")
        assert reqs[-1]["reasoning_effort"] == "xhigh"
        cat = (await (await c.get("/api/composer/catalog?token=tok")).json())
        assert cat["reasoning"]["default"] == "low"
    finally:
        await c.close()


def test_apply_skills_unit():
    assert composer.apply_skills("x", ["a", "b"], known=["a", "b"]) == "/a /b x"
    assert composer.apply_skills("/a x", ["a"], known=["a"]) == "/a x"
    assert composer.apply_skills("x", ["zz"], known=["a"]) == "x"
    assert composer.apply_skills("x", None, known=["a"]) == "x"
    assert composer.normalize_effort("HIGH") == "high" and composer.normalize_effort("max") is None
