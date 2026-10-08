"""The agent's tools: shell, files, web fetch, memory notes and skills.

Each tool is an async function ``(args, ctx) -> str``. Dangerous shell commands
go through ``ctx.approve`` first (the CLI asks on the terminal, the gateway sends
an ``approval`` request to the desktop/phone).
"""

from __future__ import annotations

import asyncio
import html
import os
import re
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Awaitable, Callable

import aiohttp

from neovarch.paths import ForeignPathError, check_path, neovarch_home

MAX_OUTPUT = 20_000

ApproveFn = Callable[[str, str, str], Awaitable[str]]


@dataclass
class ToolContext:
    cwd: Path
    approve: ApproveFn
    approvals_mode: str = "ask"            # ask | off
    session_allow: set[str] = field(default_factory=set)


DANGEROUS = [
    (r"\brm\s+(-[a-zA-Z]*[rf][a-zA-Z]*\s+)+", "deletes files recursively/forcibly"),
    (r"\bsudo\b|\bdoas\b|\bsu\s+-", "runs as another user (root)"),
    (r"\bmkfs(\.\w+)?\b|\bfdisk\b|\bparted\b|\bwipefs\b", "formats or partitions a disk"),
    (r"\bdd\s+.*\bof=", "writes raw data with dd"),
    (r">\s*/dev/(sd|nvme|hd|disk)", "writes to a block device"),
    (r"\b(shutdown|reboot|halt|poweroff)\b", "shuts down or restarts the machine"),
    (r"\bchmod\s+(-R\s+)?[0-7]*7[0-7]*\s+/|\bchown\s+-R\b", "changes permissions/ownership broadly"),
    (r"\bgit\s+(push\s+.*(--force|-f)\b|reset\s+--hard|clean\s+-[a-z]*f)", "rewrites or discards git history/work"),
    (r"(curl|wget)[^|]*\|\s*(sh|bash|zsh|python)", "pipes a download into a shell"),
    (r"\bkill(all)?\s+-9\b|\bpkill\b", "force-kills processes"),
    (r":\(\)\s*\{\s*:\|:&\s*\};:", "fork bomb"),
    (r"\b(drop\s+table|drop\s+database|truncate\s+table)\b", "destroys database data"),
]


def danger_reason(command: str) -> str | None:
    if re.search(r"(^|[\s'\"=:])(~|\$HOME|\$\{HOME\}|/home/[^/\s]+|/root)?/\.hermes(/|\s|$|['\"])"
                 r"|(^|[;&|(]\s*|\bxargs\s+)hermes(-acp|-agent)?(\s|$)", command):
        return "touches a Hermes Agent install (Neovarch never does)"
    for pattern, reason in DANGEROUS:
        if re.search(pattern, command, re.IGNORECASE):
            return reason
    return None


def _clip(text: str) -> str:
    if len(text) <= MAX_OUTPUT:
        return text
    half = MAX_OUTPUT // 2
    return text[:half] + f"\n… [{len(text) - MAX_OUTPUT} characters omitted] …\n" + text[-half:]


def _resolve(ctx: ToolContext, raw: str) -> Path:
    if not raw:
        raise ValueError("path is required")
    p = Path(os.path.expanduser(raw))
    if not p.is_absolute():
        p = ctx.cwd / p
    p = p.resolve()
    check_path(p)
    return p


# ------------------------------------------------------------------ tools -----

async def tool_shell(args: dict, ctx: ToolContext) -> str:
    command = str(args.get("command") or "").strip()
    if not command:
        return "error: command is required"
    timeout = min(float(args.get("timeout") or 120), 1800)
    reason = danger_reason(command)
    if reason and "hermes" in reason.lower():
        return f"refused: this command {reason}."
    if reason and ctx.approvals_mode != "off" and command not in ctx.session_allow:
        choice = await ctx.approve(command, f"This command {reason}.", "shell")
        if choice in ("deny", "", None):
            return "denied: the user did not approve this command."
        if choice in ("session", "always"):
            ctx.session_allow.add(command)
    workdir = _resolve(ctx, args["workdir"]) if args.get("workdir") else ctx.cwd
    started = time.monotonic()
    proc = await asyncio.create_subprocess_shell(
        command, cwd=str(workdir), stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT,
        env={**os.environ, "NEOVARCH_CORE": "1"}, start_new_session=True,
    )
    try:
        out, _ = await asyncio.wait_for(proc.communicate(), timeout=timeout)
    except asyncio.TimeoutError:
        try:
            proc.kill()
        except ProcessLookupError:
            pass
        return f"error: timed out after {timeout:.0f}s"
    text = out.decode("utf-8", "replace")
    return _clip(f"exit code {proc.returncode} ({time.monotonic() - started:.1f}s)\n{text}")


async def tool_read_file(args: dict, ctx: ToolContext) -> str:
    p = _resolve(ctx, str(args.get("path") or ""))
    if p.is_dir():
        entries = sorted(e.name + ("/" if e.is_dir() else "") for e in p.iterdir())
        return _clip("\n".join(entries) or "(empty directory)")
    text = p.read_text(encoding="utf-8", errors="replace")
    lines = text.splitlines()
    start = max(int(args.get("offset") or 1), 1)
    limit = int(args.get("limit") or 2000)
    chunk = lines[start - 1:start - 1 + limit]
    numbered = "\n".join(f"{i:>6}\t{line}" for i, line in enumerate(chunk, start))
    more = f"\n… {len(lines) - (start - 1 + len(chunk))} more lines" if start - 1 + len(chunk) < len(lines) else ""
    return _clip(numbered + more)


async def tool_write_file(args: dict, ctx: ToolContext) -> str:
    p = _resolve(ctx, str(args.get("path") or ""))
    content = str(args.get("content") or "")
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content, encoding="utf-8")
    return f"wrote {len(content)} characters to {p}"


async def tool_edit_file(args: dict, ctx: ToolContext) -> str:
    p = _resolve(ctx, str(args.get("path") or ""))
    old = str(args.get("old_text") or "")
    new = str(args.get("new_text") or "")
    if not old:
        return "error: old_text is required"
    text = p.read_text(encoding="utf-8")
    count = text.count(old)
    if count == 0:
        return "error: old_text was not found in the file"
    if count > 1 and not args.get("replace_all"):
        return f"error: old_text occurs {count} times; add more context or set replace_all"
    p.write_text(text.replace(old, new) if args.get("replace_all") else text.replace(old, new, 1), encoding="utf-8")
    return f"edited {p} ({count if args.get('replace_all') else 1} replacement(s))"


def _html_to_text(raw: str) -> str:
    raw = re.sub(r"(?is)<(script|style|noscript)[^>]*>.*?</\1>", " ", raw)
    raw = re.sub(r"(?i)<br\s*/?>|</(p|div|li|h[1-6]|tr)>", "\n", raw)
    raw = re.sub(r"<[^>]+>", " ", raw)
    raw = html.unescape(raw)
    raw = re.sub(r"[ \t\r\f\v]+", " ", raw)
    return re.sub(r"\n\s*\n+", "\n\n", raw).strip()


async def tool_web_fetch(args: dict, ctx: ToolContext) -> str:
    url = str(args.get("url") or "")
    if not re.match(r"^https?://", url):
        return "error: url must start with http:// or https://"
    async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=45)) as s:
        async with s.get(url, headers={"User-Agent": "NeovarchAgent/0.1 (+https://github.com/Maftuuh1922/neovrach_Agent)"}) as r:
            body = await r.text(errors="replace")
            ctype = r.headers.get("Content-Type", "")
            text = _html_to_text(body) if "html" in ctype else body
            return _clip(f"HTTP {r.status} {ctype}\n{text}")


async def tool_memory(args: dict, ctx: ToolContext) -> str:
    """Save or read long-term memory notes (markdown files in ~/.neovarch/memory)."""
    mem = neovarch_home() / "memory"
    mem.mkdir(parents=True, exist_ok=True)
    action = str(args.get("action") or "list")
    name = re.sub(r"[^a-zA-Z0-9_.-]+", "-", str(args.get("name") or "notes")).strip("-") or "notes"
    target = mem / (name if name.endswith(".md") else name + ".md")
    if action == "list":
        return "\n".join(sorted(p.name for p in mem.glob("*.md"))) or "(no memory notes yet)"
    if action == "read":
        return target.read_text(encoding="utf-8") if target.exists() else f"(no note named {target.name})"
    if action == "append":
        with target.open("a", encoding="utf-8") as fh:
            fh.write(str(args.get("content") or "").rstrip() + "\n")
        return f"appended to memory/{target.name}"
    if action == "write":
        target.write_text(str(args.get("content") or ""), encoding="utf-8")
        return f"wrote memory/{target.name}"
    return "error: action must be list, read, append or write"


async def tool_skill(args: dict, ctx: ToolContext) -> str:
    """List or read skills (folders with SKILL.md in ~/.neovarch/skills)."""
    root = neovarch_home() / "skills"
    root.mkdir(parents=True, exist_ok=True)
    name = str(args.get("name") or "")
    if not name:
        return "\n".join(f"{s['name']}: {s['description']}" for s in list_skills()) or "(no skills installed)"
    path = root / re.sub(r"[^a-zA-Z0-9_.-]+", "-", name) / "SKILL.md"
    return path.read_text(encoding="utf-8") if path.exists() else f"(no skill named {name})"


def list_skills() -> list[dict[str, str]]:
    root = neovarch_home() / "skills"
    out = []
    if not root.exists():
        return out
    for skill_md in sorted(root.glob("*/SKILL.md")):
        text = skill_md.read_text(encoding="utf-8", errors="replace")
        desc = ""
        m = re.search(r"(?m)^description:\s*(.+)$", text)
        if m:
            desc = m.group(1).strip()
        else:
            body = [ln for ln in text.splitlines() if ln.strip() and not ln.startswith(("---", "#", "name:"))]
            desc = body[0][:160] if body else ""
        out.append({"name": skill_md.parent.name, "description": desc, "path": str(skill_md)})
    return out


TOOLS: dict[str, tuple[Callable[[dict, ToolContext], Awaitable[str]], dict]] = {
    "shell": (tool_shell, {
        "description": "Run a shell command on the user's computer and return its output. Dangerous commands ask the user first.",
        "parameters": {"type": "object", "properties": {
            "command": {"type": "string"}, "workdir": {"type": "string"},
            "timeout": {"type": "number", "description": "seconds, default 120"}}, "required": ["command"]}}),
    "read_file": (tool_read_file, {
        "description": "Read a text file (with line numbers) or list a directory.",
        "parameters": {"type": "object", "properties": {
            "path": {"type": "string"}, "offset": {"type": "integer"}, "limit": {"type": "integer"}}, "required": ["path"]}}),
    "write_file": (tool_write_file, {
        "description": "Create or overwrite a text file.",
        "parameters": {"type": "object", "properties": {
            "path": {"type": "string"}, "content": {"type": "string"}}, "required": ["path", "content"]}}),
    "edit_file": (tool_edit_file, {
        "description": "Replace exact text in a file (old_text must be unique unless replace_all).",
        "parameters": {"type": "object", "properties": {
            "path": {"type": "string"}, "old_text": {"type": "string"}, "new_text": {"type": "string"},
            "replace_all": {"type": "boolean"}}, "required": ["path", "old_text", "new_text"]}}),
    "web_fetch": (tool_web_fetch, {
        "description": "Fetch a web page or API URL and return its text.",
        "parameters": {"type": "object", "properties": {"url": {"type": "string"}}, "required": ["url"]}}),
    "memory": (tool_memory, {
        "description": "Long-term memory notes. action: list | read | append | write; name: note name.",
        "parameters": {"type": "object", "properties": {
            "action": {"type": "string", "enum": ["list", "read", "append", "write"]},
            "name": {"type": "string"}, "content": {"type": "string"}}, "required": ["action"]}}),
    "skill": (tool_skill, {
        "description": "List installed skills (no name) or read one skill's instructions (name).",
        "parameters": {"type": "object", "properties": {"name": {"type": "string"}}}}),
}


def tool_schemas() -> list[dict[str, Any]]:
    return [{"type": "function", "function": {"name": n, **spec}} for n, (_, spec) in TOOLS.items()]


async def run_tool(name: str, args: dict, ctx: ToolContext) -> str:
    entry = TOOLS.get(name)
    if not entry:
        return f"error: unknown tool {name}"
    try:
        return await entry[0](args, ctx)
    except ForeignPathError as exc:
        return f"refused: {exc}"
    except FileNotFoundError as exc:
        return f"error: not found: {exc.filename or exc}"
    except Exception as exc:  # tools report errors to the model instead of crashing the turn
        return f"error: {type(exc).__name__}: {exc}"
