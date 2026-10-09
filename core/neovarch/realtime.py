"""Realtime event bus: one ordered stream of every gateway event, with resync.

Every event the gateway broadcasts (chat deltas, tool calls, approvals,
Office, Kanban, vault, cron, appearance) gets a monotonically increasing
``seq`` and lands in a bounded ring buffer. A client that drops its connection
reconnects and asks for everything after the last ``seq`` it saw:

* WebSocket ``/api/ws``: JSON-RPC ``events.replay {since, boot_id, session_ids}``
  returns the missed events, or ``resync: true`` when they are gone (gap older
  than the ring, or the core restarted: ``boot_id`` differs). On ``resync`` the
  client refetches its snapshots (sessions, open transcript via
  ``session.resume``, office, kanban board).
* Server-Sent Events ``/api/events``: each event carries ``id: <seq>`` so the
  browser/phone's ``Last-Event-ID`` (or ``?since=``) resumes the stream exactly;
  a gap is announced as ``event: resync``.

Nothing is polled: subscribers wait on an ``asyncio.Queue`` that ``publish``
fills directly.
"""

from __future__ import annotations

import asyncio
import secrets
import time
from collections import deque
from typing import Any, Iterable

RING_SIZE = 4096
QUEUE_MAX = 2048


class EventBus:
    def __init__(self, ring_size: int = RING_SIZE):
        self.boot_id = secrets.token_hex(8)
        self.seq = 0
        self.ring: deque[dict] = deque(maxlen=ring_size)
        self.subscribers: set[asyncio.Queue] = set()

    # ---- publishing -----------------------------------------------------
    def publish(self, kind: str, session_id: str | None, payload: Any) -> dict:
        self.seq += 1
        ev = {"seq": self.seq, "type": kind, "session_id": session_id, "payload": payload, "ts": time.time()}
        self.ring.append(ev)
        for q in list(self.subscribers):
            try:
                q.put_nowait(ev)
            except asyncio.QueueFull:
                # A subscriber that cannot keep up gets a resync marker instead of
                # an unbounded backlog; it will refetch snapshots.
                self._overflow(q)
        return ev

    @staticmethod
    def _overflow(q: asyncio.Queue) -> None:
        try:
            while True:
                q.get_nowait()
        except asyncio.QueueEmpty:
            pass
        q.put_nowait({"type": "resync", "reason": "slow-consumer"})

    # ---- subscribing ----------------------------------------------------
    def subscribe(self) -> asyncio.Queue:
        q: asyncio.Queue = asyncio.Queue(maxsize=QUEUE_MAX)
        self.subscribers.add(q)
        return q

    def unsubscribe(self, q: asyncio.Queue) -> None:
        self.subscribers.discard(q)

    # ---- replay ---------------------------------------------------------
    def oldest(self) -> int:
        return self.ring[0]["seq"] if self.ring else self.seq + 1

    def replay(self, since: int, boot_id: str | None = None,
               session_ids: Iterable[str] | None = None) -> dict:
        """Events after ``since``. ``resync`` is True when they cannot be replayed."""
        if boot_id and boot_id != self.boot_id:
            return {"boot_id": self.boot_id, "seq": self.seq, "resync": True, "reason": "restarted", "events": []}
        if since > self.seq:
            return {"boot_id": self.boot_id, "seq": self.seq, "resync": True, "reason": "ahead", "events": []}
        if since < self.oldest() - 1:
            return {"boot_id": self.boot_id, "seq": self.seq, "resync": True, "reason": "gap", "events": []}
        allowed = set(session_ids) if session_ids is not None else None
        evs = [e for e in self.ring if e["seq"] > since
               and (allowed is None or e["session_id"] is None or e["session_id"] in allowed)]
        return {"boot_id": self.boot_id, "seq": self.seq, "resync": False, "events": evs}
