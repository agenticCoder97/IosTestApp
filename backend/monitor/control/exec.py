"""Docker-exec terminal sessions brokered over WebSocket (AST-92).

A Session owns a single docker exec instance + the raw socket connected
to its TTY. Pumps bridge that socket to/from a FastAPI WebSocket in
binary-frame-for-stdio + text-JSON-for-control form.
"""
from __future__ import annotations

import asyncio
import json as _json
import logging
import re
import time
import uuid
from dataclasses import dataclass
from typing import Any, Awaitable, Callable

from monitor.control.audit import record as audit_record
from monitor.control.docker_ops import _find_compose_container

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


# ── WebSocket helpers ─────────────────────────────────────────────────

_ALLOWED_ORIGIN_PATTERNS: tuple[re.Pattern[str], ...] = (
    re.compile(r"^https://astral-reader\.duckdns\.org\Z"),
    re.compile(r"^http://localhost(:\d+)?\Z"),
    re.compile(r"^http://127\.0\.0\.1(:\d+)?\Z"),
    re.compile(r"^http://192\.168\.0\.108(:\d+)?\Z"),
)


def origin_allowed(origin: str | None) -> bool:
    # Missing Origin → non-browser (test client). Allow.
    if not origin:
        return True
    return any(p.match(origin.lower()) for p in _ALLOWED_ORIGIN_PATTERNS)


def token_from_subprotocols(offered: list[str]) -> str | None:
    # Client offers ['monitor-token', '<token>']. Accept only if both slots
    # present and first is the literal sentinel.
    if len(offered) < 2 or offered[0] != "monitor-token":
        return None
    return offered[1]


# ── I/O pumps ─────────────────────────────────────────────────────────


async def pump_stdout(sess: Session, send_bytes: Callable[[bytes], Awaitable[None]]) -> None:
    """Read from docker socket → WS binary frames. Enforces rate cap."""
    window_start = time.monotonic()
    window_bytes = 0
    while not sess._closed:
        try:
            chunk = await asyncio.to_thread(sess.sock._sock.recv, 4096)
        except Exception:
            return
        if not chunk:
            return
        sess.last_activity = time.monotonic()
        now = time.monotonic()
        if now - window_start >= 1.0:
            window_start, window_bytes = now, 0
        window_bytes += len(chunk)
        if window_bytes > STDOUT_RATE_CAP_BPS:
            sess.overflow_throttled += 1
            await asyncio.sleep(0.05)
            window_start, window_bytes = time.monotonic(), 0
        try:
            await send_bytes(chunk)
        except Exception:
            return


async def pump_stdin(
    sess: Session,
    recv: Callable[[], Awaitable[dict]],
    send_text: Callable[[str], Awaitable[None]],
) -> None:
    """WS → docker socket. Binary frames are stdin; text frames are control."""
    while not sess._closed:
        try:
            msg = await recv()
        except Exception:
            return
        sess.last_activity = time.monotonic()
        if msg.get("bytes") is not None:
            try:
                await asyncio.to_thread(sess.sock._sock.sendall, msg["bytes"])
            except Exception:
                return
            continue
        text = msg.get("text")
        if not text:
            continue
        try:
            ctrl = _json.loads(text)
        except ValueError:
            continue
        t = ctrl.get("type")
        if t == "ping":
            await send_text(_json.dumps({"type": "pong"}))
        elif t == "resize":
            cols = int(ctrl.get("cols", 0))
            rows = int(ctrl.get("rows", 0))
            if 1 <= cols <= 500 and 1 <= rows <= 200:
                def _resize():
                    _docker_client().api.exec_resize(
                        sess.exec_id, height=rows, width=cols,
                    )
                try:
                    await asyncio.to_thread(_resize)
                except Exception:
                    pass
