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
        "cwd": rec.get("cwd") or None,
        "ended_at": None,
        "is_active": False,
        "input_tokens": 0,
        "output_tokens": 0,
        "tool_call_count": sum(len(m.get("tool_calls") or []) for m in msgs if m.get("role") == "assistant"),
    }


class Kanban:
    """A small task board (kanban.json) that the phone remote shows."""

    STATUSES = ["triage", "todo", "ready", "running", "blocked", "done"]

    def __init__(self, path: Path | None = None):
        self.path = path or (neovarch_home() / "kanban.json")
        # Called with each event after it is on disk (the gateway pushes it live).
        self.on_event = None
        self._pending: list[dict] = []

    def _commit(self, data: dict) -> None:
        _atomic_write(self.path, data)
        pending, self._pending = self._pending, []
        if self.on_event:
            for ev in pending:
                try:
                    self.on_event(ev)
                except Exception:
                    pass

    def _load(self) -> dict:
        if self.path.exists():
            try:
                return json.loads(self.path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                pass
        return {"tasks": [], "next": 1}

    @staticmethod
    def _card(t: dict) -> dict:
        return {**t, "comment_count": len(t.get("comments") or []), "tenant": None,
                "link_counts": {"parents": 0, "children": 0}}

    def _event(self, data: dict, kind: str, task_id: str | None, payload: dict | None = None) -> None:
        events = data.setdefault("events", [])
        eid = int(data.get("event_seq", 0)) + 1
        data["event_seq"] = eid
        ev = {"id": eid, "kind": kind, "task_id": task_id, "payload": payload or {}, "created_at": time.time()}
        events.append(ev)
        self._pending.append(ev)
        del events[:-500]

    def events_since(self, since: int = 0) -> tuple[list[dict], int]:
        data = self._load()
        evs = [e for e in data.get("events", []) if int(e["id"]) > since]
        return evs, int(data.get("event_seq", 0))

    def board(self) -> dict:
        data = self._load()
        cards = [self._card(t) for t in data["tasks"]]
        columns = [{"name": s, "tasks": [t for t in cards if t["status"] == s]} for s in self.STATUSES]
        return {"columns": columns, "tasks": cards, "statuses": self.STATUSES, "tenants": [],
                "assignees": sorted({t["assignee"] for t in cards if t.get("assignee")}),
                "latest_event_id": int(data.get("event_seq", 0)), "now": time.time()}

    def detail(self, tid: str) -> dict | None:
        data = self._load()
        task = next((t for t in data["tasks"] if t["id"] == tid), None)
        if task is None:
            return None
        return {"task": self._card(task), "comments": task.get("comments") or [],
                "events": [e for e in data.get("events", []) if e.get("task_id") == tid],
                "attachments": [], "links": {"parents": [], "children": []}, "link_tasks": [], "runs": []}

    def delete(self, tid: str) -> bool:
        with _LOCK:
            data = self._load()
            keep = [t for t in data["tasks"] if t["id"] != tid]
            if len(keep) == len(data["tasks"]):
                return False
            data["tasks"] = keep
            self._event(data, "deleted", tid)
            self._commit(data)
            return True

    def create(self, title: str, body: str = "", assignee: str | None = None, priority: int | None = None) -> dict:
        with _LOCK:
            data = self._load()
            now = time.time()
            task = {"id": f"t{data['next']}", "title": title, "body": body, "assignee": assignee,
                    "priority": priority or 0, "status": "todo", "comments": [], "created_at": now, "updated_at": now}
            data["next"] += 1
            data["tasks"].append(task)
            self._event(data, "created", task["id"], {"title": title})
            self._commit(data)
            return task

    def update(self, tid: str, fields: dict) -> dict | None:
        with _LOCK:
            data = self._load()
            for task in data["tasks"]:
                if task["id"] == tid:
                    old = task.get("status")
                    for k in ("title", "body", "assignee", "priority", "status"):
                        if k in fields:
                            task[k] = fields[k]
                    task["updated_at"] = time.time()
                    if old != task.get("status"):
                        self._event(data, "completed" if task.get("status") == "done" else "status", tid,
                                    {"from": old, "to": task.get("status")})
                    else:
                        self._event(data, "updated", tid)
                    self._commit(data)
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
                    self._event(data, "commented", tid)
                    self._commit(data)
                    return c
        return None
