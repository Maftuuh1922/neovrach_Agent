"""Scheduled jobs: schedule parsing, next-run maths, the /api/cron routes and a real run."""
import asyncio
import datetime as dt
import time

import pytest
from aiohttp.test_utils import TestClient, TestServer

from neovarch import cron
from neovarch.server import Gateway, build_app


def _ts(y, mo, d, h, mi):
    return dt.datetime(y, mo, d, h, mi).timestamp()


def test_parse_schedule_forms():
    assert cron.parse_schedule("30m")["seconds"] == 1800
    assert cron.parse_schedule("every 2h") == {"kind": "interval", "seconds": 7200, "expr": "every 2h",
                                               "display": "setiap 2h"}
    assert cron.parse_schedule("tiap 1d")["seconds"] == 86400
    assert cron.parse_schedule("daily 08:05")["expr"] == "5 8 * * *"
    assert cron.parse_schedule("harian 7:30")["display"] == "setiap hari 07:30"
    assert cron.parse_schedule("0 9 * * 1-5")["kind"] == "cron"
    once = cron.parse_schedule("2030-01-02T03:04")
    assert once["kind"] == "once" and once["at"] == _ts(2030, 1, 2, 3, 4)
    for bad in ("", "10s", "61 * * * *", "* * * *", "kapan-kapan", "0 25 * * *", "daily 24:00"):
        with pytest.raises(cron.ScheduleError):
            cron.parse_schedule(bad)


def test_cron_next():
    # Thursday 2026-10-08 22:49 -> weekdays at 09:00 -> Friday 09:00
    assert cron.cron_next("0 9 * * 1-5", _ts(2026, 10, 8, 22, 49)) == _ts(2026, 10, 9, 9, 0)
    # Friday 09:00 exactly -> strictly after -> Monday
    assert cron.cron_next("0 9 * * 1-5", _ts(2026, 10, 9, 9, 0)) == _ts(2026, 10, 12, 9, 0)
    assert cron.cron_next("*/15 * * * *", _ts(2026, 10, 8, 22, 49)) == _ts(2026, 10, 8, 23, 0)
    assert cron.cron_next("0 0 1 1 *", _ts(2026, 10, 8, 0, 0)) == _ts(2027, 1, 1, 0, 0)
    assert cron.cron_next("0 12 * * 0", _ts(2026, 10, 8, 0, 0)) == _ts(2026, 10, 11, 12, 0)  # Sunday
    assert cron.cron_next("0 12 * * 7", _ts(2026, 10, 8, 0, 0)) == _ts(2026, 10, 11, 12, 0)
    assert cron.cron_next("0 0 29 2 *", _ts(2026, 10, 8, 0, 0)) == _ts(2028, 2, 29, 0, 0)


def test_store_roundtrip_and_next_run(home):
    s = cron.CronStore()
    job = s.create({"prompt": "Rangkum berita", "schedule": "every 1h", "name": "Berita"}, now=1000.0)
    assert job["next_run"] == 1000.0 + 3600 and s.get(job["id"])["name"] == "Berita"
    pub = s.public(job)
    assert pub["state"] == "scheduled" and pub["schedule_display"] == "setiap 1h" and pub["next_run_at"]
    s.update(job["id"], {"enabled": False})
    assert s.public(s.get(job["id"]))["state"] == "paused"
    assert (home / "cron.json").exists()
    assert s.due(10**10) == []
    s.update(job["id"], {"enabled": True})
    assert [j["id"] for j in s.due(10**10)] == [job["id"]]
    assert s.delete(job["id"]) and s.list() == []
    with pytest.raises(cron.ScheduleError):
        s.create({"prompt": "", "schedule": "1h"})


async def _client(monkeypatch):
    monkeypatch.setenv("HERMES_DASHBOARD_SESSION_TOKEN", "tok")
    monkeypatch.setenv("NEOVARCH_CRON_TICK", "0.2")
    gw = Gateway(isolated=False)
    c = TestClient(TestServer(build_app(gw)))
    await c.start_server()
    return gw, c


async def test_cron_api_and_real_run(mock_provider, monkeypatch, home):
    gw, c = await _client(monkeypatch)
    try:
        assert await (await c.get("/api/cron/jobs?token=tok")).json() == []
        targets = await (await c.get("/api/cron/delivery-targets?token=tok")).json()
        assert targets["targets"][0]["id"] == "local"
        r = await c.post("/api/cron/jobs?token=tok", json={"schedule": "nanti", "prompt": "x"})
        assert r.status == 422 and "format jadwal" in (await r.json())["detail"]
        job = await (await c.post("/api/cron/jobs?token=tok",
                                  json={"name": "Sapa", "schedule": "every 1h", "prompt": "Halo jadwal"})).json()
        jid = job["id"]
        assert job["enabled"] and job["state"] == "scheduled" and job["schedule"]["kind"] == "interval"
        upd = await (await c.put(f"/api/cron/jobs/{jid}?token=tok",
                                 json={"updates": {"name": "Sapa pagi", "schedule": "daily 08:00"}})).json()
        assert upd["name"] == "Sapa pagi" and upd["schedule"]["expr"] == "0 8 * * *"
        assert (await (await c.post(f"/api/cron/jobs/{jid}/pause?token=tok")).json())["state"] == "paused"
        assert (await (await c.post(f"/api/cron/jobs/{jid}/resume?token=tok")).json())["enabled"] is True
        # manual trigger runs the prompt through the agent in a fresh "cron" session
        ran = await (await c.post(f"/api/cron/jobs/{jid}/trigger?token=tok")).json()
        assert ran["last_run_at"] and ran["last_error"] is None and ran["run_count"] == 1 and ran["state"] == "scheduled"
        runs = (await (await c.get(f"/api/cron/jobs/{jid}/runs?token=tok")).json())["runs"]
        assert len(runs) == 1 and runs[0]["source"] == "cron"
        rec = gw.store.load(runs[0]["id"])
        assert any("Halo jadwal" in (m.get("content") or "") for m in rec["messages"] if m["role"] == "assistant")
        assert (await c.get("/api/cron/jobs/nope?token=tok")).status == 404
        assert (await (await c.delete(f"/api/cron/jobs/{jid}?token=tok")).json())["ok"]
        assert await (await c.get("/api/cron/jobs?token=tok")).json() == []
    finally:
        await c.close()


async def test_scheduler_fires_due_one_shot(mock_provider, monkeypatch, home):
    gw, c = await _client(monkeypatch)
    try:
        when = dt.datetime.fromtimestamp(time.time() + 1).isoformat(timespec="seconds")
        job = await (await c.post("/api/cron/jobs?token=tok", json={"schedule": when, "prompt": "Sekali saja"})).json()
        for _ in range(100):
            await asyncio.sleep(0.1)
            cur = await (await c.get(f"/api/cron/jobs/{job['id']}?token=tok")).json()
            if cur["state"] == "completed":
                break
        assert cur["state"] == "completed" and cur["run_count"] == 1 and not cur["enabled"] and cur["next_run_at"] is None
    finally:
        await c.close()
