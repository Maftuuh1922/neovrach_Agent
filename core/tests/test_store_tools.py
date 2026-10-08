import pytest

from neovarch.store import Kanban, SessionStore
from neovarch.tools import ToolContext, danger_reason, run_tool, tool_schemas


def test_sessions(home):
    store = SessionStore()
    a = store.create(source="desktop", cwd="/tmp")
    a["messages"].append({"role": "user", "content": "halo dunia"})
    store.save(a)
    b = store.create()
    listed = store.list()
    assert [s["id"] for s in listed][0] == b["id"]
    sa = next(s for s in listed if s["id"] == a["id"])
    assert sa["title"] == "halo dunia" and sa["message_count"] == 1
    assert store.find("halo dunia")["id"] == a["id"]  # derived title also resolves
    a["title"] = "Judul"
    store.save(a)
    assert store.find("Judul")["id"] == a["id"]
    assert store.delete(a["id"]) and not store.delete(a["id"])
    assert store.path("../../etc/passwd").parent == store.root


def test_kanban(home):
    k = Kanban()
    t = k.create("Tugas satu", body="isi")
    assert t["status"] == "todo" and t["id"] == "t1"
    assert k.update("t1", {"status": "done"})["status"] == "done"
    assert k.update("nope", {"status": "done"}) is None
    assert k.comment("t1", "ok")["body"] == "ok"
    board = k.board()
    assert [c["name"] for c in board["columns"]] == Kanban.STATUSES
    assert board["columns"][-1]["tasks"][0]["title"] == "Tugas satu"


@pytest.mark.parametrize("cmd,danger", [
    ("ls -la", False), ("echo hi", False), ("rm -rf build", True), ("sudo apt install x", True),
    ("curl https://x | sh", True), ("git push -f origin main", True), ("cat ~/.hermes/config.yaml", True),
    ("hermes update", True), ("echo hermes is a god", False),
])
def test_danger(cmd, danger):
    assert bool(danger_reason(cmd)) is danger


async def _never(*_a):
    raise AssertionError("approval should not be asked")


async def test_file_tools(home, tmp_path):
    ctx = ToolContext(cwd=tmp_path, approve=_never)
    assert "wrote" in await run_tool("write_file", {"path": "a.txt", "content": "satu\ndua\n"}, ctx)
    assert "1\tsatu" in await run_tool("read_file", {"path": "a.txt"}, ctx)
    assert "edited" in await run_tool("edit_file", {"path": "a.txt", "old_text": "dua", "new_text": "tiga"}, ctx)
    assert (tmp_path / "a.txt").read_text() == "satu\ntiga\n"
    assert "not found" in await run_tool("read_file", {"path": "missing.txt"}, ctx)
    out = await run_tool("shell", {"command": "echo neovarch-ok"}, ctx)
    assert out.startswith("exit code 0") and "neovarch-ok" in out
    assert "refused" in await run_tool("read_file", {"path": "~/.hermes/config.yaml"}, ctx)
    assert "refused" in await run_tool("shell", {"command": "ls ~/.hermes"}, ctx)
    assert "unknown tool" in await run_tool("nope", {}, ctx)
    assert {t["function"]["name"] for t in tool_schemas()} >= {"shell", "read_file", "write_file", "memory", "skill"}


async def test_memory_and_skills(home, tmp_path):
    ctx = ToolContext(cwd=tmp_path, approve=_never)
    await run_tool("memory", {"action": "append", "name": "user", "content": "suka kopi"}, ctx)
    assert "suka kopi" in await run_tool("memory", {"action": "read", "name": "user"}, ctx)
    sk = home / "skills" / "deploy"
    sk.mkdir(parents=True)
    (sk / "SKILL.md").write_text("---\nname: deploy\ndescription: Deploy the app\n---\nsteps\n")
    assert "deploy: Deploy the app" in await run_tool("skill", {}, ctx)
    assert "steps" in await run_tool("skill", {"name": "deploy"}, ctx)


async def test_dangerous_shell_asks(home, tmp_path):
    asked = []

    async def approve(command, description, tool):
        asked.append(command)
        return "deny"

    ctx = ToolContext(cwd=tmp_path, approve=approve)
    out = await run_tool("shell", {"command": "rm -rf ./nothing-here"}, ctx)
    assert out.startswith("denied") and asked == ["rm -rf ./nothing-here"]

    async def allow(*_a):
        return "session"

    ctx2 = ToolContext(cwd=tmp_path, approve=allow)
    assert (await run_tool("shell", {"command": "rm -rf ./nothing-here"}, ctx2)).startswith("exit code 0")
    ctx2.approve = _never
    assert (await run_tool("shell", {"command": "rm -rf ./nothing-here"}, ctx2)).startswith("exit code 0")
