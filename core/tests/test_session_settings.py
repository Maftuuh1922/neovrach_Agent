"""Composer model / reasoning picks, app self-knowledge and the office_status tool."""

import json

import yaml
from aiohttp import web
from aiohttp.test_utils import TestServer

import mock_llm
from neovarch import config as cfgmod
from neovarch import session_settings as ss
from neovarch.agent import APP_KNOWLEDGE, system_prompt
from neovarch.llm import stream_chat
from neovarch.tools import TOOLS, ToolContext, list_skills, run_tool

from test_server import WS, _client


def test_parse_model_value():
    assert ss.parse_model_value("mimo-v2.6-flash-free --provider 9router --session") == (
        "mimo-v2.6-flash-free", "9router", True)
    assert ss.parse_model_value("gpt-4o --provider openai") == ("gpt-4o", "openai", False)


def test_effort_levels_and_wire_mapping():
    assert ss.normalize_effort("ULTRA") == "ultra"
    assert ss.normalize_effort("off") == "none"
    assert ss.normalize_effort("banana") is None
    assert ss.wire_effort("ultra") == "high" and ss.wire_effort("low") == "low"
    assert ss.wire_effort("none") is None and ss.wire_effort("") is None


def test_load_config_repairs_composer_damage(home):
    # What older cores wrote from the composer: model as a string, top-level reasoning.
    cfgmod.config_path().write_text(yaml.safe_dump({
        "model": "mimo --provider 9router", "reasoning": "ultra", "agent": {"max_turns": 12}}), encoding="utf-8")
    cfg = cfgmod.load_config()
    assert cfg["model"]["default"] == "mimo" and cfg["model"]["provider"] == "9router"
    assert "reasoning" not in cfg and cfg["agent"]["reasoning_effort"] == "ultra"
    assert cfg["agent"]["max_turns"] == 12


def test_system_prompt_has_app_knowledge(home, tmp_path):
    sp = system_prompt(cfgmod.load_config(), tmp_path, "kamu bisa lihat kantor?")
    assert APP_KNOWLEDGE in sp
    for word in ("Kantor", "Kanban", "Obsidian", "office_status", "at most 5 tool calls"):
        assert word in sp


def test_builtin_skill_installed_and_user_copy_kept(home):
    names = [s["name"] for s in list_skills()]
    assert "neovarch-app" in names
    skill = home / "skills" / "neovarch-app" / "SKILL.md"
    skill.write_text("# punyaku sendiri\n", encoding="utf-8")
    list_skills()
    assert skill.read_text(encoding="utf-8") == "# punyaku sendiri\n"


async def test_office_status_tool_reads_live_state(tmp_path):
    snap = {"counts": {"total": 1, "working": 1, "waiting-approval": 0, "idle": 0},
            "agents": [{"name": "Sora", "status": "working", "current_task": "rapikan README", "model": "mimo"}],
            "kanban": {"todo": 2}, "feed": [{"text": "Sora menjalankan shell"}],
            "model": {"model": "mimo", "provider": "9router"}}

    async def approve(*_):
        return "once"

    ctx = ToolContext(cwd=tmp_path, approve=approve, office=lambda: snap)
    out = await run_tool("office_status", {}, ctx)
    assert "Sora: working — rapikan README" in out and "Model aktif: mimo" in out and "todo 2" in out
    assert "office_status" in TOOLS
    no_gw = await run_tool("office_status", {}, ToolContext(cwd=tmp_path, approve=approve))
    assert "gateway" in no_gw


async def test_reasoning_effort_reaches_the_provider(mock_provider):
    app = mock_provider.app
    await stream_chat(base_url=str(mock_provider.make_url("/v1")), api_key="", model="mock-model",
                      messages=[{"role": "user", "content": "halo"}], reasoning_effort="high")
    assert app[mock_llm.REQUESTS][-1]["reasoning_effort"] == "high"


async def test_reasoning_effort_dropped_when_provider_rejects_it(home):
    seen = []

    async def completions(request):
        body = await request.json()
        seen.append(body)
        if "reasoning_effort" in body:
            return web.json_response({"error": {"message": "Unrecognized request argument: reasoning_effort"}},
                                     status=400)
        return web.json_response({"choices": [{"message": {"role": "assistant", "content": "ok"},
                                               "finish_reason": "stop"}]})

    app = web.Application()
    app.router.add_post("/v1/chat/completions", completions)
    server = TestServer(app)
    await server.start_server()
    try:
        comp = await stream_chat(base_url=str(server.make_url("/v1")), api_key="", model="m",
                                 messages=[{"role": "user", "content": "hi"}], reasoning_effort="low")
        assert comp.text == "ok" and comp.reasoning_skipped
        assert "reasoning_effort" in seen[0] and "reasoning_effort" not in seen[1]
    finally:
        await server.close()


async def test_composer_model_and_reasoning_picks(mock_provider, monkeypatch):
    gw, c = await _client(monkeypatch, NEOVARCH_SESSION_TOKEN="tok")
    try:
        cfg = cfgmod.load_config()
        cfg["custom_providers"] = [{"name": "Router", "base_url": cfg["model"]["base_url"], "models": ["mock-model", "other"]}]
        cfgmod.save_config(cfg)
        ws = WS(await c.ws_connect("/api/ws?token=tok"))
        await ws.pump()
        sid = (await ws.call("session.create", {"source": "desktop"}))["result"]["session_id"]
        # Session-only pick: the session switches, config.yaml keeps its default.
        res = (await ws.call("config.set", {"session_id": sid, "key": "model",
                                            "value": "other --provider custom:router --session"}))["result"]
        assert res["model"] == "other" and res["scope"] == "session"
        info = (await ws.call("session.status", {"session_id": sid}))["result"]
        assert info["model"] == "other" and info["provider"] == "custom:router"
        raw = yaml.safe_load(cfgmod.config_path().read_text(encoding="utf-8"))
        assert isinstance(raw["model"], dict) and raw["model"]["default"] == "mock-model"
        # Global pick rewrites only the model mapping and keeps every other key.
        raw.setdefault("agent", {})["max_turns"] = 17
        cfgmod.config_path().write_text(yaml.safe_dump(raw), encoding="utf-8")
        res = (await ws.call("config.set", {"session_id": sid, "key": "model",
                                            "value": "other --provider custom:router"}))["result"]
        raw = yaml.safe_load(cfgmod.config_path().read_text(encoding="utf-8"))
        assert raw["model"]["default"] == "other" and raw["agent"]["max_turns"] == 17
        # Reasoning: per session, validated, never a top-level key; reaches the request.
        assert (await ws.call("config.set", {"session_id": sid, "key": "reasoning", "value": "ultra"}))["result"]["value"] == "ultra"
        bad = await ws.call("config.set", {"session_id": sid, "key": "reasoning", "value": "turbo"})
        assert bad["error"]["code"] == -32602
        raw = yaml.safe_load(cfgmod.config_path().read_text(encoding="utf-8"))
        assert "reasoning" not in raw
        await ws.call("prompt.submit", {"session_id": sid, "text": "halo"})
        done = await ws.until("message.complete")
        assert not done["payload"].get("error"), done["payload"]
        body = mock_provider.app[mock_llm.REQUESTS][-1]
        assert body["reasoning_effort"] == "high" and body["model"] == "other"
    finally:
        await c.close()
