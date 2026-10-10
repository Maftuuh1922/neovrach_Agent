"""The core's own log files under ``~/.neovarch/logs`` and the ``/api/logs`` reader.

``agent.log`` gets everything at INFO and above (gateway start, turns, tool
calls, errors); ``errors.log`` only WARNING and above. Both rotate at 1 MB.
The desktop's Logs pane tails them through ``GET /api/logs``.
"""

from __future__ import annotations

import logging
import logging.handlers
from pathlib import Path
from typing import Any

from neovarch.paths import neovarch_home

LOGGER = "neovarch"
FILES = {"agent": "agent.log", "errors": "errors.log", "unhandled": "unhandled.log"}
LEVELS = ("DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL")
_FMT = "%(asctime)s %(levelname)s %(name)s: %(message)s"

log = logging.getLogger(LOGGER)


def log_dir() -> Path:
    d = neovarch_home() / "logs"
    d.mkdir(parents=True, exist_ok=True)
    return d


def setup() -> logging.Logger:
    """Attach the rotating file handlers once (idempotent)."""
    if getattr(log, "_neovarch_files", False):
        return log
    log.setLevel(logging.INFO)
    for name, level in (("agent", logging.INFO), ("errors", logging.WARNING)):
        h = logging.handlers.RotatingFileHandler(log_dir() / FILES[name], maxBytes=1_000_000, backupCount=2,
                                                 encoding="utf-8")
        h.setLevel(level)
        h.setFormatter(logging.Formatter(_FMT))
        log.addHandler(h)
    log.propagate = False
    log._neovarch_files = True  # type: ignore[attr-defined]
    return log


def _level_of(line: str) -> str:
    parts = line.split(" ", 3)
    return parts[2] if len(parts) > 2 and parts[2] in LEVELS else ""


def read(query: Any) -> dict[str, Any]:
    """``/api/logs``: file (agent|errors|unhandled), lines, level, component, search."""
    name = str(query.get("file") or "agent")
    path = log_dir() / FILES.get(name, FILES["agent"])
    try:
        n = max(1, min(int(query.get("lines") or 200), 2000))
    except (TypeError, ValueError):
        n = 200
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines() if path.exists() else []
    level = str(query.get("level") or "").upper()
    if level in LEVELS:
        floor = LEVELS.index(level)
        lines = [ln for ln in lines if _level_of(ln) and LEVELS.index(_level_of(ln)) >= floor]
    comp = str(query.get("component") or "").lower()
    if comp and comp != "all":
        lines = [ln for ln in lines if comp in ln.lower()]
    q = str(query.get("search") or "").lower()
    if q:
        lines = [ln for ln in lines if q in ln.lower()]
    return {"file": str(path), "name": name, "lines": lines[-n:], "available": sorted(FILES)}
