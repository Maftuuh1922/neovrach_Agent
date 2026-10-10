"""Per-session model and reasoning-effort choices from the desktop composer.

The desktop's model picker and reasoning selector send ``config.set`` with
``key=model`` (value ``"<model> --provider <slug> [--session]"``) and
``key=reasoning`` (value an effort level or a display word). Writing those
values verbatim into config.yaml replaced the whole ``model:`` mapping with a
string (the agent then had no endpoint) and left a dead top-level
``reasoning:`` key. This module parses them, keeps session-only choices on the
session record, and maps the effort onto the provider request.
"""

from __future__ import annotations

import copy
import shlex
from typing import Any

from neovarch import config as cfgmod

# Levels the desktop can send, in order. ``none`` turns reasoning off.
REASONING_LEVELS = ("none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra")
DISPLAY_WORDS = {"show": True, "full": True, "hide": False, "clamp": True}

# What OpenAI-compatible providers accept for ``reasoning_effort``.
_WIRE = {"minimal": "minimal", "low": "low", "medium": "medium", "high": "high",
         "xhigh": "high", "max": "high", "ultra": "high"}


def normalize_effort(value: Any) -> str | None:
    level = str(value or "").strip().lower()
    if level in ("off", "disabled", "false", "0"):
        level = "none"
    return level if level in REASONING_LEVELS else None


def wire_effort(level: str | None) -> str | None:
    """The ``reasoning_effort`` value to send, or None to omit the parameter."""
    return _WIRE.get(normalize_effort(level) or "")


def parse_model_value(value: Any) -> tuple[str, str, bool]:
    """``"m --provider p --session"`` -> (model, provider, session_only)."""
    try:
        parts = shlex.split(str(value or ""))
    except ValueError:
        parts = str(value or "").split()
    model: list[str] = []
    provider = ""
    session_only = False
    it = iter(parts)
    for part in it:
        if part == "--provider":
            provider = next(it, "")
        elif part.startswith("--provider="):
            provider = part.split("=", 1)[1]
        elif part in ("--session", "-s"):
            session_only = True
        elif part in ("--global", "-g"):
            session_only = False
        else:
            model.append(part)
    return " ".join(model).strip(), provider.strip(), session_only


def repair_config(cfg: dict) -> bool:
    """Undo shapes older cores wrote from the composer. Returns True when changed."""
    changed = False
    model = cfg.get("model")
    if model is not None and not isinstance(model, dict):
        name, provider, _ = parse_model_value(model)
        cfg["model"] = {"default": name, "provider": provider, "base_url": "", "context_length": 128000}
        changed = True
    if "reasoning" in cfg and not isinstance(cfg.get("reasoning"), dict):
        level = normalize_effort(cfg.pop("reasoning"))
        if level and not cfgmod.get_path(cfg, "agent.reasoning_effort"):
            cfgmod.set_path(cfg, "agent.reasoning_effort", level)
        changed = True
    effort = cfgmod.get_path(cfg, "agent.reasoning_effort")
    if effort not in (None, "") and normalize_effort(effort) is None:
        cfgmod.set_path(cfg, "agent.reasoning_effort", "")
        changed = True
    return changed


def effective_endpoint(cfg: dict, rec: dict | None) -> dict[str, Any]:
    """The endpoint a session talks to: the config default, or its own pick."""
    override = (rec or {}).get("model_override") or {}
    if override.get("model") or override.get("provider"):
        from neovarch import providers
        scratch = copy.deepcopy(cfg)
        try:
            providers.set_model(scratch, {"model": override.get("model") or "",
                                          "provider": override.get("provider") or ""})
            return cfgmod.resolve_endpoint(scratch)
        except Exception:  # a provider removed since: fall back to the default
            pass
    return cfgmod.resolve_endpoint(cfg)


def effective_effort(cfg: dict, rec: dict | None) -> str:
    level = normalize_effort((rec or {}).get("reasoning_effort"))
    if level is None:
        level = normalize_effort(cfgmod.get_path(cfg, "agent.reasoning_effort"))
    return level or ""
