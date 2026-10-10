"""Quiet answers for desktop REST routes the Neovarch core has no feature behind.

The desktop renderer calls many ``/api/*`` routes.
Each one here returns the empty / "not available" shape the renderer accepts,
so no page shows "Failed to load" and no call ends in a 4xx/5xx. Routes with a
real implementation live in server.py and win (they are registered first).
"""

from __future__ import annotations

import os
import platform
import time
from pathlib import Path
from typing import Any, Callable

from aiohttp import web

from neovarch import __version__
from neovarch import config as cfgmod
from neovarch.paths import neovarch_home

NOT_AVAILABLE = "Belum tersedia di Neovarch core."


def _na(**extra) -> dict:
    return {"ok": False, "available": False, "message": NOT_AVAILABLE, "detail": NOT_AVAILABLE, **extra}


def _moa() -> dict:
    slot = {"provider": "", "model": "", "enabled": False}
    preset = {"aggregator": slot, "aggregator_temperature": 0.7, "degraded_reference_policy": "loud",
              "enabled": False, "reference_models": [], "reference_temperature": 0.7, "reference_timeout": None}
    return {"default_preset": "default", "active_preset": "default", "presets": {"default": preset}, **preset}


def _analytics(request: web.Request) -> dict:
    from neovarch.store import SessionStore
    try:
        days = max(1, int(request.query.get("days") or 30))
    except ValueError:
        days = 30
    since = time.time() - days * 86400
    sessions = [s for s in SessionStore().list(limit=100000) if float(s.get("last_active") or 0) >= since]
    by_model: dict[str, int] = {}
    for s in sessions:
        by_model[s.get("model") or "?"] = by_model.get(s.get("model") or "?", 0) + 1
    return {
        "by_model": [{"model": m, "sessions": n, "input_tokens": 0, "output_tokens": 0, "estimated_cost": 0,
                      "actual_cost": 0, "api_calls": 0} for m, n in by_model.items()],
        "daily": [], "period_days": days, "tools": [],
        "skills": {"summary": {"distinct_skills_used": 0, "total_skill_actions": 0, "total_skill_edits": 0,
                               "total_skill_loads": 0}, "top_skills": []},
        "totals": {"total_actual_cost": 0, "total_api_calls": None, "total_cache_read": None,
                   "total_estimated_cost": 0, "total_input": None, "total_output": None, "total_reasoning": None,
                   "total_sessions": len(sessions)},
    }


def _update_check(_request) -> dict:
    return {"install_method": "neovarch", "current_version": __version__, "behind": None,
            "update_available": False, "can_apply": False, "update_command": None,
            "message": "Pembaruan Neovarch dicek dari halaman rilis GitHub.", "commits": []}


def _system(_request) -> dict:
    return {"platform": platform.system().lower(), "python": platform.python_version(), "version": __version__,
            "home": str(neovarch_home()), "cwd": os.getcwd()}


# GET routes: path -> payload (callable(request) or a constant)
GETS: dict[str, Any] = {
    "/api/actions/{name}/status": lambda r: {"exit_code": None, "lines": [], "name": r.match_info["name"],
                                              "pid": None, "running": False},
    "/api/analytics/usage": _analytics,
    "/api/audio/elevenlabs/voices": {"available": False, "voices": []},
    "/api/audio/voice-config": {"ok": False, "available": False},
    "/api/cron/delivery-targets": [],
    "/api/cron/blueprints": {"blueprints": []},
    "/api/curator": {"enabled": False, "paused": False, "interval_hours": None, "last_run_at": None,
                     "min_idle_hours": None, "stale_after_days": None, "archive_after_days": None},
    "/api/git/gh-auth": {"available": False, "authenticated": False},
    "/api/hermes/update/check": _update_check,
    "/api/learning/graph": {"nodes": [], "edges": [], "clusters": [], "memory": [], "stats": {}},
    "/api/local-models/hardware": {"uma": False, "vram_total_bytes": 0, "vram_usable_bytes": 0, "ram_total_bytes": 0,
                                   "ram_available_bytes": 0, "vram_label": "", "gpu_name": None,
                                   "gpu_util_percent": None, "vram_used_bytes": None},
    "/api/local-models/catalog": {"models": [], "entries": []},
    "/api/local-models/search": {"results": [], "models": []},
    "/api/local-models/search/files": {"files": []},
    "/api/mcp/servers": {"servers": []},
    "/api/mcp/catalog": {"entries": [], "diagnostics": []},
    "/api/messaging/platforms": {"platforms": []},
    "/api/model/moa": lambda r: _moa(),
    "/api/pairing": {"approved": [], "pending": []},
    "/api/profiles/projects/tree": {"projects": [], "active_id": None, "scoped_session_ids": []},
    "/api/skills/hub/sources": {"sources": [], "index_available": False, "featured": [], "installed": {}},
    "/api/skills/hub/search": {"results": [], "source_counts": {}, "timed_out": [], "installed": {}},
    "/api/skills/hub/official": {"results": [], "skills": []},
    "/api/system": _system,
    "/api/tools/computer-use/status": {"platform": platform.system().lower(), "platform_supported": False,
                                       "installed": False, "version": None, "ready": None, "can_grant": False,
                                       "checks": [], "accessibility": None, "screen_recording": None,
                                       "screen_recording_capturable": None, "source": None, "error": None},
    "/api/tools/toolsets/{name}/config": lambda r: {"name": r.match_info["name"], "has_category": False,
                                                    "providers": [], "active_provider": None},
    "/api/tools/toolsets/{name}/models": lambda r: {"name": r.match_info["name"], "has_models": False,
                                                    "models": [], "current": None, "default": None},
    "/api/webhooks": {"base_url": "", "enabled": False, "subscriptions": []},
    "/api/providers/oauth": {"providers": []},
    "/api/providers/oauth/{pid}/poll/{sid}": lambda r: {"session_id": r.match_info["sid"], "status": "error",
                                                        "error_message": "Login OAuth tidak didukung di Neovarch core. "
                                                        "Pakai API key atau endpoint kustom."},
    "/api/memory/providers/{name}/config": lambda r: {"docs_url": "", "fields": [], "label": r.match_info["name"],
                                                      "name": r.match_info["name"]},
    "/api/memory/providers/{name}/oauth/status": {"status": "unsupported", "connected": False, "ok": False},
    "/api/agents": {"agents": [], "items": []},
    "/api/plugins": {"plugins": [], "items": []},
    "/api/models": lambda r: _models(),
}


def _models() -> dict:
    from neovarch import providers
    opts = providers.model_options(cfgmod.load_config())
    return {"models": [{"id": m, "provider": p["slug"]} for p in opts["providers"] for m in p.get("models") or []],
            "data": [{"id": m, "object": "model", "owned_by": p["slug"]}
                     for p in opts["providers"] for m in p.get("models") or []]}


# Mutations the core cannot perform: answer clearly, never 404/500.
MUTATIONS: dict[str, dict] = {
    "/api/providers/oauth/{pid}/start": {"ok": False, "flow": "external", "session_id": "",
                                         "message": "Login OAuth tidak didukung di Neovarch core. Pakai API key atau endpoint kustom."},
    "/api/providers/oauth/{pid}/submit": {"ok": False, "message": "Login OAuth tidak didukung di Neovarch core."},
    "/api/providers/oauth/{pid}": {"ok": True, "provider": ""},
    "/api/providers/oauth/sessions/{sid}": {"ok": True},
    "/api/profiles/sessions/pull-requests": {"pull_requests": {}, "scanned": []},
    "/api/curator/paused": {"ok": True, "paused": False},
}


def install(r: web.UrlDispatcher, log: Callable[[str, str], None]) -> None:
    """Register every quiet route not already served by a real handler."""
    taken = {(res.canonical, route.method) for res in r.resources() for route in res}

    def has(path: str, method: str) -> bool:
        return (path, method) in taken or (path, "*") in taken

    for path, payload in GETS.items():
        if has(path, "GET"):
            continue

        async def get(request: web.Request, payload=payload):
            data = payload(request) if callable(payload) else payload
            return web.json_response(data)
        r.add_get(path, get)

    for path, payload in MUTATIONS.items():
        async def mut(request: web.Request, payload=payload):
            return web.json_response(payload)
        for method in ("POST", "PUT", "DELETE", "PATCH"):
            if not has(path, method):
                r.add_route(method, path, mut)

    async def fallback(request: web.Request):
        log("http", f"{request.method} {request.path} (quiet fallback)")
        if request.method == "GET":
            return web.json_response({**_na(), "items": [], "results": []})
        return web.json_response({**_na(), "name": request.path.rsplit("/", 1)[-1], "pid": 0})

    r.add_route("*", "/api/{tail:.+}", fallback)


def home_path() -> Path:
    return neovarch_home()
