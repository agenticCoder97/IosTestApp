"""Server-Sent Events log stream — AST-73.

Subscribers receive new LOG_DEQUE entries matching their filter. The
background log_tailer task calls `publish()` once per line; each
subscriber queue holds the last 500 lines, so a slow client loses
history but never blocks the tailer.
"""
from __future__ import annotations

import asyncio
import json
import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import AsyncIterator, Optional

logger = logging.getLogger("monitor.logs_stream")

_MAX_QUEUE = 500

_LEVEL_RANK = {"debug": 0, "info": 1, "warn": 2, "error": 3}


@dataclass
class LogFilter:
    services: Optional[set[str]] = None
    min_level: str = "debug"
    q: Optional[str] = None

    def matches(self, entry: dict) -> bool:
        if self.services and entry.get("svc") not in self.services:
            return False
        if _LEVEL_RANK.get(entry.get("lvl", "info"), 1) < _LEVEL_RANK.get(self.min_level, 0):
            return False
        if self.q and self.q.lower() not in str(entry.get("msg", "")).lower():
            return False
        return True


@dataclass
class Subscriber:
    queue: asyncio.Queue = field(default_factory=lambda: asyncio.Queue(maxsize=_MAX_QUEUE))
    filt: LogFilter = field(default_factory=LogFilter)


_SUBSCRIBERS: set[Subscriber] = set()


def publish(entry: dict) -> None:
    """Called by bg.log_tailer for every new line."""
    dead: list[Subscriber] = []
    for sub in _SUBSCRIBERS:
        if not sub.filt.matches(entry):
            continue
        try:
            sub.queue.put_nowait(entry)
        except asyncio.QueueFull:
            # Drop oldest — subscriber too slow.
            try:
                sub.queue.get_nowait()
                sub.queue.put_nowait(entry)
            except Exception:
                dead.append(sub)
    for d in dead:
        _SUBSCRIBERS.discard(d)


def _serialize_entry(entry: dict) -> str:
    ts = entry.get("ts")
    if isinstance(ts, datetime):
        ts = ts.isoformat().replace("+00:00", "Z")
    return json.dumps({
        "ts": ts,
        "svc": entry.get("svc"),
        "lvl": entry.get("lvl"),
        "msg": entry.get("msg"),
    }, default=str)


async def subscribe(filt: LogFilter) -> AsyncIterator[str]:
    """Yield SSE frames forever. Caller is expected to run until the
    client disconnects (FastAPI cancels the task on disconnect)."""
    sub = Subscriber(filt=filt)
    _SUBSCRIBERS.add(sub)
    # Emit a comment frame immediately so proxies flush headers.
    yield ": connected\n\n"
    try:
        while True:
            try:
                entry = await asyncio.wait_for(sub.queue.get(), timeout=15.0)
                yield f"data: {_serialize_entry(entry)}\n\n"
            except asyncio.TimeoutError:
                # Heartbeat so proxies / nginx don't close the idle
                # connection; also tells client we're still alive.
                ping = json.dumps({"ts": datetime.now(timezone.utc).isoformat(), "kind": "heartbeat"})
                yield f"event: heartbeat\ndata: {ping}\n\n"
    finally:
        _SUBSCRIBERS.discard(sub)
