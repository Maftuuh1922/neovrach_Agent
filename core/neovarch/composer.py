"""What the desktop composer offers, for remote composers (the phone).

The desktop composer has a "+" menu (files, folder, images, paste image, URL,
prompt snippets), a model pill, a reasoning pill, "/" (commands + skills) and
"@" (file/folder/url/git references) completions. The phone remote reads the
same choices from one place:

    GET /api/composer/catalog              (also RPC ``composer.catalog``)
    GET /api/composer/complete?kind=path&q=src/ma[&session_id=…]
    GET /api/composer/complete?kind=slash&q=rev

and sends its picks with ``prompt.submit`` as optional, additive fields:

    skills:            ["code-review", …]   -> "/code-review " prefix, the same
                                               text form the desktop sends
    reasoning_effort:  "none|minimal|low|medium|high|xhigh"  (per turn)

Old clients send neither field and see no change. Old PCs do not have the
catalog route; the phone hides its menus then.
"""
from __future__ import annotations

import contextvars
import os
from pathlib import Path
from typing import Any

from neovarch import config as cfgmod
from neovarch.tools import list_skills

#: Bump when the catalog shape gains something a client must know about.
CATALOG_VERSION = 1

#: The desktop reasoning pill's levels (lib/reasoning-effort.ts), minus the
#: Hermes-only "max"/"ultra" steps that OpenAI-compatible routes clamp anyway.
REASONING_LEVELS = ["none", "minimal", "low", "medium", "high", "xhigh"]
REASONING_LABELS = {"none": "Mati", "minimal": "Minimal", "low": "Rendah", "medium": "Sedang",
                    "high": "Tinggi", "xhigh": "Sangat tinggi"}

#: Desktop "+" -> prompt snippets (i18n/neovarch-id.ts composer.snippets).
SNIPPETS = [
    {"id": "codeReview", "label": "Tinjau kode",
     "description": "Periksa perubahan ini untuk regresi, kasus tepi, dan tes yang kurang.",
     "text": "Tolong tinjau ini untuk bug, regresi, dan tes yang kurang."},
    {"id": "implementationPlan", "label": "Rencana implementasi",
     "description": "Susun pendekatan sebelum mengubah kode.",
     "text": "Tolong buat rencana implementasi singkat sebelum mengubah kode."},
    {"id": "explainThis", "label": "Jelaskan ini",
     "description": "Jelaskan cara kerja kode ini dan file pentingnya.",
     "text": "Tolong jelaskan cara kerja ini dan tunjukkan file-file pentingnya."},
]

#: Built-in slash commands (same list as ``commands.catalog``).
COMMANDS = [
    {"name": "new", "description": "Mulai percakapan baru"},
    {"name": "model", "description": "Ganti model"},
]

#: "@" starters the desktop offers that make sense from a phone.
MENTION_STARTERS = [
    {"text": "@url:", "display": "@url:", "meta": "Sebut tautan"},
    {"text": "@diff", "display": "@diff", "meta": "Perubahan git yang belum di-stage"},
    {"text": "@staged", "display": "@staged", "meta": "Perubahan git yang sudah di-stage"},
    {"text": "@git:", "display": "@git:", "meta": "Konteks git (mis. @git:log)"},
]

_turn_effort: contextvars.ContextVar[str | None] = contextvars.ContextVar("neovarch_turn_effort", default=None)


def normalize_effort(value: Any) -> str | None:
    v = str(value or "").strip().lower()
    return v if v in REASONING_LEVELS else None


def current_effort() -> str | None:
    """Reasoning effort for the request being built: this turn's pick from
    ``prompt.submit``, else the profile's ``agent.reasoning_effort`` (what the
    desktop reasoning pill writes), else None (provider default, not sent)."""
    turn = _turn_effort.get()
    if turn:
        return turn
    try:
        return normalize_effort(cfgmod.get_path(cfgmod.load_config(), "agent.reasoning_effort", ""))
    except Exception:  # config trouble must never break a turn
        return None


def set_turn_effort(value: str | None) -> contextvars.Token:
    return _turn_effort.set(value)


def reset_turn_effort(token: contextvars.Token) -> None:
    _turn_effort.reset(token)


def apply_skills(text: str, skills: Any, known: list[str] | None = None) -> str:
    """Prefix ``/skill`` references (the desktop's text form) for picked skills
    that are installed and not already in the text."""
    if not isinstance(skills, list) or not skills:
        return text
    names = {s["name"] for s in list_skills()} if known is None else set(known)
    words = set(text.split())
    picked: list[str] = []
    for raw in skills:
        name = str(raw or "").strip().lstrip("/")
        if name and name in names and f"/{name}" not in words and name not in picked:
            picked.append(name)
    if not picked:
        return text
    return " ".join(f"/{n}" for n in picked) + " " + text


def prepare_submit(p: dict) -> tuple[dict, str | None]:
    """The ``prompt.submit`` params with the composer picks folded in, and the
    per-turn reasoning effort (or None). Untouched when no pick is present."""
    effort = normalize_effort(p.get("reasoning_effort"))
    if not isinstance(p.get("skills"), list) or not p.get("skills"):
        return p, effort
    out = dict(p)
    out["text"] = apply_skills(str(p.get("text") or ""), p.get("skills"))
    return out, effort


def _models(cfg: dict) -> dict:
    from neovarch import providers
    try:
        opts = providers.model_options(cfg, False)
    except Exception:
        ep = cfgmod.resolve_endpoint(cfg)
        return {"model": ep["model"], "provider": ep["provider"], "providers": []}
    return {"model": opts.get("model") or "", "provider": opts.get("provider") or "",
            "providers": [{"slug": pv["slug"], "name": pv["name"], "models": list(pv.get("models") or []),
                           "is_current": bool(pv.get("is_current"))} for pv in opts.get("providers") or []]}


def catalog() -> dict:
    cfg = cfgmod.load_config()
    skills = [{"name": s["name"], "description": s.get("description") or ""} for s in list_skills()]
    effort = normalize_effort(cfgmod.get_path(cfg, "agent.reasoning_effort", "")) or "default"
    return {
        "version": CATALOG_VERSION,
        "skills": skills,
        "commands": COMMANDS,
        "snippets": SNIPPETS,
        "mentions": MENTION_STARTERS,
        "models": _models(cfg),
        "reasoning": {"supported": True, "levels": REASONING_LEVELS, "labels": REASONING_LABELS,
                      "default": effort},
        "profiles": [{"name": "default", "active": True}],
        "features": {"skills": True, "slash": True, "mentions": True, "url": True, "snippets": True,
                     "model_switch": True, "reasoning": True, "prompt_fields": ["skills", "reasoning_effort"]},
    }


def complete_path(query: str, cwd: Path, limit: int = 40) -> list[dict]:
    """``@`` file/folder completions relative to the session folder, in the
    desktop's wire form (``@file:rel`` / ``@folder:rel/``). Never leaves cwd."""
    q = (query or "").lstrip("@")
    for kind in ("file:", "folder:"):
        if q.startswith(kind):
            q = q[len(kind):]
    q = q.replace("\\", "/").lstrip("/")
    root = cwd.resolve()
    sub, _, stem = q.rpartition("/")
    folder = (root / sub).resolve() if sub else root
    try:
        folder.relative_to(root)
    except ValueError:
        return []
    try:
        entries = sorted(folder.iterdir(), key=lambda e: (not e.is_dir(), e.name.lower()))
    except OSError:
        return []
    out = []
    low = stem.lower()
    for e in entries:
        if e.name.startswith(".") and not stem.startswith("."):
            continue
        if low and low not in e.name.lower():
            continue
        rel = e.relative_to(root).as_posix()
        if e.is_dir():
            out.append({"text": f"@folder:{rel}/", "display": e.name + "/", "meta": "folder", "is_dir": True})
        else:
            out.append({"text": f"@file:{rel}", "display": e.name, "meta": sub or ".", "is_dir": False})
        if len(out) >= limit:
            break
    return out


def complete_slash(query: str) -> list[dict]:
    q = (query or "").lstrip("/").lower()
    items = [{"text": f"/{c['name']}", "name": c["name"], "description": c["description"], "kind": "command"}
             for c in COMMANDS]
    items += [{"text": f"/{s['name']}", "name": s["name"], "description": s.get("description") or "",
               "kind": "skill"} for s in list_skills()]
    if q:
        items = [i for i in items if q in i["name"].lower()]
    return items[:50]


def register(r, gw) -> None:
    """REST routes (auth is the app middleware's, like every /api route)."""
    from aiohttp import web

    async def catalog_get(_request):
        return web.json_response(catalog())

    async def complete_get(request):
        kind = request.query.get("kind", "path")
        q = request.query.get("q", "")
        if kind == "slash":
            return web.json_response({"items": complete_slash(q)})
        if kind != "path":
            return web.json_response({"detail": "kind must be path or slash"}, status=400)
        cwd = None
        sid = request.query.get("session_id")
        if sid and sid in gw.live:
            cwd = Path(gw.live[sid].ctx.cwd)
        if cwd is None:
            from neovarch.agent import default_cwd
            cwd = Path(os.path.expanduser(str(default_cwd())))
        return web.json_response({"items": complete_path(q, cwd), "cwd": str(cwd)})

    r.add_get("/api/composer/catalog", catalog_get)
    r.add_get("/api/composer/complete", complete_get)
