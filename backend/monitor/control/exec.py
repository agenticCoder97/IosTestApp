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


import time  # noqa: E402
from monitor.control.audit import record as audit_record
from monitor.control.docker_ops import _find_compose_container


class SessionExists(RuntimeError):
    """A live session already exists for this service."""


async def start_session(service: str, *, cols: int, rows: int) -> Session:
    if service not in EXEC_ALLOWLIST:
        raise ValueError(f"service not exec-allowed: {service}")

    async with service_lock(service):
        if _has_live_session_for(service):
            raise SessionExists(f"session already open for {service}")

        def _do_start():
            container = _find_compose_container(service)
            client = _docker_client()
            ex = client.api.exec_create(
                container=container.id,
                cmd=["/bin/sh"],
                stdout=True, stderr=True, stdin=True, tty=True,
            )
            exec_id = ex["Id"]
            sock = client.api.exec_start(
                exec_id, socket=True, tty=True, demux=False,
            )
            client.api.exec_resize(exec_id, height=rows, width=cols)
            return exec_id, sock

        try:
            exec_id, sock = await asyncio.to_thread(_do_start)
        except Exception as e:
            audit_record("exec.start", ok=False, detail=f"{service}: {e}")
            raise

        now = time.monotonic()
        sess = Session(
            session_id=_new_session_id(),
            service=service,
            exec_id=exec_id,
            sock=sock,
            created_at=now,
            last_activity=now,
        )
        _REGISTRY[sess.session_id] = sess
        audit_record("exec.start", ok=True,
                     detail={"service": service, "session_id": sess.session_id})
        return sess


async def close_session(sess: Session, *, reason: str) -> None:
    if sess._closed:
        return
    sess._closed = True
    sess.reason = reason
    duration = time.monotonic() - sess.created_at

    def _do_close() -> bool:
        try:
            sess.sock._sock.sendall(b"exit\n")
        except Exception:
            pass
        try:
            sess.sock.close()
        except Exception:
            pass
        client = _docker_client()
        try:
            info = client.api.exec_inspect(sess.exec_id)
            return bool(info.get("Running"))
        except Exception:
            return False

    orphaned = await asyncio.to_thread(_do_close)
    _REGISTRY.pop(sess.session_id, None)
    audit_record(
        "exec.close", ok=True,
        detail={
            "service": sess.service,
            "session_id": sess.session_id,
            "duration_s": round(duration, 2),
            "reason": reason,
            "orphaned": orphaned,
            "overflow_throttled": sess.overflow_throttled,
        },
    )


def _docker_client():
    """Reexport so tests can monkeypatch exec.py independently of docker_ops."""
    from monitor.control.docker_ops import _docker_client as inner
    return inner()
