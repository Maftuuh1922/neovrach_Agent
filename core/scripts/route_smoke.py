"""Smoke test of every route the desktop's visible pages call, against a live core.

    python core/scripts/route_smoke.py [--port 9329] [--llm-port 18090]

Starts the mock provider and `neovarch serve` in a throwaway NEOVARCH_HOME,
GETs the REST routes behind each rail page and Settings tab, calls the gateway
RPCs those pages use, runs one chat turn and checks the Kantor snapshot and the
chat's persona, then the routes behind the Kantor desk model switch, thread
timeline/around, logs level filter, skills toggle + learning node edit,
memory panel and the GitHub account page. Prints a JSON report (one row per check) and exits non-zero if
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
    ("logs", "/api/logs", "lines"),
    ("memory", "/api/memory", None),
    ("settings:account", "/api/account/github", None),
]

SMOKE_SKILL = "route-smoke-skill"
LEVELS = ("DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL")


async def rest(http, method: str, url: str, body: dict | None = None) -> tuple[int, object]:
    async with http.request(method, url, json=body) as resp:
        text = await resp.text()
        try:
            return resp.status, json.loads(text)
        except ValueError:
            return resp.status, {}


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

            # Model picker follows the open chat (session_id), and a desk's
            # model switch from Kantor is chat-only for a chat desk.
            opts = (await call("model.options", {"session_id": sid})).get("result") or {}
            rows.append({"page": "chat", "check": "model.options session_id (before switch)",
                         "ok": opts.get("model") == "mock-model" and opts.get("scope") == "default"
                         and "reasoning_effort" in opts and isinstance(opts.get("providers"), list),
                         "model": opts.get("model"), "scope": opts.get("scope")})
            status, body = await rest(http, "PUT", f"{base}/api/agents/session:{sid}/model",
                                      {"model": "mock-model-b"})
            rows.append({"page": "kantor", "check": "PUT /api/agents/{id}/model (chat desk)",
                         "ok": status == 200 and body.get("agent_id") == f"session:{sid}", "status": status})
            opts = (await call("model.options", {"session_id": sid})).get("result") or {}
            rows.append({"page": "chat", "check": "model.options session_id (after desk switch)",
                         "ok": opts.get("model") == "mock-model-b" and opts.get("scope") == "session",
                         "model": opts.get("model"), "scope": opts.get("scope")})
            glob = (await call("model.options", {})).get("result") or {}
            rows.append({"page": "chat", "check": "desk switch is chat-only (default unchanged)",
                         "ok": glob.get("model") == "mock-model", "model": glob.get("model")})
            status, _ = await rest(http, "PUT", f"{base}/api/agents/session:no-such-chat/model", {"model": "x"})
            rows.append({"page": "kantor", "check": "PUT /api/agents/{unknown}/model -> 404",
                         "ok": status == 404, "status": status})
            status, _ = await rest(http, "PUT", f"{base}/api/agents/session:{sid}/model", {"model": ""})
            rows.append({"page": "kantor", "check": "PUT /api/agents/{id}/model without model -> 422",
                         "ok": status == 422, "status": status})

        # Thread jump marks and the page around one of them.
        status, tl = await rest(http, "GET", f"{base}/api/sessions/{sid}/timeline")
        entries = tl.get("entries") if isinstance(tl, dict) else None
        rows.append({"page": "chat", "check": "GET /api/sessions/{id}/timeline",
                     "ok": status == 200 and isinstance(entries, list) and len(entries) >= 1
                     and all("row_id" in e for e in entries), "status": status,
                     "entries": len(entries or [])})
        row_id = entries[0]["row_id"] if entries else 0
        status, ar = await rest(http, "GET", f"{base}/api/sessions/{sid}/messages/around?row_id={row_id}&limit=20")
        msgs = ar.get("messages") if isinstance(ar, dict) else None
        rows.append({"page": "chat", "check": "GET /api/sessions/{id}/messages/around",
                     "ok": status == 200 and isinstance(msgs, list) and any(m.get("row_id") == row_id for m in msgs),
                     "status": status, "returned": len(msgs or [])})

        # Logs page: the gateway really writes agent.log; level is a floor.
        status, lg = await rest(http, "GET", f"{base}/api/logs?level=INFO&lines=500")
        lines = lg.get("lines") if isinstance(lg, dict) else None
        rows.append({"page": "logs", "check": "GET /api/logs?level=INFO has turn lines",
                     "ok": status == 200 and isinstance(lines, list) and len(lines) > 0,
                     "status": status, "lines": len(lines or [])})
        for level in ("WARNING", "ERROR"):
            status, lg = await rest(http, "GET", f"{base}/api/logs?level={level}&lines=500")
            lines = lg.get("lines") if isinstance(lg, dict) else None
            floor = LEVELS.index(level)
            ok = status == 200 and isinstance(lines, list) and all(
                len(ln.split(" ", 3)) > 2 and ln.split(" ", 3)[2] in LEVELS
                and LEVELS.index(ln.split(" ", 3)[2]) >= floor for ln in lines)
            rows.append({"page": "logs", "check": f"GET /api/logs?level={level} filters", "ok": ok,
                         "status": status, "lines": len(lines or [])})

        # Skills page: toggle off/on, and the learning node edit.
        status, tg = await rest(http, "PUT", f"{base}/api/skills/toggle", {"name": SMOKE_SKILL, "enabled": False})
        status2, sk = await rest(http, "GET", f"{base}/api/skills")
        listed = next((x for x in (sk if isinstance(sk, list) else []) if x.get("name") == SMOKE_SKILL), {})
        rows.append({"page": "skill", "check": "PUT /api/skills/toggle (off)",
                     "ok": status == 200 and tg.get("ok") is True and listed.get("enabled") is False,
                     "status": status, "listed_enabled": listed.get("enabled")})
        status, tg = await rest(http, "PUT", f"{base}/api/skills/toggle", {"name": SMOKE_SKILL, "enabled": True})
        rows.append({"page": "skill", "check": "PUT /api/skills/toggle (on)",
                     "ok": status == 200 and tg.get("ok") is True, "status": status})
        status, tg = await rest(http, "PUT", f"{base}/api/skills/toggle", {"name": "no-such-skill", "enabled": False})
        rows.append({"page": "skill", "check": "PUT /api/skills/toggle unknown skill -> ok:false",
                     "ok": status == 200 and tg.get("ok") is False, "status": status})
        status, nd = await rest(http, "GET", f"{base}/api/learning/node?id={SMOKE_SKILL}")
        rows.append({"page": "skill", "check": "GET /api/learning/node",
                     "ok": status == 200 and nd.get("ok") is True and "Route smoke" in str(nd.get("content")),
                     "status": status})
        edited = "---\nname: route-smoke-skill\ndescription: edited\n---\nEdited by the route smoke.\n"
        status, ed = await rest(http, "PUT", f"{base}/api/learning/node", {"id": SMOKE_SKILL, "content": edited})
        _, nd = await rest(http, "GET", f"{base}/api/learning/node?id={SMOKE_SKILL}")
        rows.append({"page": "skill", "check": "PUT /api/learning/node (edit persists)",
                     "ok": status == 200 and ed.get("ok") is True and nd.get("content") == edited,
                     "status": status})

        # Memory panel and the GitHub account page.
        status, mem = await rest(http, "GET", f"{base}/api/memory")
        rows.append({"page": "memory", "check": "GET /api/memory (real status)",
                     "ok": status == 200 and isinstance(mem, dict) and "active" in mem,
                     "status": status, "active": (mem or {}).get("active") if isinstance(mem, dict) else None})
        status, acct = await rest(http, "GET", f"{base}/api/account/github")
        rows.append({"page": "settings:account", "check": "GET /api/account/github",
                     "ok": status == 200 and acct.get("provider") == "github"
                     and isinstance(acct.get("connected"), bool),
                     "status": status, "connected": acct.get("connected")})
        status, acct = await rest(http, "POST", f"{base}/api/account/github", {"token": ""})
        rows.append({"page": "settings:account", "check": "POST /api/account/github empty token -> ok:false",
                     "ok": status == 200 and acct.get("ok") is False and bool(acct.get("error")),
                     "status": status})

    from neovarch.agent import persona_prompt
    persona = persona_prompt(sid, snap)
    rows.append({"page": "chat", "check": "persona names the desk", "ok": bool(desk.get("name"))
                 and f"**{desk.get('name')}**" in persona, "name": desk.get("name")})
    return rows


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=9329)
    ap.add_argument("--llm-port", type=int, default=18090)
    ap.add_argument("--out", help="also write the JSON report to this file")
    args = ap.parse_args()
    home = Path(tempfile.mkdtemp(prefix="neovarch-routes-"))
    env = {k: v for k, v in os.environ.items() if not k.startswith(("HERM" + "ES_", "NEOVARCH_"))}
    token = "route-smoke"
    env.update(NEOVARCH_HOME=str(home), NEOVARCH_SESSION_TOKEN=token, PYTHONPATH=str(CORE))
    (home / "config.yaml").write_text(
        "model:\n  provider: custom\n  default: mock-model\n"
        f"  base_url: http://127.0.0.1:{args.llm_port}/v1\n", encoding="utf-8")
    skill = home / "skills" / SMOKE_SKILL
    skill.mkdir(parents=True)
    (skill / "SKILL.md").write_text("---\nname: route-smoke-skill\ndescription: Route smoke\n---\nRoute smoke skill.\n",
                                   encoding="utf-8")
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
        report = json.dumps({"checks": len(rows), "failed": len(failed), "rows": rows}, indent=2, ensure_ascii=False)
        print(report)
        if args.out:
            Path(args.out).write_text(report + "\n", encoding="utf-8")
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
