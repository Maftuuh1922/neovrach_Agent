"""The agent loop: stream a completion, run the tools it asks for, repeat."""

from __future__ import annotations

import json
import os
import time
from pathlib import Path
from typing import Any, Callable

from neovarch import config as cfgmod
from neovarch.llm import Completion, LLMError, stream_chat
from neovarch.store import SessionStore
from neovarch.tools import ToolContext, list_skills, run_tool, tool_schemas

EmitFn = Callable[[str, dict[str, Any]], Any]


def system_prompt(cfg: dict, cwd: Path, query: str = "") -> str:
    parts = [cfgmod.soul_text().strip()]
    extra = str(cfgmod.get_path(cfg, "agent.system_prompt", "") or "").strip()
    if extra:
        parts.append(extra)
    home = cfgmod.neovarch_home()
    notes = sorted((home / "memory").glob("*.md")) if (home / "memory").exists() else []
    if notes:
        mem = []
        for p in notes[:20]:
            text = p.read_text(encoding="utf-8", errors="replace").strip()
            if text:
                mem.append(f"## {p.stem}\n{text[:4000]}")
        if mem:
            parts.append("# Memory notes (from earlier sessions)\n" + "\n\n".join(mem))
    parts.extend(_vault_prompt(cfg, query))
    skills = list_skills()
    if skills:
        parts.append("# Skills (read one with the `skill` tool before using it)\n"
                     + "\n".join(f"- {s['name']}: {s['description']}" for s in skills))
    parts.append(f"Current working directory: {cwd}\nDate: {time.strftime('%Y-%m-%d %H:%M %Z')}")
    return "\n\n".join(parts)


def _vault_prompt(cfg: dict, query: str) -> list[str]:
    from neovarch import obsidian
    vault = obsidian.vault_path(cfg)
    if vault is None or not vault.is_dir():
        return []
    out = [f"# Obsidian vault (long-term memory)\nThe user's Obsidian vault at {vault} is your long-term memory. "
           "Use obsidian_search / obsidian_read to recall, obsidian_write to save durable facts as markdown notes "
           "with [[wikilinks]] and #tags, and obsidian_links to follow backlinks. Never write outside the vault."]
    try:
        notes = obsidian.relevant_notes(vault, query) if query else []
    except Exception:  # retrieval must never break a turn
        notes = []
    if notes:
        out.append("# Relevant vault notes (keyword match for this message)\n"
                   + "\n\n".join(f"## {n['path']}\n{n['content']}" for n in notes))
    return out


def _preview(args: dict) -> str:
    for key in ("command", "path", "url", "name", "action"):
        if args.get(key):
            return str(args[key])[:200]
    return json.dumps(args, ensure_ascii=False)[:200]


class Agent:
    def __init__(self, rec: dict, store: SessionStore, ctx: ToolContext, emit: EmitFn):
        self.rec = rec
        self.store = store
        self.ctx = ctx
        self.emit = emit
        self.interrupted = False

    def interrupt(self) -> None:
        self.interrupted = True

    async def run_turn(self, user_text: str) -> str:
        cfg = cfgmod.load_config()
        from neovarch import models as modelsmod
        endpoint = modelsmod.endpoint_for(cfg, "session:" + str(self.rec.get("id") or ""))
        self.ctx.approvals_mode = str(cfgmod.get_path(cfg, "approvals.mode", "ask") or "ask")
        max_turns = int(cfgmod.get_path(cfg, "agent.max_turns", 30) or 30)
        self.interrupted = False
        messages = self.rec["messages"]
        messages.append({"role": "user", "content": user_text, "ts": time.time()})
        if not self.rec.get("title"):
            self.rec["title"] = user_text.strip().splitlines()[0][:60] if user_text.strip() else ""
            if self.rec["title"]:
                self.emit("session.title", {"title": self.rec["title"]})
        self.rec["model"] = endpoint["model"]
        self.store.save(self.rec)

        self.emit("message.start", {})
        started = time.monotonic()
        final_text = ""
        usage: dict[str, Any] = {}
        error = None
        sys_prompt = system_prompt(cfg, self.ctx.cwd, user_text)
        try:
            for _ in range(max_turns):
                if self.interrupted:
                    error = "interrupted"
                    break
                wire = [{"role": "system", "content": sys_prompt}] + [_wire(m) for m in messages]
                comp: Completion = await stream_chat(
                    base_url=endpoint["base_url"], api_key=endpoint["api_key"], model=endpoint["model"],
                    messages=wire, tools=tool_schemas(),
                    on_text=lambda t: self.emit("message.delta", {"text": t}),
                    on_reasoning=lambda t: self.emit("reasoning.delta", {"text": t}),
                    extra_headers=endpoint.get("headers") or None,
                    verify_ssl=endpoint.get("verify_ssl", True),
                )
                usage = comp.usage or usage
                assistant: dict[str, Any] = {"role": "assistant", "content": comp.text, "ts": time.time()}
                if comp.reasoning:
                    assistant["reasoning"] = comp.reasoning
                if comp.tool_calls:
                    assistant["tool_calls"] = [{"id": c.id, "type": "function",
                                                "function": {"name": c.name, "arguments": c.arguments or "{}"}}
                                               for c in comp.tool_calls]
                messages.append(assistant)
                self.store.save(self.rec)
                if not comp.tool_calls:
                    final_text = comp.text
                    break
                for call in comp.tool_calls:
                    args = call.parsed_args()
                    self.emit("tool.start", {"tool_id": call.id, "name": call.name, "args": args,
                                             "args_text": call.arguments, "preview": _preview(args)})
                    t0 = time.monotonic()
                    result = await run_tool(call.name, args, self.ctx) if not self.interrupted else "interrupted"
                    dur = time.monotonic() - t0
                    messages.append({"role": "tool", "tool_call_id": call.id, "name": call.name,
                                     "content": result, "ts": time.time()})
                    self.store.save(self.rec)
                    self.emit("tool.complete", {"tool_id": call.id, "name": call.name,
                                                "summary": result.splitlines()[0][:160] if result else "",
                                                "result": result[:4000], "result_text": result[:4000],
                                                "duration_s": round(dur, 2)})
            else:
                error = f"stopped after {max_turns} model calls"
        except LLMError as exc:
            error = _explain(str(exc), endpoint)
        if error and error != "interrupted":
            self.emit("error", {"message": error})
        elapsed = max(time.monotonic() - started, 1e-6)
        out_tokens = int(usage.get("completion_tokens") or 0)
        ctx_len = int(cfgmod.get_path(cfg, "model.context_length", 128000) or 128000)
        self.emit("message.complete", {
            "text": final_text,
            "usage": {**usage, "avg_tps": round(out_tokens / elapsed, 1) if out_tokens else None,
                      "context_percent": round(100 * int(usage.get("prompt_tokens") or 0) / ctx_len, 1)},
            **({"error": error} if error else {}),
            **({"status": "interrupted"} if error == "interrupted" else {}),
        })
        return final_text


def _explain(error: str, endpoint: dict) -> str:
    """A 9Router failure the user can act on, in Indonesian."""
    if endpoint.get("provider") != "9router":
        return error
    from neovarch import router9
    root = router9.root_url(endpoint.get("base_url") or router9.DEFAULT_BASE_URL)
    if error.startswith("could not reach"):
        return (f"9Router belum berjalan di {root}. Buka Pengaturan \u25b8 Model lalu tekan Jalankan, "
                f"atau pasang dulu: {router9.INSTALL_COMMAND}")
    if "HTTP 401" in error:
        return (f"9Router meminta API key. Buka dashboard 9Router ({root}/dashboard) \u25b8 Endpoint, "
                "buat API key, lalu tempel di Pengaturan \u25b8 Model.")
    return error


def _wire(m: dict) -> dict:
    out = {"role": m["role"], "content": m.get("content") or ("" if m["role"] != "assistant" else None)}
    if m["role"] == "assistant" and m.get("tool_calls"):
        out["tool_calls"] = m["tool_calls"]
        if not out["content"]:
            out["content"] = None
    if m["role"] == "tool":
        out["tool_call_id"] = m.get("tool_call_id", "")
    return out


def default_cwd() -> Path:
    return Path(os.environ.get("NEOVARCH_CWD") or os.getcwd())
