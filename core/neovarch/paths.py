"""Where Neovarch keeps its data, and the guard that keeps it away from other agents' data.

Neovarch's home is ``$NEOVARCH_HOME`` or ``~/.neovarch`` (``%LOCALAPPDATA%\\neovarch``
on Windows). Everything the core writes lives below it::

    config.yaml   .env   SOUL.md
    sessions/<id>.json      memory/*.md      skills/<name>/SKILL.md
    kanban.json   logs/

A machine may also run Hermes Agent. Its data (``~/.hermes``,
``%LOCALAPPDATA%\\hermes``) and its ``hermes`` commands are off limits: the tools
refuse those paths, and :func:`install_guard` adds an interpreter-wide audit hook
so no code path in this process can open, list, change or delete them.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path


def neovarch_home() -> Path:
    explicit = os.environ.get("NEOVARCH_HOME", "").strip()
    if explicit:
        return Path(os.path.expanduser(explicit)).resolve()
    if sys.platform == "win32":
        base = os.environ.get("LOCALAPPDATA", "").strip() or str(Path.home() / "AppData" / "Local")
        return Path(base) / "neovarch"
    return Path.home() / ".neovarch"


def ensure_home() -> Path:
    home = neovarch_home()
    for sub in ("sessions", "memory", "skills", "logs"):
        (home / sub).mkdir(parents=True, exist_ok=True)
    return home


# ---------------------------------------------------------------- guard -----

def _foreign_roots() -> tuple[list[str], list[str]]:
    home = os.path.expanduser("~")
    dirs = [os.path.join(home, ".hermes")]
    if sys.platform == "win32":
        dirs.append(os.path.join(os.environ.get("LOCALAPPDATA") or os.path.join(home, "AppData", "Local"), "hermes"))
    state = os.environ.get("XDG_STATE_HOME") or os.path.join(home, ".local", "state")
    dirs.append(os.path.join(state, "hermes"))
    bin_dir = os.path.join(home, ".local", "bin")
    files = [os.path.join(bin_dir, n) for n in ("hermes", "hermes-acp", "hermes-agent")]
    norm = lambda p: os.path.normcase(os.path.normpath(p))  # noqa: E731
    return [norm(d) for d in dirs], [norm(f) for f in files]


_DIRS, _FILES = _foreign_roots()


def is_foreign_path(path) -> bool:
    """True when ``path`` belongs to a foreign agent install (never ours)."""
    try:
        raw = os.fsdecode(path)
    except TypeError:
        return False
    if not raw:
        return False
    p = os.path.normcase(os.path.normpath(os.path.abspath(os.path.expanduser(raw))))
    candidates = {p}
    try:
        candidates.add(os.path.normcase(os.path.realpath(p)))
    except (OSError, ValueError):
        pass
    for c in candidates:
        if c in _FILES or any(c == d or c.startswith(d + os.sep) for d in _DIRS):
            return True
    return False


class ForeignPathError(PermissionError):
    pass


def check_path(path) -> None:
    if is_foreign_path(path):
        raise ForeignPathError(f"{path} belongs to a Hermes Agent install; Neovarch does not touch it")


_PATH_EVENTS = {
    "open", "os.listdir", "os.scandir", "os.remove", "os.rmdir", "os.mkdir", "os.rename",
    "os.chmod", "os.chown", "os.truncate", "os.utime", "os.link", "os.symlink",
    "shutil.rmtree", "shutil.copyfile", "shutil.copytree", "shutil.move", "glob.glob",
}
_GUARDED = False


def _audit(event: str, args) -> None:
    if event not in _PATH_EVENTS or not args:
        return
    for arg in args[:2]:
        if isinstance(arg, (str, bytes, os.PathLike)) and is_foreign_path(arg):
            raise ForeignPathError(f"[neovarch] refused {event} on {os.fsdecode(arg)}: it belongs to Hermes Agent")


def install_guard() -> None:
    """Refuse every file operation on foreign paths for the rest of this process."""
    global _GUARDED
    if _GUARDED:
        return
    _GUARDED = True
    os.environ["NEOVARCH_CORE"] = "1"
    sys.addaudithook(_audit)
