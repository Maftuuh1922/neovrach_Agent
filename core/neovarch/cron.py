"""Scheduled jobs (cron) for the Neovarch core.

Jobs live in ``<NEOVARCH_HOME>/cron.json``. A job is a prompt the agent runs in
a fresh session on a schedule. Accepted schedules:

* an interval: ``30m``, ``every 2h``, ``1d``, ``tiap 45m`` (s/m/h/d units)
* a daily time: ``daily 08:00`` / ``harian 08:00``
* a 5-field cron expression: ``0 9 * * 1-5``
* a one-shot local time: ``2026-10-09T08:00`` (ISO 8601)

The scheduler is a single asyncio task owned by the gateway; it wakes every few
seconds and starts every due job, at most one run per job at a time.
"""

from __future__ import annotations

import asyncio
import datetime as dt
import re
import secrets
import threading
import time
from pathlib import Path
from typing import Any, Awaitable, Callable

from neovarch.paths import neovarch_home
from neovarch.store import _atomic_write

_LOCK = threading.RLock()
_UNITS = {"s": 1, "m": 60, "h": 3600, "d": 86400}
_INTERVAL = re.compile(r"^(?:every|tiap|setiap)?\s*(\d+)\s*([smhd])$", re.I)
_DAILY = re.compile(r"^(?:daily|harian|setiap hari)\s+(\d{1,2}):(\d{2})$", re.I)
_RANGES = [(0, 59), (0, 23), (1, 31), (1, 12), (0, 6)]


class ScheduleError(ValueError):
    pass


def _field(spec: str, lo: int, hi: int, dow: bool = False) -> set[int]:
    out: set[int] = set()
    for part in spec.split(","):
        step = 1
        if "/" in part:
            part, s = part.split("/", 1)
            if not s.isdigit() or int(s) < 1:
                raise ScheduleError(f"langkah tidak valid: {s}")
            step = int(s)
        if part in ("*", ""):
            a, b = lo, hi
        elif "-" in part:
            x, y = part.split("-", 1)
            if not (x.isdigit() and y.isdigit()):
                raise ScheduleError(f"rentang tidak valid: {part}")
            a, b = int(x), int(y)
        elif part.isdigit():
            a = b = int(part)
            if step > 1:
                b = hi
        else:
            raise ScheduleError(f"nilai tidak valid: {part}")
        top = 7 if dow else hi  # cron allows 7 for Sunday
        if a < lo or b > top or a > b:
            raise ScheduleError(f"di luar rentang {lo}-{hi}: {part}")
        out.update(0 if (dow and v == 7) else v for v in range(a, b + 1, step))
    return out


def parse_schedule(text: str) -> dict:
    """Normalise a schedule string; raises ScheduleError with an Indonesian message."""
    s = " ".join(str(text or "").strip().split())
    if not s:
        raise ScheduleError("jadwal kosong")
    m = _INTERVAL.match(s)
    if m:
        secs = int(m.group(1)) * _UNITS[m.group(2).lower()]
        if secs < 60:
            raise ScheduleError("interval minimal 1 menit")
        return {"kind": "interval", "seconds": secs, "expr": s, "display": f"setiap {m.group(1)}{m.group(2).lower()}"}
    m = _DAILY.match(s)
    if m:
        hh, mm = int(m.group(1)), int(m.group(2))
        if hh > 23 or mm > 59:
            raise ScheduleError("jam tidak valid")
        expr = f"{mm} {hh} * * *"
        return {"kind": "cron", "expr": expr, "display": f"setiap hari {hh:02d}:{mm:02d}"}
    parts = s.split(" ")
    if len(parts) == 5:
        for i, p in enumerate(parts):
            _field(p, *_RANGES[i], dow=(i == 4))
        return {"kind": "cron", "expr": s, "display": f"cron {s}"}
    try:
        when = dt.datetime.fromisoformat(s)
    except ValueError:
        raise ScheduleError(
            "format jadwal tidak dikenal (contoh: 30m, every 2h, daily 08:00, 0 9 * * 1-5, 2026-10-09T08:00)") from None
    if when.tzinfo is None:
        when = when.astimezone()
    return {"kind": "once", "at": when.timestamp(), "expr": s, "display": f"sekali {when.strftime('%Y-%m-%d %H:%M')}"}


def cron_next(expr: str, after: float) -> float | None:
    """Next local time strictly after ``after`` matching a 5-field expression."""
    f = expr.split()
    mins, hours, doms, months, dows = (_field(p, *_RANGES[i], dow=(i == 4)) for i, p in enumerate(f))
    dom_any, dow_any = f[2] == "*", f[4] == "*"
    t = dt.datetime.fromtimestamp(after).replace(second=0, microsecond=0) + dt.timedelta(minutes=1)
    limit = t + dt.timedelta(days=366 * 5)
    while t < limit:
        if t.month not in months:
            t = (t.replace(day=1, hour=0, minute=0) + dt.timedelta(days=32)).replace(day=1)
            continue
        dow = (t.weekday() + 1) % 7  # cron: 0 = Sunday
        day_ok = (t.day in doms) if dow_any else (dow in dows) if dom_any else (t.day in doms or dow in dows)
        if not day_ok:
            t = t.replace(hour=0, minute=0) + dt.timedelta(days=1)
            continue
        if t.hour not in hours:
            t = t.replace(minute=0) + dt.timedelta(hours=1)
            continue
        if t.minute not in mins:
            t += dt.timedelta(minutes=1)
            continue
        return t.timestamp()
    return None


def next_run(sched: dict, *, after: float, last_run: float | None) -> float | None:
    kind = sched.get("kind")
    if kind == "interval":
        base = last_run if last_run else after
        return base + sched["seconds"] if last_run else after + sched["seconds"]
    if kind == "cron":
        return cron_next(sched["expr"], after)
    if kind == "once":
        return None if last_run else sched["at"]
    return None


def _iso(ts: float | None) -> str | None:
    return dt.datetime.fromtimestamp(ts).astimezone().isoformat(timespec="seconds") if ts else None


class CronStore:
    def __init__(self, path: Path | None = None):
        self.path = path or (neovarch_home() / "cron.json")

    def _load(self) -> dict:
        import json
        try:
            data = json.loads(self.path.read_text(encoding="utf-8"))
            if isinstance(data, dict) and isinstance(data.get("jobs"), list):
                data.setdefault("runs", {})
                return data
        except (OSError, ValueError):
            pass
        return {"jobs": [], "runs": {}}

    def _save(self, data: dict) -> None:
        _atomic_write(self.path, data)

    @staticmethod
    def public(job: dict) -> dict:
        sched = job.get("schedule") or {}
        state = ("running" if job.get("running") else "completed" if job.get("completed")
                 else "paused" if not job.get("enabled") else "scheduled")
        return {"id": job["id"], "name": job.get("name") or "", "prompt": job.get("prompt") or "",
                "enabled": bool(job.get("enabled")), "schedule": {"kind": sched.get("kind"), "expr": sched.get("expr"),
                                                                  "display": sched.get("display")},
                "schedule_display": sched.get("display"), "next_run_at": _iso(job.get("next_run")),
                "last_run_at": _iso(job.get("last_run")), "last_error": job.get("last_error"),
                "last_session_id": job.get("last_session_id"), "state": state, "deliver": job.get("deliver") or "local",
                "model": job.get("model"), "provider": job.get("provider"), "repeat": job.get("repeat"),
                "run_count": int(job.get("run_count") or 0), "no_agent": False, "script": None,
                "created_at": _iso(job.get("created"))}

    def list(self) -> list[dict]:
        with _LOCK:
            return list(self._load()["jobs"])

    def get(self, jid: str) -> dict | None:
        return next((j for j in self.list() if j["id"] == jid), None)

    def create(self, body: dict, now: float | None = None) -> dict:
        prompt = str(body.get("prompt") or "").strip()
        if not prompt:
            raise ScheduleError("prompt wajib diisi")
        sched = parse_schedule(str(body.get("schedule") or ""))
        now = time.time() if now is None else now
        repeat = body.get("repeat")
        job = {"id": "job_" + secrets.token_hex(4), "name": str(body.get("name") or prompt[:40]), "prompt": prompt,
               "schedule": sched, "enabled": True, "created": now, "last_run": None, "last_error": None,
               "run_count": 0, "repeat": int(repeat) if isinstance(repeat, (int, float)) and repeat > 0 else None,
               "deliver": str(body.get("deliver") or "local"), "model": body.get("model") or None,
               "provider": body.get("provider") or None}
        job["next_run"] = next_run(sched, after=now, last_run=None)
        with _LOCK:
            data = self._load()
            data["jobs"].append(job)
            self._save(data)
        return job

    def update(self, jid: str, fields: dict, now: float | None = None) -> dict | None:
        now = time.time() if now is None else now
        with _LOCK:
            data = self._load()
            job = next((j for j in data["jobs"] if j["id"] == jid), None)
            if not job:
                return None
            if "schedule" in fields and fields["schedule"] is not None:
                job["schedule"] = parse_schedule(str(fields["schedule"]))
                job["completed"] = False
                job["next_run"] = next_run(job["schedule"], after=now, last_run=None)
            for k in ("name", "prompt", "deliver", "model", "provider"):
                if k in fields:
                    job[k] = fields[k]
            if "enabled" in fields:
                job["enabled"] = bool(fields["enabled"])
                if job["enabled"] and not job.get("next_run") and not job.get("completed"):
                    job["next_run"] = next_run(job["schedule"], after=now, last_run=None)
            for k, v in fields.items():
                if k.startswith("_"):
                    job[k[1:]] = v
            self._save(data)
            return job

    def delete(self, jid: str) -> bool:
        with _LOCK:
            data = self._load()
            n = len(data["jobs"])
            data["jobs"] = [j for j in data["jobs"] if j["id"] != jid]
            data["runs"].pop(jid, None)
            self._save(data)
            return len(data["jobs"]) != n

    def add_run(self, jid: str, sid: str) -> None:
        with _LOCK:
            data = self._load()
            runs = data["runs"].setdefault(jid, [])
            runs.insert(0, sid)
            del runs[50:]
            self._save(data)

    def runs(self, jid: str) -> list[str]:
        with _LOCK:
            return list(self._load()["runs"].get(jid, []))

    def due(self, now: float) -> list[dict]:
        return [j for j in self.list() if j.get("enabled") and not j.get("running")
                and j.get("next_run") and j["next_run"] <= now]


Runner = Callable[[dict], Awaitable[tuple[str, str | None]]]


class Scheduler:
    """Starts due jobs. ``runner(job)`` returns (session_id, error_or_None)."""

    def __init__(self, store: CronStore, runner: Runner, on_change: Callable[[], None] | None = None,
                 tick: float = 5.0):
        self.store, self.runner, self.on_change, self.tick = store, runner, on_change, tick
        self.task: asyncio.Task | None = None
        self.active: dict[str, asyncio.Task] = {}

    def start(self) -> None:
        if not self.task:
            # a crash or shutdown mid-run leaves "running" set; clear it on boot
            for j in self.store.list():
                if j.get("running"):
                    self.store.update(j["id"], {"_running": False})
            self.task = asyncio.create_task(self._loop())

    async def stop(self) -> None:
        if self.task:
            self.task.cancel()
            self.task = None

    async def _loop(self) -> None:
        while True:
            try:
                for job in self.store.due(time.time()):
                    self.run_now(job["id"])
            except Exception:  # never let one bad file stop the loop
                import traceback
                traceback.print_exc()
            await asyncio.sleep(self.tick)

    def run_now(self, jid: str) -> asyncio.Task | None:
        if jid in self.active:
            return self.active[jid]
        job = self.store.update(jid, {"_running": True})
        if not job:
            return None
        self._changed()
        t = asyncio.create_task(self._run(job))
        self.active[jid] = t
        return t

    async def _run(self, job: dict) -> None:
        started = time.time()
        sid, err = "", None
        try:
            sid, err = await self.runner(job)
        except Exception as exc:
            err = f"{type(exc).__name__}: {exc}"
        finally:
            self.active.pop(job["id"], None)
        if sid:
            self.store.add_run(job["id"], sid)
        cur = self.store.get(job["id"]) or job
        count = int(cur.get("run_count") or 0) + 1
        fields: dict[str, Any] = {"_running": False, "_last_run": started, "_last_error": err,
                                  "_last_session_id": sid or cur.get("last_session_id"), "_run_count": count}
        nxt = next_run(cur["schedule"], after=time.time(), last_run=started)
        done = nxt is None or (cur.get("repeat") and count >= cur["repeat"])
        fields["_next_run"] = None if done else nxt
        if done:
            fields["_completed"] = True
            fields["enabled"] = False
        self.store.update(job["id"], fields)
        self._changed()

    def _changed(self) -> None:
        if self.on_change:
            try:
                self.on_change()
            except Exception:
                pass
