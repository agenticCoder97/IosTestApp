"""Docker-exec terminal sessions brokered over WebSocket (AST-92).

A Session owns a single docker exec instance + the raw socket connected
to its TTY. Pumps bridge that socket to/from a FastAPI WebSocket in
binary-frame-for-stdio + text-JSON-for-control form.
"""
from __future__ import annotations

import asyncio
import logging
import uuid
from dataclasses import dataclass
from typing import Any

logger = logging.getLogger("monitor.control.exec")

EXEC_ALLOWLIST: frozenset[str] = frozenset({
    "postgres", "redis", "fastapi", "arq_worker", "nginx", "certbot",
})

# 10 min idle → server-side close. Exported so tests can monkeypatch.
IDLE_TIMEOUT_S: float = 600.0

# stdout rate cap: 1 MB/s. If a session exceeds this, insert a 50 ms
# sleep before the next read. Protects against `cat /dev/urandom`.
STDOUT_RATE_CAP_BPS: int = 1_000_000


@dataclass
class Session:
    session_id: str
    service: str
    exec_id: str
    sock: Any  # docker-py SocketIO wrapper; .close() + ._sock.{recv,sendall}
    created_at: float
    last_activity: float
    overflow_throttled: int = 0
    reason: str = ""
    _closed: bool = False


_REGISTRY: dict[str, Session] = {}
_SERVICE_LOCKS: dict[str, asyncio.Lock] = {}


def service_lock(service: str) -> asyncio.Lock:
    lock = _SERVICE_LOCKS.get(service)
    if lock is None:
        lock = _SERVICE_LOCKS[service] = asyncio.Lock()
    return lock


def _has_live_session_for(service: str) -> Session | None:
    for sess in _REGISTRY.values():
        if sess.service == service and not sess._closed:
            return sess
    return None


def _new_session_id() -> str:
    return uuid.uuid4().hex
