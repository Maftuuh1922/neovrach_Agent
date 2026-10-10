"""Routes that used to answer from compat stubs: timeline/around, logs,
skills toggle/edit/archive, memory status/reset, the Kantor per-agent model."""

import logging

from neovarch import config as cfgmod
from neovarch import logs as logmod
from neovarch.paths import neovarch_home
from neovarch.tools import list_skills

from test_server import _client

H = {"Authorization": "Bearer tok"}


async def test_timeline_and_around(home, monkeypatch):
    gw, c = await _client(monkeypatch, NEOVARCH_SESSION_TOKEN="tok")
    try:
        rec = gw.store.create(source="desktop", cwd=str(home), model="m")
        for i in range(10):
            rec["messages"].append({"role": "user", "content": f"pertanyaan {i}\nbaris dua", "ts": i})
            rec["messages"].append({"role": "assistant", "content": f"jawaban {i}", "ts": i})
        gw.store.save(rec)
        sid = rec["id"]
        tl = await (await c.get(f"/api/sessions/{sid}/timeline?limit=4", headers=H)).json()
        assert [e["row_id"] for e in tl["entries"]] == [1, 3, 5, 7]
        assert tl["entries"][0]["preview"] == "pertanyaan 0 baris dua"
        assert tl["pagination"] == {"next_cursor": 7, "has_more": True}
        tl2 = await (await c.get(f"/api/sessions/{sid}/timeline?after_row_id=7", headers=H)).json()
        assert [e["row_id"] for e in tl2["entries"]] == [9, 11, 13, 15, 17, 19] and not tl2["pagination"]["has_more"]
        page = await (await c.get(f"/api/sessions/{sid}/messages/around?row_id=11&limit=6", headers=H)).json()
        rows = [m["row_id"] for m in page["messages"]]
        assert 11 in rows and len(rows) == 6
        assert page["pagination"]["has_older"] and page["pagination"]["has_newer"]
        assert page["pagination"]["offset"] == rows[0] - 1
        msgs = await (await c.get(f"/api/sessions/{sid}/messages", headers=H)).json()
        assert msgs["messages"][0]["row_id"] == 1
        assert (await c.get("/api/sessions/nope/timeline", headers=H)).status == 404
    finally:
        await c.close()


async def test_logs_are_real(home, monkeypatch):
    log = logmod.setup()
    try:
        log.info("gateway listening test")
        log.warning("model gagal: 404")
        gw, c = await _client(monkeypatch, NEOVARCH_SESSION_TOKEN="tok")
        try:
            agent = await (await c.get("/api/logs?lines=50", headers=H)).json()
            assert any("gateway listening test" in ln for ln in agent["lines"])
            warn = await (await c.get("/api/logs?level=WARNING", headers=H)).json()
            assert warn["lines"] and all("WARNING" in ln for ln in warn["lines"])
            err = await (await c.get("/api/logs?file=errors&search=gagal", headers=H)).json()
            assert len(err["lines"]) == 1 and err["name"] == "errors"
        finally:
            await c.close()
    finally:
        for h in list(log.handlers):
            log.removeHandler(h)
            h.close()
        log._neovarch_files = False


async def test_skills_toggle_edit_archive_and_memory(home, monkeypatch):
    gw, c = await _client(monkeypatch, NEOVARCH_SESSION_TOKEN="tok")
    try:
        d = neovarch_home() / "skills" / "tulis-laporan"
        d.mkdir(parents=True)
        (d / "SKILL.md").write_text("---\nname: tulis-laporan\ndescription: Laporan\n---\nisi", encoding="utf-8")
        res = await (await c.put("/api/skills/toggle", json={"name": "tulis-laporan", "enabled": False}, headers=H)).json()
        assert res == {"ok": True, "name": "tulis-laporan", "enabled": False}
        assert "tulis-laporan" not in [s["name"] for s in list_skills()]
        listed = await (await c.get("/api/skills", headers=H)).json()
        assert next(s for s in listed if s["name"] == "tulis-laporan")["enabled"] is False
        await c.put("/api/skills/toggle", json={"name": "tulis-laporan", "enabled": True}, headers=H)
        assert "tulis-laporan" in [s["name"] for s in list_skills()]
        node = await (await c.get("/api/learning/node?id=tulis-laporan", headers=H)).json()
        assert node["ok"] and node["content"].endswith("isi")
        await c.put("/api/learning/node", json={"id": "tulis-laporan", "content": "baru"}, headers=H)
        assert (d / "SKILL.md").read_text(encoding="utf-8") == "baru"
        gone = await (await c.delete("/api/learning/node", json={"id": "tulis-laporan"}, headers=H)).json()
        assert gone["ok"] and not d.exists()
        assert any((neovarch_home() / "skills" / ".archive").glob("tulis-laporan-*"))
        mem = neovarch_home() / "memory"
        mem.mkdir(exist_ok=True)
        (mem / "proyek.md").write_text("x", encoding="utf-8")
        (mem / "USER.md").write_text("y", encoding="utf-8")
        st = await (await c.get("/api/memory", headers=H)).json()
        assert st["builtin_files"] == {"memory": 1, "user": 1}
        out = await (await c.post("/api/memory/reset", json={"target": "memory"}, headers=H)).json()
        assert out["deleted"] == ["proyek.md"] and (mem / "USER.md").exists()
    finally:
        await c.close()


async def test_office_agent_model_route(mock_provider, monkeypatch):
    gw, c = await _client(monkeypatch, NEOVARCH_SESSION_TOKEN="tok")
    try:
        rec = gw.store.create(source="desktop", cwd=".", model="mock-model")
        gw.store.save(rec)
        res = await (await c.put(f"/api/agents/session:{rec['id']}/model", json={"model": "other"}, headers=H)).json()
        assert res["ok"] and res["scope"] == "session" and res["model"] == "other"
        assert cfgmod.load_config()["model"]["default"] == "mock-model"
        # the Kantor desk pick is that agent's own model (config agents.models), not the default
        from neovarch import models as modelsmod
        assert modelsmod.agent_model(cfgmod.load_config(), f"session:{rec['id']}")["model"] == "other"
        res = await (await c.put("/api/agents/pc/model", json={"model": "mock-2"}, headers=H)).json()
        assert res["scope"] == "global" and cfgmod.load_config()["model"]["default"] == "mock-2"
        assert (await c.put("/api/agents/session:nope/model", json={"model": "x"}, headers=H)).status == 404
    finally:
        await c.close()
