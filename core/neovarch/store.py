"""Persistent state under the Neovarch home: sessions and the Kanban board."""

from __future__ import annotations

import json
import os
import secrets
import threading
import time
from pathlib import Path
from typing import Any

from neovarch.paths import neovarch_home

_LOCK = threading.RLock()


def _atomic_write(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + f".{os.getpid()}.tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
    os.replace(tmp, path)


def new_id() -> str:
    return time.strftime("%Y%m%d_%H%M%S") + "_" + secrets.token_hex(3)


class SessionStore:
    """One JSON file per conversation: sessions/<id>.json."""

    def __init__(self, root: Path | None = None):
        self.root = root or (neovarch_home() / "sessions")
        self.root.mkdir(parents=True, exist_ok=True)

    def path(self, sid: str) -> Path:
        safe = "".join(c for c in sid if c.isalnum() or c in "_-")
        return self.root / f"{safe}.json"

    def create(self, *, source: str = "cli", title: str = "", model: str = "", cwd: str = "") -> dict:
        now = time.time()
        rec = {"id": new_id(), "title": title, "source": source, "model": model, "cwd": cwd,
               "created_at": now, "updated_at": now, "messages": []}
        self.save(rec)
        return rec

    def save(self, rec: dict) -> None:
        rec["updated_at"] = time.time()
        with _LOCK:
            _atomic_write(self.path(rec["id"]), rec)

    def load(self, sid: str) -> dict | None:
        p = self.path(sid)
        if not p.exists():
            return None
        try:
            return json.loads(p.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return None

    def find(self, key: str) -> dict | None:
        """By id, else by exact title (newest first)."""
        rec = self.load(key)
        if rec:
            return rec
        for summary in self.list(limit=10_000):
            if summary["title"] == key:
                return self.load(summary["id"])
        return None

    def delete(self, sid: str) -> bool:
        p = self.path(sid)
        if p.exists():
            p.unlink()
            return True
        return False

    def list(self, limit: int = 50, offset: int = 0) -> list[dict]:
        items = []
        for p in self.root.glob("*.json"):
            try:
                rec = json.loads(p.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                continue
            items.append(summarize(rec))
        items.sort(key=lambda s: s["last_active"], reverse=True)
        return items[offset:offset + limit]


def visible_messages(rec: dict) -> list[dict]:
    return [m for m in rec.get("messages", []) if m.get("role") in ("user", "assistant", "tool")]


def summarize(rec: dict) -> dict:
    msgs = rec.get("messages", [])
    first_user = next((m.get("content") for m in msgs if m.get("role") == "user" and isinstance(m.get("content"), str)), "")
    last_text = next((m.get("content") for m in reversed(msgs) if m.get("role") in ("assistant", "user")
                      and isinstance(m.get("content"), str) and m.get("content")), "")
    title = rec.get("title") or (first_user.strip().splitlines()[0][:60] if first_user and first_user.strip() else "")
    return {
        "id": rec["id"],
        "title": title or None,
        "preview": (last_text or "")[:160],
        "message_count": sum(1 for m in msgs if m.get("role") in ("user", "assistant")),
        "last_active": rec.get("updated_at", rec.get("created_at", 0)),
        "started_at": rec.get("created_at", 0),
        "source": rec.get("source", "cli"),
        "model": rec.get("model", ""),
    }


class Kanban:
    """A small task board (kanban.json) that the phone remote shows."""

    STATUSES = ["triage", "todo", "ready", "running", "blocked", "done"]

    def __init__(self, path: Path | None = None):
        self.path = path or (neovarch_home() / "kanban.json")

    def _load(self) -> dict:
        if self.path.exists():
            try:
                return json.loads(self.path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                pass
        return {"tasks": [], "next": 1}

    def board(self) -> dict:
        data = self._load()
        columns = [{"name": s, "tasks": [t for t in data["tasks"] if t["status"] == s]} for s in self.STATUSES]
        return {"columns": columns, "tasks": data["tasks"], "statuses": self.STATUSES}

    def create(self, title: str, body: str = "", assignee: str | None = None, priority: int | None = None) -> dict:
        with _LOCK:
            data = self._load()
            now = time.time()
            task = {"id": f"t{data['next']}", "title": title, "body": body, "assignee": assignee,
                    "priority": priority or 0, "status": "todo", "comments": [], "created_at": now, "updated_at": now}
            data["next"] += 1
            data["tasks"].append(task)
            _atomic_write(self.path, data)
            return task

    def update(self, tid: str, fields: dict) -> dict | None:
        with _LOCK:
            data = self._load()
            for task in data["tasks"]:
                if task["id"] == tid:
                    for k in ("title", "body", "assignee", "priority", "status"):
                        if k in fields:
                            task[k] = fields[k]
                    task["updated_at"] = time.time()
                    _atomic_write(self.path, data)
                    return task
        return None

    def comment(self, tid: str, body: str, author: str = "user") -> dict | None:
        with _LOCK:
            data = self._load()
            for task in data["tasks"]:
                if task["id"] == tid:
                    c = {"id": secrets.token_hex(4), "body": body, "author": author, "created_at": time.time()}
                    task.setdefault("comments", []).append(c)
                    task["updated_at"] = time.time()
                    _atomic_write(self.path, data)
                    return c
        return None
