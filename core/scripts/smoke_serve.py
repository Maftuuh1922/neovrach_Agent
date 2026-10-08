"""End-to-end smoke test of `neovarch serve` against the mock provider.

    python core/scripts/smoke_serve.py [--port 9319] [--llm-port 18080]

Starts tests/mock_llm.py, runs `python -m neovarch serve --port <port>` in a
throwaway NEOVARCH_HOME, then over the WebSocket JSON-RPC API calls
session.create and prompt.submit ("jalankan tool") and checks that the reply
streams (several message.delta events) and carries exactly one tool call.
Prints a JSON report and exits non-zero on failure.
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


def wait_port(port: int, timeout: float = 20) -> None:
    import socket

    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        with socket.socket() as s:
            if s.connect_ex(("127.0.0.1", port)) == 0:
                return
        time.sleep(0.2)
    raise TimeoutError(f"port {port} never opened")


async def drive(port: int, token: str) -> dict:
    events: list[dict] = []
    async with aiohttp.ClientSession() as http:
        async with http.ws_connect(f"http://127.0.0.1:{port}/api/ws?token={token}") as ws:
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

            sid = (await call("session.create", {"source": "smoke"}))["result"]["session_id"]
            assert (await call("prompt.submit", {"session_id": sid, "text": "jalankan tool"}))["result"]["ok"]
            deadline = time.monotonic() + 30
            while not any(e["type"] == "message.complete" for e in events):
                msg = await ws.receive_json(timeout=max(deadline - time.monotonic(), 0.1))
                if msg.get("method") == "event":
                    events.append(msg["params"])
    kinds = [e["type"] for e in events]
    done = next(e for e in events if e["type"] == "message.complete")
    return {
        "session_id": sid,
        "deltas": kinds.count("message.delta"),
        "tool_starts": [e["payload"].get("name") for e in events if e["type"] == "tool.start"],
        "tool_completes": kinds.count("tool.complete"),
        "final_text": done["payload"].get("text"),
        "event_kinds": sorted(set(kinds)),
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=9319)
    ap.add_argument("--llm-port", type=int, default=18080)
    args = ap.parse_args()
    home = Path(tempfile.mkdtemp(prefix="neovarch-smoke-"))
    env = {k: v for k, v in os.environ.items() if not k.startswith(("HERMES_", "NEOVARCH_"))}
    token = "smoke-token"
    env.update(NEOVARCH_HOME=str(home), HERMES_DASHBOARD_SESSION_TOKEN=token, PYTHONPATH=str(CORE))
    (home).mkdir(exist_ok=True)
    (home / "config.yaml").write_text(
        "model:\n  provider: custom\n  default: mock-model\n"
        f"  base_url: http://127.0.0.1:{args.llm_port}/v1\n", encoding="utf-8")
    llm = subprocess.Popen([sys.executable, str(CORE / "tests" / "mock_llm.py"), "--port", str(args.llm_port)],
                           env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    srv = subprocess.Popen([sys.executable, "-m", "neovarch", "serve", "--port", str(args.port)],
                           env=env, cwd=str(home), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    try:
        wait_port(args.llm_port)
        ready = srv.stdout.readline().strip()
        report = {"ready_line": ready, **asyncio.run(drive(args.port, token))}
        ok = (ready == f"HERMES_BACKEND_READY port={args.port}" and report["deltas"] > 1
              and report["tool_starts"] == ["shell"] and report["tool_completes"] == 1
              and report["final_text"] == "Selesai. Hasil alat: neovarch-tool-ok")
        report["ok"] = ok
        print(json.dumps(report, indent=2, ensure_ascii=False))
        return 0 if ok else 1
    finally:
        for p in (srv, llm):
            p.terminate()
            try:
                p.wait(5)
            except subprocess.TimeoutExpired:
                p.kill()


if __name__ == "__main__":
    raise SystemExit(main())
