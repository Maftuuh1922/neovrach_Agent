"""The agent loop: stream a completion, run the tools it asks for, repeat."""

from __future__ import annotations

import json
import os
import time
from pathlib import Path
from typing import Any, Callable

from neovarch import config as cfgmod
from neovarch import session_settings
from neovarch.llm import Completion, LLMError, stream_chat
from neovarch.store import SessionStore
from neovarch.tools import ToolContext, list_skills, run_tool, tool_schemas

EmitFn = Callable[[str, dict[str, Any]], Any]


# What the agent knows about the app it lives in. Without it a question like
# "can you see the Kantor?" sent the agent grepping app.asar and site-packages.
APP_KNOWLEDGE = """# About the Neovarch app you are running in
You are the agent inside Neovarch Agent: a desktop app (Windows/Linux) plus a phone remote app. The desktop
talks to this core (the `neovarch serve` gateway). Its pages, from the left rail:
- Obrolan / Sesi: chats with you; the session list has search, pinned chats and grouping.
- Kantor (Office): a 3D office where each running or recent chat and each Kanban task is an agent "employee"
  at a desk (status working / waiting-approval / idle, current task, model), with a live activity feed and a garden.
- Kanban: the task board (todo, ready, running, blocked, done) shared with the Kantor.
- Catatan / Obsidian: the user's Obsidian vault (tree, notes, backlinks, graph); it is also your long-term memory.
- Skill: installed skills (folders with SKILL.md under ~/.neovarch/skills).
- Artefak, Jadwal (cron jobs), Pasangkan HP (pair the phone remote by QR), Pengaturan (model, providers,
  custom OpenAI-compatible endpoints, appearance, security/approvals, memory).
How to answer questions about the app:
- Answer from this description directly. Call `office_status` to see the live Kantor (agents, status, tasks,
  active model); never search the filesystem, the app bundle (app.asar) or Python site-packages to learn
  what the app has.
- Use tools only when the request needs them. For exploration, stop and answer after at most 5 tool calls
  unless the task clearly needs more; prefer narrow commands with a short timeout over broad greps."""


def persona_prompt(session_id: str | None, office: dict | None) -> str:
    """Who this chat is in the Kantor: the desk the session sits at.

    Every chat is a pegawai in the Kantor (name derived from the session id).
    Without this the agent answered "lagi apa kamu?" with a generic
    "Saya Neovarch Agent... standby" instead of its own desk and task."""
    if not session_id:
        return ""
    from neovarch.office import staff_name
    agents = (office or {}).get("agents") or []
    desk = next((a for a in agents if isinstance(a, dict) and
                 (a.get("session_id") == session_id or a.get("id") == f"session:{session_id}")), None)
    name = str((desk or {}).get("name") or staff_name(session_id))
    role = str((desk or {}).get("role") or "Agen")
    status_word = {"working": "sedang bekerja (giliran ini)", "waiting-approval": "menunggu persetujuan pengguna",
                   "idle": "santai di meja"}.get(str((desk or {}).get("status") or "working"), "di meja")
    lines = [f"# Identitasmu di Kantor\nKamu adalah **{name}**, pegawai Kantor Neovarch ({role}). "
             f"Obrolan ini adalah mejamu; di Kantor kamu tampil sebagai {name}. Saat ditanya siapa kamu, sedang apa, "
             f"atau \"lagi apa\", jawab sebagai {name} secara natural dan pakai data nyata di bawah ini "
             "(jangan jawab generik seperti \"Saya Neovarch Agent, standby\")."]
    if desk:
        if desk.get("title"):
            lines.append(f"- Judul obrolan: {desk['title']}")
        lines.append(f"- Status: {status_word}")
        if desk.get("current_task"):
            lines.append(f"- Tugas saat ini: {desk['current_task']}")
        if desk.get("current_tool"):
            lines.append(f"- Tool yang sedang dipakai: {desk['current_tool']}")
        if desk.get("model"):
            lines.append(f"- Model: {desk['model']}")
        if desk.get("last_activity_text"):
            lines.append(f"- Aktivitas terakhir: {desk['last_activity_text']}")
    counts = (office or {}).get("counts") or {}
    others = [a for a in agents if isinstance(a, dict) and a is not desk][:6]
    if counts or others:
        lines.append(f"- Kantor sekarang: {counts.get('working', 0)} bekerja, "
                     f"{counts.get('waiting-approval', 0)} menunggu, {counts.get('idle', 0)} santai")
        for a in others:
            task = f" — {a['current_task']}" if a.get("current_task") else ""
            lines.append(f"  - rekan {a.get('name')}: {a.get('status')}{task}")
    lines.append("Untuk detail terbaru panggil `office_status`.")
    return "\n".join(lines)


def system_prompt(cfg: dict, cwd: Path, query: str = "", persona: str = "") -> str:
    parts = [cfgmod.soul_text().strip(), APP_KNOWLEDGE]
    if persona:
        parts.append(persona)
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
        endpoint = session_settings.effective_endpoint(cfg, self.rec)
        effort = session_settings.wire_effort(session_settings.effective_effort(cfg, self.rec))
        skipped_notice = False
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
        persona = ""
        try:
            persona = persona_prompt(self.rec.get("id"), self.ctx.office() if self.ctx.office else None)
        except Exception:  # the Kantor must never break a turn
            persona = persona_prompt(self.rec.get("id"), None)
        if "@kantor" in user_text.lower() and self.ctx.office is not None:
            try:  # `@kantor` attaches the live Kantor state to this turn
                from neovarch.tools import office_summary
                persona += "\n\n# Kantor saat ini (diminta lewat @kantor)\n" + office_summary(self.ctx.office())
            except Exception:
                pass
        sys_prompt = system_prompt(cfg, self.ctx.cwd, user_text, persona)
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
                    reasoning_effort=effort,
                )
                if comp.reasoning_skipped:
                    effort = None  # the model rejected it; do not resend this turn
                    if not skipped_notice:
                        skipped_notice = True
                        self.emit("status", {"kind": "notice", "text": "Model ini tidak mendukung tingkat penalaran; "
                                                                        "dikirim tanpa pengaturan itu."})
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
            error = str(exc)
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
