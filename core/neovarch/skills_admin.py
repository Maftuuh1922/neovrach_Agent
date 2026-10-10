"""Skill and memory management behind the desktop's Skills tab and memory card.

* toggle: ``skills.disabled`` in config.yaml; a disabled skill stays on disk
  but is left out of the agent's prompt and its ``skill`` tool listing.
* node read / edit / archive: a skill's SKILL.md by name. Archive moves the
  folder to ``skills/.archive/<name>-<timestamp>`` (restorable by moving it
  back); the built-in skill is not re-installed while an archived copy exists.
* memory status / reset: the notes the ``memory`` tool keeps in
  ``~/.neovarch/memory`` (``USER.md`` counts as the user profile).
"""

from __future__ import annotations

import re
import shutil
import time
from pathlib import Path
from typing import Any

from neovarch import config as cfgmod
from neovarch.paths import neovarch_home


def skills_root() -> Path:
    return neovarch_home() / "skills"


def _safe(name: str) -> str:
    return re.sub(r"[^a-zA-Z0-9_.-]+", "-", str(name or "")).strip(".-")


def disabled() -> set[str]:
    raw = cfgmod.get_path(cfgmod.load_config(), "skills.disabled", []) or []
    return {str(x) for x in raw} if isinstance(raw, list) else set()


def set_enabled(name: str, enabled: bool) -> dict[str, Any]:
    name = _safe(name)
    if not name or not (skills_root() / name / "SKILL.md").exists():
        return {"ok": False, "name": name, "enabled": enabled, "message": f"Skill '{name}' tidak ditemukan."}
    cfg = cfgmod.load_config()
    off = disabled()
    off.discard(name) if enabled else off.add(name)
    cfgmod.set_path(cfg, "skills.disabled", sorted(off))
    cfgmod.save_config(cfg)
    return {"ok": True, "name": name, "enabled": enabled}


def node(name: str) -> dict[str, Any]:
    path = skills_root() / _safe(name) / "SKILL.md"
    if not path.exists():
        return {"ok": False, "kind": "skill", "label": name, "content": "", "message": "Skill tidak ditemukan."}
    return {"ok": True, "id": _safe(name), "kind": "skill", "label": _safe(name),
            "content": path.read_text(encoding="utf-8", errors="replace")}


def edit(name: str, content: str) -> dict[str, Any]:
    path = skills_root() / _safe(name) / "SKILL.md"
    if not _safe(name) or not path.exists():
        return {"ok": False, "message": "Skill tidak ditemukan."}
    path.write_text(str(content or ""), encoding="utf-8")
    return {"ok": True, "message": f"Skill '{_safe(name)}' disimpan."}


def archive(name: str) -> dict[str, Any]:
    name = _safe(name)
    src = skills_root() / name
    if not name or not (src / "SKILL.md").exists():
        return {"ok": False, "message": "Skill tidak ditemukan."}
    dest = skills_root() / ".archive" / f"{name}-{time.strftime('%Y%m%d-%H%M%S')}"
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(src), str(dest))
    return {"ok": True, "message": f"Skill '{name}' diarsipkan ke {dest}."}


def archived(name: str) -> bool:
    arch = skills_root() / ".archive"
    return arch.exists() and any(arch.glob(f"{_safe(name)}-*"))


# ------------------------------------------------------------------ memory ----

def memory_dir() -> Path:
    return neovarch_home() / "memory"


def memory_status() -> dict[str, Any]:
    notes = sorted(p.name for p in memory_dir().glob("*.md")) if memory_dir().exists() else []
    user = [n for n in notes if n.lower() == "user.md"]
    return {"active": "builtin", "providers": [],
            "builtin_files": {"memory": len(notes) - len(user), "user": len(user)},
            "notes": notes, "path": str(memory_dir())}


def memory_reset(target: str) -> dict[str, Any]:
    target = target if target in ("all", "memory", "user") else "all"
    deleted: list[str] = []
    for p in sorted(memory_dir().glob("*.md")) if memory_dir().exists() else []:
        is_user = p.name.lower() == "user.md"
        if target == "all" or (target == "user") == is_user:
            p.unlink()
            deleted.append(p.name)
    return {"ok": True, "deleted": deleted}
