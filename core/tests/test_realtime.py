"""Realtime push: ordered events with seq, replay after reconnect, resync on gaps,
SSE with Last-Event-ID, Kanban/vault pushes, latency, Tailscale addresses."""

import asyncio
import json
import time

from aiohttp.test_utils import TestClient, TestServer

from neovarch import netinfo
from neovarch.realtime import EventBus
from neovarch.server import Gateway, build_app

from test_server import WS


async def _client(monkeypatch):
    monkeypatch.setenv("NEOVARCH_SESSION_TOKEN", "tok")
    gw = Gateway(isolated=False)
    client = TestClient(TestServer(build_app(gw)))
    await client.start_server()
    return gw, client


# ---- bus ----------------------------------------------------------------

def test_bus_replay_gap_and_restart():
    bus = EventBus(ring_size=5)
    for i in range(8):
        bus.publish("x", None if i % 2 else "s1", {"i": i})
    assert bus.seq == 8
    ok = bus.replay(5)
    assert not ok["resync"] and [e["seq"] for e in ok["events"]] == [6, 7, 8]
    assert bus.replay(1)["resync"] and bus.replay(1)["reason"] == "gap"
    assert bus.replay(3, boot_id=bus.boot_id)["resync"] is False      # oldest kept is 4
    assert bus.replay(5, boot_id="other")["reason"] == "restarted"
    assert bus.replay(99)["reason"] == "ahead"
    only_global = bus.replay(5, session_ids=[])
    assert all(e["session_id"] is None for e in only_global["events"])


async def test_bus_slow_consumer_gets_resync():
    bus = EventBus()
    q = bus.subscribe()
    for i in range(3000):
        bus.publish("x", None, {"i": i})
    first = q.get_nowait()
    assert first.get("type") == "resync"


# ---- WebSocket ------------------------------------------------------------

async def test_ws_events_carry_seq_and_replay_after_reconnect(home, monkeypatch):
    gw, c = await _client(monkeypatch)
    try:
        ws = WS(await c.ws_connect("/api/ws?token=tok"))
        ready = (await ws.pump())["params"]
        boot = ready["payload"]["boot_id"]
        assert ready["type"] == "gateway.ready" and isinstance(ready["payload"]["seq"], int)
        gw.broadcast_event("cron.changed", None, {"n": 1})
        ev = await ws.until("cron.changed", timeout=3)
        last = ev["seq"]
        await ws.ws.close()

        # offline: three things happen
        gw.broadcast_event("cron.changed", None, {"n": 2})
        gw.broadcast_event("appearance.changed", None, {"accent": "#2563EB", "base": "dark"})
        gw.broadcast_event("message.delta", "sess-a", {"text": "hai"})

        # reconnect with ?since: global events replayed in order, flagged
        ws2 = WS(await c.ws_connect(f"/api/ws?token=tok&since={last}&boot_id={boot}"))
        await ws2.pump()
        got = [await ws2.pump() for _ in range(2)]
        types = [m["params"]["type"] for m in got]
        assert types == ["cron.changed", "appearance.changed"]
        assert all(m["params"].get("replayed") for m in got)
        assert got[0]["params"]["seq"] == last + 1

        # session events come back through events.replay once re-attached
        rep = (await ws2.call("events.replay", {"since": last, "boot_id": boot, "session_ids": ["sess-a"]}))["result"]
        assert not rep["resync"]
        assert [e["type"] for e in rep["events"]] == ["cron.changed", "appearance.changed", "message.delta"]
        # ...and the connection is now attached to that session for live events
        gw.broadcast_event("message.delta", "sess-a", {"text": "lagi"})
        live = await ws2.until("message.delta", timeout=3)
        assert live["payload"]["text"] == "lagi"

        # stale boot id -> resync.required
        ws3 = WS(await c.ws_connect("/api/ws?token=tok&since=1&boot_id=deadbeef"))
        await ws3.pump()
        assert (await ws3.until("resync.required", timeout=3))["payload"]["reason"] == "restarted"
        ping = (await ws3.call("ping"))["result"]
        assert ping["boot_id"] == boot and ping["seq"] == gw.bus.seq
    finally:
        await c.close()


async def test_kanban_mutation_is_pushed(home, monkeypatch):
    gw, c = await _client(monkeypatch)
    try:
        ws = WS(await c.ws_connect("/api/ws?token=tok"))
        await ws.pump()
        r = await c.post("/api/plugins/kanban/tasks?token=tok", json={"title": "Bab 1"})
        assert r.status in (200, 201)
        ev = await ws.until("kanban.changed", timeout=3)
        assert ev["payload"]["kind"] == "created" and ev["payload"]["payload"]["title"] == "Bab 1"
    finally:
        await c.close()


async def test_vault_write_tool_pushes_vault_changed(home, monkeypatch):
    gw, c = await _client(monkeypatch)
    try:
        ws = WS(await c.ws_connect("/api/ws?token=tok"))
        await ws.pump()
        gw.broadcast_event("tool.complete", None, {"name": "obsidian_write", "tool_id": "t1"})
        assert (await ws.until("vault.changed", timeout=3))["payload"]["tool"] == "obsidian_write"
    finally:
        await c.close()


# ---- SSE ------------------------------------------------------------------

async def _sse_read(resp, n, timeout=5):
    """Read n events (dicts with id/event/data) from an SSE response."""
    out, cur, buf = [], {}, b""
    deadline = time.monotonic() + timeout
    while len(out) < n:
        chunk = await asyncio.wait_for(resp.content.readline(), max(deadline - time.monotonic(), 0.05))
        line = chunk.decode().rstrip("\n")
        if line == "":
            if cur:
                out.append(cur)
            cur = {}
            continue
        if line.startswith(":"):
            continue
        k, _, v = line.partition(": ")
        cur[k] = v
    return out


async def test_sse_stream_resume_with_last_event_id(home, monkeypatch):
    gw, c = await _client(monkeypatch)
    try:
        assert (await c.get("/api/events")).status == 401
        resp = await c.get("/api/events?token=tok")
        hello = (await _sse_read(resp, 1))[0]
        assert hello["event"] == "hello" and json.loads(hello["data"])["boot_id"] == gw.bus.boot_id
        gw.broadcast_event("office.update", None, {"agents": []})
        gw.broadcast_event("kanban.changed", None, {"kind": "created"})
        evs = await _sse_read(resp, 2)
        assert [e["event"] for e in evs] == ["office.update", "kanban.changed"]
        last = int(evs[0]["id"])
        resp.close()

        gw.broadcast_event("cron.changed", None, {})
        resp2 = await c.get("/api/events?token=tok", headers={"Last-Event-ID": str(last)})
        evs2 = await _sse_read(resp2, 3)
        assert [e["event"] for e in evs2] == ["hello", "kanban.changed", "cron.changed"]
        resp2.close()

        # type filter + gap -> resync
        resp3 = await c.get("/api/events?token=tok&since=0&boot_id=nope&types=cron.")
        evs3 = await _sse_read(resp3, 2)
        assert evs3[1]["event"] == "resync"
        gw.broadcast_event("office.update", None, {})
        gw.broadcast_event("cron.changed", None, {"x": 1})
        assert (await _sse_read(resp3, 1))[0]["event"] == "cron.changed"
        resp3.close()

        rep = await (await c.get(f"/api/events/replay?token=tok&since={last}")).json()
        assert rep["resync"] is False and rep["events"][0]["type"] == "kanban.changed"
    finally:
        await c.close()


async def test_push_latency_under_300ms_with_simulated_rtt(home, monkeypatch):
    """Publish -> client receive, over WS and SSE, with a 150 ms simulated network
    RTT (75 ms each way, as on a phone over Tailscale/LTE). Budget: 300 ms."""
    gw, c = await _client(monkeypatch)
    one_way = 0.075
    try:
        ws = WS(await c.ws_connect("/api/ws?token=tok"))
        await ws.pump()
        sse = await c.get("/api/events?token=tok")
        await _sse_read(sse, 1)
        worst = 0.0
        for i in range(10):
            t0 = time.monotonic()
            await asyncio.sleep(one_way)                 # client -> core (the action)
            gw.broadcast_event("office.update", None, {"i": i})
            msg = await ws.ws.receive_json(timeout=2)
            (sev,) = await _sse_read(sse, 1)
            await asyncio.sleep(one_way)                 # core -> client (the push)
            assert msg["params"]["payload"]["i"] == i and json.loads(sev["data"])["payload"]["i"] == i
            worst = max(worst, time.monotonic() - t0)
        assert worst < 0.3, f"push round trip {worst * 1000:.0f} ms"
        sse.close()
    finally:
        await c.close()


# ---- Tailscale / addresses -------------------------------------------------

def test_netinfo_lan_first_then_magicdns_then_tailnet():
    ts = {"dns_name": "pc-kantor.tail1234.ts.net", "ips": ["100.101.102.103"], "online": True,
          "backend_state": "Running"}
    out = netinfo.addresses(9319, ts=ts, iface=["127.0.0.1", "10.0.0.7", "192.168.1.5", "100.101.102.103",
                                                "169.254.1.1", "8.8.8.8"])
    assert out["lan"] == ["192.168.1.5", "10.0.0.7"]
    assert out["tailscale"]["magic_dns"] == "pc-kantor.tail1234.ts.net"
    assert out["urls"] == ["http://192.168.1.5:9319", "http://10.0.0.7:9319",
                           "http://pc-kantor.tail1234.ts.net:9319", "http://100.101.102.103:9319"]
    none = netinfo.addresses(9319, ts=None, iface=["100.80.1.2"])
    assert none["tailscale"]["installed"] is False and none["urls"] == ["http://100.80.1.2:9319"]


def test_tailscale_status_parse(monkeypatch):
    monkeypatch.setattr(netinfo.shutil, "which", lambda _n: "/usr/bin/tailscale")

    class P:
        stdout = json.dumps({"BackendState": "Running",
                             "Self": {"DNSName": "pc.tailnet.ts.net.", "TailscaleIPs": ["100.64.0.9", "fd7a::1"]}})
    st = netinfo.tailscale_status(run=lambda *a, **k: P())
    assert st == {"dns_name": "pc.tailnet.ts.net", "ips": ["100.64.0.9"], "online": True, "backend_state": "Running"}


async def test_network_addresses_route(home, monkeypatch):
    monkeypatch.setattr(netinfo, "tailscale_status", lambda: None)
    gw, c = await _client(monkeypatch)
    try:
        body = await (await c.get("/api/network/addresses?token=tok")).json()
        assert body["port"] == gw.port and "lan" in body and "tailscale" in body
    finally:
        await c.close()
