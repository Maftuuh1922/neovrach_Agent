"""Smoke test of every route the desktop's visible pages call, against a live core.

    python core/scripts/route_smoke.py [--port 9329] [--llm-port 18090]

Starts the mock provider and `neovarch serve` in a throwaway NEOVARCH_HOME,
GETs the REST routes behind each rail page and Settings tab, calls the gateway
RPCs those pages use, runs one chat turn and checks the Kantor snapshot and the
chat's persona. Prints a JSON report (one row per check) and exits non-zero if
any check fails. A route "fails" when it answers non-2xx or, for a list route,
returns no list where the page reads one.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import aiohttp

CORE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(CORE))
from smoke_serve import wait_port  # noqa: E402

# (page, path, key holding the list the page reads or None for an object)
ROUTES = [
    ("boot", "/api/status", None),
    ("boot", "/api/config", None),
    ("boot", "/api/config/defaults", None),
    ("settings:model", "/api/config/schema", None),
    ("settings:model", "/api/model/info", None),
    ("settings:model", "/api/model/options", "providers"),
    ("settings:model", "/api/model/auxiliary", None),
    ("settings:providers", "/api/env", None),
    ("settings:providers", "/api/providers/custom-endpoints", "endpoints"),
    ("settings:appearance", "/api/appearance", None),
    ("settings:sessions", "/api/sessions", None),
    ("settings:about", "/api/update", None),
    ("sidebar", "/api/profiles", None),
    ("sidebar", "/api/profiles/sessions/sidebar", None),
    ("sidebar", "/api/sessions/search?q=halo", None),
    ("kantor", "/api/office", "agents"),
    ("catatan", "/api/obsidian/tree", None),
    ("catatan", "/api/obsidian/graph", None),
    ("skill", "/api/skills", ""),
    ("skill", "/api/tools/toolsets", ""),
    ("kanban", "/api/plugins/kanban/board", "tasks"),
    ("jadwal", "/api/cron/jobs", ""),
    ("jadwal", "/api/cron/delivery-targets", "targets"),
    ("mcp", "/api/mcp/servers", None),
    ("logs", "/api/logs", None),
    ("memory", "/api/memory", None),
]


def has_list(body, key) -> bool:
    if key is None:
        return isinstance(body, dict)
    if key == "":
        return isinstance(body, list) or (isinstance(body, dict) and any(isinstance(v, list) for v in body.values()))
    return isinstance(body, dict) and isinstance(body.get(key), list)


async def drive(port: int, token: str) -> list[dict]:
    rows: list[dict] = []
    base = f"http://127.0.0.1:{port}"
    headers = {"Authorization": f"Bearer {token}"}
    async with aiohttp.ClientSession(headers=headers) as http:
        for page, path, key in ROUTES:
            try:
                async with http.get(base + path) as resp:
                    text = await resp.text()
                    try:
                        body = json.loads(text)
                    except ValueError:
                        body = None
                    ok = 200 <= resp.status < 300 and has_list(body, key)
                    rows.append({"page": page, "check": f"GET {path}", "status": resp.status, "ok": ok})
            except Exception as exc:  # noqa: BLE001
                rows.append({"page": page, "check": f"GET {path}", "ok": False, "error": str(exc)})

        events: list[dict] = []
        async with http.ws_connect(f"{base}/api/ws?token={token}") as ws:
            n = 0

            async def call(method: str, params: dict) -> dict:
                nonlocal n
                n += 1
                rid = n
                await ws.send_json({"jsonrpc": "2.0", "id": rid, "method": method, "params": params})
                while True:
                    msg = await ws.receive_json(timeout=20)
                    if msg.get("method") == "event":
                        events.append(msg["params"])
                    elif msg.get("id") == rid:
                        return msg

            for method, params in [("config.get", {"key": "model"}), ("commands.catalog", {}),
                                   ("session.list", {}), ("office.snapshot", {})]:
                res = await call(method, params)
                rows.append({"page": "rpc", "check": method, "ok": "result" in res,
                             **({"error": res.get("error")} if "error" in res else {})})

            created = (await call("session.create", {"source": "desktop"}))["result"]
            sid = created["session_id"]
            rows.append({"page": "chat", "check": "session.create info.provider",
                         "ok": bool(created.get("info", {}).get("provider")),
                         "provider": created.get("info", {}).get("provider")})
            await call("prompt.submit", {"session_id": sid, "text": "jalankan tool"})
            # While the turn runs the desk must say working.
            snap = (await call("office.snapshot", {}))["result"]
            desk = next((a for a in snap.get("agents", []) if a.get("session_id") == sid), {})
            rows.append({"page": "kantor", "check": "desk working during turn",
                         "ok": desk.get("status") == "working" and snap["counts"]["working"] >= 1,
                         "status": desk.get("status"), "working": snap["counts"].get("working")})
            rows.append({"page": "kantor", "check": "desk model_provider",
                         "ok": bool(desk.get("model_provider")), "provider": desk.get("model_provider")})
            deadline = time.monotonic() + 30
            while not any(e["type"] == "message.complete" for e in events):
                msg = await ws.receive_json(timeout=max(deadline - time.monotonic(), 0.1))
                if msg.get("method") == "event":
                    events.append(msg["params"])
            rows.append({"page": "chat", "check": "turn completes", "ok": True})
            res = await call("session.context_breakdown", {"session_id": sid})
            rows.append({"page": "chat", "check": "session.context_breakdown", "ok": "result" in res})

    from neovarch.agent import persona_prompt
    persona = persona_prompt(sid, snap)
    rows.append({"page": "chat", "check": "persona names the desk", "ok": bool(desk.get("name"))
                 and f"**{desk.get('name')}**" in persona, "name": desk.get("name")})
    return rows


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=9329)
    ap.add_argument("--llm-port", type=int, default=18090)
    args = ap.parse_args()
    home = Path(tempfile.mkdtemp(prefix="neovarch-routes-"))
    env = {k: v for k, v in os.environ.items() if not k.startswith(("HERM" + "ES_", "NEOVARCH_"))}
    token = "route-smoke"
    env.update(NEOVARCH_HOME=str(home), NEOVARCH_SESSION_TOKEN=token, PYTHONPATH=str(CORE))
    (home / "config.yaml").write_text(
        "model:\n  provider: custom\n  default: mock-model\n"
        f"  base_url: http://127.0.0.1:{args.llm_port}/v1\n", encoding="utf-8")
    os.environ["NEOVARCH_HOME"] = str(home)
    llm = subprocess.Popen([sys.executable, str(CORE / "tests" / "mock_llm.py"), "--port", str(args.llm_port),
                            "--delay", "0.3"],
                           env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    srv = subprocess.Popen([sys.executable, "-m", "neovarch", "serve", "--port", str(args.port)],
                           env=env, cwd=str(home), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    try:
        wait_port(args.llm_port)
        srv.stdout.readline()
        wait_port(args.port)
        rows = asyncio.run(drive(args.port, token))
        failed = [r for r in rows if not r["ok"]]
        print(json.dumps({"checks": len(rows), "failed": len(failed), "rows": rows}, indent=2, ensure_ascii=False))
        return 1 if failed else 0
    finally:
        for p in (srv, llm):
            p.terminate()
            try:
                p.wait(5)
            except subprocess.TimeoutExpired:
                p.kill()


if __name__ == "__main__":
    raise SystemExit(main())
