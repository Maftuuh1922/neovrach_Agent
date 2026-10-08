import mock_llm
from neovarch import config as cfgmod
from neovarch.agent import Agent
from neovarch.llm import LLMError, stream_chat
from neovarch.store import SessionStore
from neovarch.tools import ToolContext, tool_schemas


async def test_stream_text_and_tool_call(mock_provider):
    ep = cfgmod.resolve_endpoint(cfgmod.load_config())
    pieces = []
    comp = await stream_chat(base_url=ep["base_url"], api_key="", model=ep["model"],
                             messages=[{"role": "user", "content": "apa kabar"}], on_text=pieces.append)
    assert comp.text == "Halo dari mock Neovarch. Kamu bilang: apa kabar"
    assert len(pieces) > 3 and comp.usage["completion_tokens"] == 12
    comp = await stream_chat(base_url=ep["base_url"], api_key="", model=ep["model"],
                             messages=[{"role": "user", "content": "pakai tool"}], tools=tool_schemas())
    assert comp.tool_calls[0].name == "shell"
    assert comp.tool_calls[0].parsed_args() == {"command": "echo neovarch-tool-ok"}


async def test_no_provider_is_a_clear_error(home):
    try:
        await stream_chat(base_url="", api_key="", model="", messages=[])
    except LLMError as exc:
        assert "neovarch setup" in str(exc)
    else:
        raise AssertionError


async def test_agent_turn_with_tool(mock_provider, tmp_path):
    events = []
    store = SessionStore()
    rec = store.create(cwd=str(tmp_path))

    async def never(*_a):
        raise AssertionError

    agent = Agent(rec, store, ToolContext(cwd=tmp_path, approve=never), lambda k, p: events.append((k, p)))
    final = await agent.run_turn("tolong jalankan tool")
    kinds = [k for k, _ in events]
    assert kinds[0] == "session.title" and "tool.start" in kinds and "tool.complete" in kinds
    assert kinds[-1] == "message.complete"
    assert final == "Selesai. Hasil alat: neovarch-tool-ok"
    saved = store.load(rec["id"])
    assert [m["role"] for m in saved["messages"]] == ["user", "assistant", "tool", "assistant"]
    sent = mock_provider.app[mock_llm.REQUESTS][0]["messages"][0]
    assert sent["role"] == "system" and "Neovarch Agent" in sent["content"]


async def test_agent_reports_provider_error(home, tmp_path):
    events = []
    store = SessionStore()
    agent = Agent(store.create(), store, ToolContext(cwd=tmp_path, approve=None), lambda k, p: events.append((k, p)))
    await agent.run_turn("halo")
    assert ("error" in [k for k, _ in events]) and events[-1][1].get("error")
