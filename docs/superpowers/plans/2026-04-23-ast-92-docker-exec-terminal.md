# AST-92 · docker-exec terminal channel — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the AST-78 "coming soon" stub on the monitor service cards with a real interactive shell backed by `docker exec`, brokered by the monitor FastAPI over WebSocket, with persistent scroll-back across flip-back/flip-forward.

**Architecture:** New `monitor.control.exec` module holds an in-process session registry and pumps a raw docker-exec socket (tty=True) ↔ a FastAPI WebSocket. Binary WS frames carry stdio; text WS frames carry JSON control messages (resize / ping / closed). Frontend uses xterm.js with a detached `termHost` DIV that survives service-grid re-renders, allowing a minimize button to preserve shell state.

**Tech Stack:** Python 3.11, FastAPI (built-in WebSocket), `docker==7.1.*` (already pinned), xterm.js 5 via jsdelivr, nginx WebSocket proxying, vanilla JS frontend.

**Branch + PR:** Work on the current worktree branch. PR body must include `Fixes AST-92` on its own line (CLAUDE.md requires this for Linear auto-close). Every commit subject: `[backend] AST-92 <imperative description>`.

---

### Task 1: Scaffold — extract compose-container lookup + new `exec.py` module with allowlist, Session type, and per-service locks

**Files:**
- Modify: `backend/monitor/control/docker_ops.py` (extract helper)
- Create: `backend/monitor/control/exec.py`
- Create: `backend/monitor/tests/test_control_exec.py`

- [ ] **Step 1: Write the failing test for the helper extraction + registry skeleton**

Create `backend/monitor/tests/test_control_exec.py`:

```python
"""Unit tests for monitor.control.exec — session registry, allowlist,
start/close lifecycle, watchdog, rate limit. All docker calls are mocked.
"""
from __future__ import annotations

import asyncio
from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest


# ── allowlist + helper extraction ─────────────────────────────────────

def test_exec_allowlist_contents():
    from monitor.control.exec import EXEC_ALLOWLIST
    assert EXEC_ALLOWLIST == {
        "postgres", "redis", "fastapi", "arq_worker", "nginx", "certbot",
    }
    # astral_monitor is deliberately NOT in the allowlist.
    assert "astral_monitor" not in EXEC_ALLOWLIST


def test_find_compose_container_uses_project_and_service_labels(monkeypatch):
    from monitor.control import docker_ops

    fake_container = SimpleNamespace(short_id="abc123", id="abc123full")
    fake_list = MagicMock(return_value=[fake_container])
    fake_client = SimpleNamespace(containers=SimpleNamespace(list=fake_list))
    monkeypatch.setattr(docker_ops, "_docker_client", lambda: fake_client)

    got = docker_ops._find_compose_container("postgres")
    assert got is fake_container
    kwargs = fake_list.call_args.kwargs
    assert kwargs["filters"]["label"] == [
        "com.docker.compose.project=backend",
        "com.docker.compose.service=postgres",
    ]


def test_find_compose_container_raises_when_missing(monkeypatch):
    from monitor.control import docker_ops

    fake_client = SimpleNamespace(
        containers=SimpleNamespace(list=lambda **_: []),
    )
    monkeypatch.setattr(docker_ops, "_docker_client", lambda: fake_client)

    with pytest.raises(RuntimeError, match="no container for service postgres"):
        docker_ops._find_compose_container("postgres")


def test_session_registry_starts_empty():
    from monitor.control.exec import _REGISTRY
    assert _REGISTRY == {}


def test_service_lock_is_per_service():
    from monitor.control.exec import service_lock
    a = service_lock("postgres")
    b = service_lock("postgres")
    c = service_lock("redis")
    assert a is b          # same service → same lock
    assert a is not c      # different service → different lock
    assert isinstance(a, asyncio.Lock)
```

- [ ] **Step 2: Run tests — expect failures (module missing, helper missing)**

```
cd backend && PYTHONPATH=. pytest monitor/tests/test_control_exec.py -v
```
Expected: `ModuleNotFoundError: monitor.control.exec` and `AttributeError: _find_compose_container`.

- [ ] **Step 3: Extract the helper in `docker_ops.py`**

Replace the inline container-list logic in `restart_service` with a shared helper. In `backend/monitor/control/docker_ops.py`, add at module scope:

```python
def _find_compose_container(service: str):
    """Find a compose-managed container by service label. Raises if absent.
    Shared by restart_service (AST-71) and exec.start_session (AST-92).
    """
    client = _docker_client()
    containers = client.containers.list(
        all=True,
        filters={
            "label": [
                "com.docker.compose.project=backend",
                f"com.docker.compose.service={service}",
            ],
        },
    )
    if not containers:
        raise RuntimeError(f"no container for service {service}")
    return containers[0]
```

Then simplify `restart_service`'s inner `_do_restart` to call `_find_compose_container(service)` and `container.restart(timeout=timeout_s); container.reload()` as before.

- [ ] **Step 4: Create `backend/monitor/control/exec.py` scaffold**

```python
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
```

- [ ] **Step 5: Run tests and verify all pass**

```
cd backend && PYTHONPATH=. pytest monitor/tests/test_control_exec.py -v
```
Expected: 4 passed.

Also re-run the docker_ops tests to confirm the helper extraction didn't break restart:

```
cd backend && PYTHONPATH=. pytest monitor/tests -k "not exec" -q
```
Expected: all prior tests still pass.

- [ ] **Step 6: Commit**

```bash
git add backend/monitor/control/docker_ops.py \
        backend/monitor/control/exec.py \
        backend/monitor/tests/test_control_exec.py
git commit -m "[backend] AST-92 scaffold exec module — allowlist, Session, per-service locks"
```

---

### Task 2: Session lifecycle — `start_session` and `close_session` (docker mocked)

**Files:**
- Modify: `backend/monitor/control/exec.py`
- Modify: `backend/monitor/tests/test_control_exec.py`

- [ ] **Step 1: Write failing tests for start/close**

Append to `backend/monitor/tests/test_control_exec.py`:

```python
# ── session start / close ─────────────────────────────────────────────

class _FakeInnerSock:
    def __init__(self):
        self.written = bytearray()
        self.closed = False
        self._recv_queue: list[bytes] = []
    def sendall(self, data: bytes) -> None:
        self.written.extend(data)
    def recv(self, n: int) -> bytes:
        return self._recv_queue.pop(0) if self._recv_queue else b""


class _FakeSocketIO:
    def __init__(self):
        self._sock = _FakeInnerSock()
        self.closed = False
    def close(self):
        self.closed = True


@pytest.fixture
def fake_docker(monkeypatch):
    """Patch docker_ops._docker_client to a stub exec engine."""
    from monitor.control import docker_ops, exec as exec_mod

    container = SimpleNamespace(short_id="abc123", id="abc123full")
    api = MagicMock()
    api.exec_create.return_value = {"Id": "exec-xyz"}
    sock_io = _FakeSocketIO()
    api.exec_start.return_value = sock_io
    api.exec_inspect.return_value = {"Running": False}

    client = SimpleNamespace(
        containers=SimpleNamespace(list=lambda **_: [container]),
        api=api,
    )
    monkeypatch.setattr(docker_ops, "_docker_client", lambda: client)
    monkeypatch.setattr(exec_mod, "_docker_client", lambda: client,
                        raising=False)

    exec_mod._REGISTRY.clear()
    exec_mod._SERVICE_LOCKS.clear()
    return SimpleNamespace(api=api, sock_io=sock_io, container=container)


@pytest.mark.asyncio
async def test_start_session_rejects_unknown_service(fake_docker):
    from monitor.control.exec import start_session
    with pytest.raises(ValueError, match="service not exec-allowed"):
        await start_session("astral_monitor", cols=80, rows=24)


@pytest.mark.asyncio
async def test_start_session_creates_exec_with_tty_and_stdin(fake_docker):
    from monitor.control.exec import start_session
    sess = await start_session("postgres", cols=120, rows=40)
    assert sess.service == "postgres"
    assert sess.exec_id == "exec-xyz"
    fake_docker.api.exec_create.assert_called_once()
    kwargs = fake_docker.api.exec_create.call_args.kwargs
    assert kwargs["cmd"] == ["/bin/sh"]
    assert kwargs["tty"] is True
    assert kwargs["stdin"] is True
    assert kwargs["stdout"] is True
    assert kwargs["stderr"] is True
    fake_docker.api.exec_start.assert_called_once()
    start_kwargs = fake_docker.api.exec_start.call_args.kwargs
    assert start_kwargs["socket"] is True
    assert start_kwargs["tty"] is True
    assert start_kwargs["demux"] is False


@pytest.mark.asyncio
async def test_start_session_sets_initial_size(fake_docker):
    from monitor.control.exec import start_session
    await start_session("postgres", cols=120, rows=40)
    # height first, width second.
    fake_docker.api.exec_resize.assert_called_once_with(
        "exec-xyz", height=40, width=120,
    )


@pytest.mark.asyncio
async def test_duplicate_start_for_same_service_raises(fake_docker):
    from monitor.control.exec import start_session, SessionExists
    await start_session("redis", cols=80, rows=24)
    with pytest.raises(SessionExists):
        await start_session("redis", cols=80, rows=24)


@pytest.mark.asyncio
async def test_close_session_closes_socket_and_audits(fake_docker, monkeypatch):
    from monitor.control import exec as exec_mod
    records: list[dict] = []
    monkeypatch.setattr(
        exec_mod, "audit_record",
        lambda action, *, ok, detail=None, source_ip=None:
            records.append({"action": action, "ok": ok, "detail": detail}),
    )
    sess = await exec_mod.start_session("redis", cols=80, rows=24)
    await exec_mod.close_session(sess, reason="user-close")
    assert fake_docker.sock_io.closed is True
    assert sess._closed is True
    actions = [r["action"] for r in records]
    assert "exec.start" in actions
    assert "exec.close" in actions
    close_detail = next(r for r in records if r["action"] == "exec.close")["detail"]
    assert close_detail["service"] == "redis"
    assert close_detail["reason"] == "user-close"
    assert "duration_s" in close_detail
    assert "orphaned" in close_detail
```

- [ ] **Step 2: Run tests — expect failures**

```
cd backend && PYTHONPATH=. pytest monitor/tests/test_control_exec.py -v
```
Expected: 5 new tests fail (start_session / close_session / SessionExists not defined).

- [ ] **Step 3: Implement start_session / close_session**

Append to `backend/monitor/control/exec.py`:

```python
import time
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
```

- [ ] **Step 4: Run tests and verify pass**

```
cd backend && PYTHONPATH=. pytest monitor/tests/test_control_exec.py -v
```
Expected: 9 passed.

- [ ] **Step 5: Commit**

```bash
git add backend/monitor/control/exec.py backend/monitor/tests/test_control_exec.py
git commit -m "[backend] AST-92 exec session start/close with audit + session cap"
```

---

### Task 3: `POST /control/exec/start` route — auth, allowlist, 409 on duplicate

**Files:**
- Modify: `backend/monitor/control/routes.py`
- Create: `backend/monitor/tests/test_control_exec_routes.py`

- [ ] **Step 1: Write failing route tests**

Create `backend/monitor/tests/test_control_exec_routes.py`:

```python
"""HTTP-level tests for POST /control/exec/start (AST-92)."""
from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest
from httpx import ASGITransport, AsyncClient


@pytest.fixture
def app_with_token(monkeypatch):
    monkeypatch.setenv("MONITOR_CONTROL_TOKEN", "s3cret")
    container = SimpleNamespace(id="abc123full", short_id="abc123")
    api = MagicMock()
    api.exec_create.return_value = {"Id": "exec-xyz"}

    class _Sock:
        _sock = MagicMock()
        def close(self): pass
    api.exec_start.return_value = _Sock()
    api.exec_inspect.return_value = {"Running": False}

    client = SimpleNamespace(
        containers=SimpleNamespace(list=lambda **_: [container]),
        api=api,
    )
    from monitor.control import docker_ops, exec as exec_mod
    monkeypatch.setattr(docker_ops, "_docker_client", lambda: client)
    monkeypatch.setattr(exec_mod, "_docker_client", lambda: client,
                        raising=False)
    exec_mod._REGISTRY.clear()
    exec_mod._SERVICE_LOCKS.clear()

    from monitor.main import app
    return app


@pytest.mark.asyncio
async def test_start_requires_token_header(app_with_token):
    transport = ASGITransport(app=app_with_token)
    async with AsyncClient(transport=transport, base_url="http://t") as c:
        resp = await c.post("/control/exec/start",
                            json={"service": "postgres", "cols": 80, "rows": 24})
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_start_rejects_non_allowlisted_service(app_with_token):
    transport = ASGITransport(app=app_with_token)
    async with AsyncClient(transport=transport, base_url="http://t") as c:
        resp = await c.post(
            "/control/exec/start",
            json={"service": "astral_monitor", "cols": 80, "rows": 24},
            headers={"X-Monitor-Auth": "s3cret"},
        )
    assert resp.status_code == 400
    assert "not exec-allowed" in resp.json()["detail"]


@pytest.mark.asyncio
async def test_start_returns_session_id(app_with_token):
    transport = ASGITransport(app=app_with_token)
    async with AsyncClient(transport=transport, base_url="http://t") as c:
        resp = await c.post(
            "/control/exec/start",
            json={"service": "postgres", "cols": 80, "rows": 24},
            headers={"X-Monitor-Auth": "s3cret"},
        )
    assert resp.status_code == 200
    body = resp.json()
    assert "session_id" in body and len(body["session_id"]) == 32


@pytest.mark.asyncio
async def test_duplicate_start_returns_409(app_with_token):
    transport = ASGITransport(app=app_with_token)
    async with AsyncClient(transport=transport, base_url="http://t") as c:
        headers = {"X-Monitor-Auth": "s3cret"}
        body = {"service": "redis", "cols": 80, "rows": 24}
        r1 = await c.post("/control/exec/start", json=body, headers=headers)
        assert r1.status_code == 200
        r2 = await c.post("/control/exec/start", json=body, headers=headers)
    assert r2.status_code == 409
    assert "already open" in r2.json()["detail"]


@pytest.mark.asyncio
async def test_missing_token_env_returns_503(app_with_token, monkeypatch):
    monkeypatch.delenv("MONITOR_CONTROL_TOKEN", raising=False)
    transport = ASGITransport(app=app_with_token)
    async with AsyncClient(transport=transport, base_url="http://t") as c:
        resp = await c.post(
            "/control/exec/start",
            json={"service": "postgres", "cols": 80, "rows": 24},
            headers={"X-Monitor-Auth": "anything"},
        )
    assert resp.status_code == 503
```

- [ ] **Step 2: Run tests — expect route-not-found failures**

```
cd backend && PYTHONPATH=. pytest monitor/tests/test_control_exec_routes.py -v
```
Expected: 404s because the route doesn't exist yet.

- [ ] **Step 3: Add the route**

In `backend/monitor/control/routes.py`, import the exec module and add the route after the SQL-console block:

```python
from monitor.control import exec as exec_mod


class ExecStartBody(BaseModel):
    service: str
    cols: int = 80
    rows: int = 24


@router.post("/exec/start")
async def exec_start(body: ExecStartBody, ip: str = Depends(require_auth)) -> JSONResponse:
    try:
        sess = await exec_mod.start_session(
            body.service, cols=body.cols, rows=body.rows,
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except exec_mod.SessionExists as e:
        raise HTTPException(status_code=409, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    return JSONResponse({"session_id": sess.session_id})
```

- [ ] **Step 4: Run tests and verify pass**

```
cd backend && PYTHONPATH=. pytest monitor/tests/test_control_exec_routes.py -v
```
Expected: 5 passed.

- [ ] **Step 5: Commit**

```bash
git add backend/monitor/control/routes.py backend/monitor/tests/test_control_exec_routes.py
git commit -m "[backend] AST-92 add POST /control/exec/start with auth + 409 on duplicate"
```

---

### Task 4: WebSocket handshake — subprotocol auth, Origin check, session lookup

**Files:**
- Modify: `backend/monitor/control/exec.py` (add origin/subprotocol helpers)
- Modify: `backend/monitor/control/routes.py` (WS endpoint — handshake only; pumps in Task 5)
- Modify: `backend/monitor/tests/test_control_exec_routes.py`

- [ ] **Step 1: Write failing WS handshake tests**

Append to `backend/monitor/tests/test_control_exec_routes.py`:

```python
from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect


def _start_session_sync(client: TestClient, service="postgres") -> str:
    r = client.post("/control/exec/start",
                    json={"service": service, "cols": 80, "rows": 24},
                    headers={"X-Monitor-Auth": "s3cret"})
    assert r.status_code == 200, r.text
    return r.json()["session_id"]


def test_ws_rejects_without_subprotocol(app_with_token):
    client = TestClient(app_with_token)
    sid = _start_session_sync(client)
    with pytest.raises(WebSocketDisconnect) as exc:
        with client.websocket_connect(f"/control/exec/{sid}"):
            pass
    assert exc.value.code == 1008


def test_ws_rejects_bad_token(app_with_token):
    client = TestClient(app_with_token)
    sid = _start_session_sync(client)
    with pytest.raises(WebSocketDisconnect) as exc:
        with client.websocket_connect(
            f"/control/exec/{sid}",
            subprotocols=["monitor-token", "wrong"],
        ):
            pass
    assert exc.value.code == 1008


def test_ws_rejects_unknown_session(app_with_token):
    client = TestClient(app_with_token)
    with pytest.raises(WebSocketDisconnect) as exc:
        with client.websocket_connect(
            "/control/exec/deadbeef",
            subprotocols=["monitor-token", "s3cret"],
        ):
            pass
    assert exc.value.code == 1008


def test_ws_rejects_bad_origin(app_with_token):
    client = TestClient(app_with_token)
    sid = _start_session_sync(client)
    with pytest.raises(WebSocketDisconnect) as exc:
        with client.websocket_connect(
            f"/control/exec/{sid}",
            subprotocols=["monitor-token", "s3cret"],
            headers={"origin": "https://evil.example.com"},
        ):
            pass
    assert exc.value.code == 1008


def test_ws_accepts_with_subprotocol_and_allowed_origin(app_with_token):
    client = TestClient(app_with_token)
    sid = _start_session_sync(client)
    # Default TestClient omits Origin — treated as allowed (server-to-server).
    with client.websocket_connect(
        f"/control/exec/{sid}",
        subprotocols=["monitor-token", "s3cret"],
    ) as ws:
        # Just accept/close — pumps land in Task 5.
        ws.close()
```

- [ ] **Step 2: Run tests — expect WS-route-missing failures**

```
cd backend && PYTHONPATH=. pytest monitor/tests/test_control_exec_routes.py -v -k "ws_"
```
Expected: all 5 WS tests fail with 404 or routing errors.

- [ ] **Step 3: Add Origin + subprotocol helpers to `exec.py`**

Append to `backend/monitor/control/exec.py`:

```python
import re

_ALLOWED_ORIGIN_PATTERNS: tuple[re.Pattern[str], ...] = (
    re.compile(r"^https://astral-reader\.duckdns\.org$"),
    re.compile(r"^http://localhost(:\d+)?$"),
    re.compile(r"^http://127\.0\.0\.1(:\d+)?$"),
    re.compile(r"^http://192\.168\.0\.108(:\d+)?$"),
)


def origin_allowed(origin: str | None) -> bool:
    # Missing Origin → non-browser (test client). Allow.
    if not origin:
        return True
    return any(p.match(origin) for p in _ALLOWED_ORIGIN_PATTERNS)


def token_from_subprotocols(offered: list[str]) -> str | None:
    # Client offers ['monitor-token', '<token>']. Accept only if both slots
    # present and first is the literal sentinel.
    if len(offered) < 2 or offered[0] != "monitor-token":
        return None
    return offered[1]
```

- [ ] **Step 4: Add WS route to `routes.py`**

Add at the end of `backend/monitor/control/routes.py`:

```python
from fastapi import WebSocket


@router.websocket("/exec/{session_id}")
async def exec_ws(websocket: WebSocket, session_id: str) -> None:
    expected = os.getenv("MONITOR_CONTROL_TOKEN")
    offered = [p.strip() for p in
               websocket.headers.get("sec-websocket-protocol", "").split(",")
               if p.strip()]
    tok = exec_mod.token_from_subprotocols(offered)
    if not expected or tok != expected:
        await websocket.close(code=1008)
        return
    if not exec_mod.origin_allowed(websocket.headers.get("origin")):
        await websocket.close(code=1008)
        return
    sess = exec_mod._REGISTRY.get(session_id)
    if sess is None or sess._closed:
        await websocket.close(code=1008)
        return
    await websocket.accept(subprotocol="monitor-token")
    # Pumps land in Task 5 — for now, immediately close so handshake tests pass.
    await websocket.close(code=1000)
```

- [ ] **Step 5: Run tests and verify pass**

```
cd backend && PYTHONPATH=. pytest monitor/tests/test_control_exec_routes.py -v
```
Expected: all 10 tests pass.

- [ ] **Step 6: Commit**

```bash
git add backend/monitor/control/exec.py backend/monitor/control/routes.py \
        backend/monitor/tests/test_control_exec_routes.py
git commit -m "[backend] AST-92 WS handshake — subprotocol auth, origin allowlist, session lookup"
```

---

### Task 5: I/O pumps + control frames (binary passthrough, resize, ping/pong, closed)

**Files:**
- Modify: `backend/monitor/control/exec.py`
- Modify: `backend/monitor/control/routes.py`
- Modify: `backend/monitor/tests/test_control_exec_routes.py`

- [ ] **Step 1: Write failing pump tests**

Append to `backend/monitor/tests/test_control_exec_routes.py`:

```python
import json
import time


def test_ws_passes_binary_stdin_to_docker_socket(app_with_token):
    from monitor.control import exec as exec_mod
    client = TestClient(app_with_token)
    sid = _start_session_sync(client)
    sess = exec_mod._REGISTRY[sid]
    with client.websocket_connect(
        f"/control/exec/{sid}",
        subprotocols=["monitor-token", "s3cret"],
    ) as ws:
        ws.send_bytes(b"ls -la\n")
        time.sleep(0.05)
    sent = sess.sock._sock.sendall.call_args_list
    payloads = [call.args[0] for call in sent]
    assert b"ls -la\n" in payloads


def test_ws_resize_frame_calls_exec_resize_height_first(app_with_token):
    client = TestClient(app_with_token)
    sid = _start_session_sync(client)
    with client.websocket_connect(
        f"/control/exec/{sid}",
        subprotocols=["monitor-token", "s3cret"],
    ) as ws:
        ws.send_text(json.dumps({"type": "resize", "cols": 132, "rows": 50}))
        time.sleep(0.05)
    from monitor.control.docker_ops import _docker_client
    api = _docker_client().api
    # Initial resize (80x24 from start_session) + our 132x50 frame.
    calls = api.exec_resize.call_args_list
    assert calls[-1].kwargs == {"height": 50, "width": 132}


def test_ws_ping_receives_pong(app_with_token):
    client = TestClient(app_with_token)
    sid = _start_session_sync(client)
    with client.websocket_connect(
        f"/control/exec/{sid}",
        subprotocols=["monitor-token", "s3cret"],
    ) as ws:
        ws.send_text(json.dumps({"type": "ping"}))
        frame = ws.receive_text()
    assert json.loads(frame) == {"type": "pong"}
```

- [ ] **Step 2: Run tests — expect failures**

```
cd backend && PYTHONPATH=. pytest monitor/tests/test_control_exec_routes.py -v -k "binary or resize or ping"
```
Expected: all 3 fail (pumps not wired; stub just closes).

- [ ] **Step 3: Implement the pump pair in `exec.py`**

Append to `backend/monitor/control/exec.py`:

```python
import json as _json
from typing import Awaitable, Callable


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
            await asyncio.to_thread(sess.sock._sock.sendall, msg["bytes"])
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
```

- [ ] **Step 4: Wire pumps into the WS route**

Replace the body of `exec_ws` in `backend/monitor/control/routes.py` after `websocket.accept(...)`:

```python
    await websocket.accept(subprotocol="monitor-token")

    async def _recv() -> dict:
        return await websocket.receive()

    stdout_task = asyncio.create_task(
        exec_mod.pump_stdout(sess, websocket.send_bytes),
    )
    stdin_task = asyncio.create_task(
        exec_mod.pump_stdin(sess, _recv, websocket.send_text),
    )
    done, pending = await asyncio.wait(
        {stdout_task, stdin_task}, return_when=asyncio.FIRST_COMPLETED,
    )
    for t in pending:
        t.cancel()
    try:
        await websocket.send_text('{"type":"closed","reason":"exec-exited"}')
    except Exception:
        pass
    try:
        await websocket.close(code=1000)
    except Exception:
        pass
    await exec_mod.close_session(sess, reason="exec-exited")
```

- [ ] **Step 5: Run tests and verify pass**

```
cd backend && PYTHONPATH=. pytest monitor/tests/test_control_exec_routes.py -v
```
Expected: all tests pass (10 prior + 3 new = 13).

- [ ] **Step 6: Commit**

```bash
git add backend/monitor/control/exec.py backend/monitor/control/routes.py \
        backend/monitor/tests/test_control_exec_routes.py
git commit -m "[backend] AST-92 pumps — binary stdio passthrough, resize/ping/pong control frames"
```

---

### Task 6: Idle watchdog + closed-frame-with-reason

**Files:**
- Modify: `backend/monitor/control/exec.py`
- Modify: `backend/monitor/control/routes.py`
- Modify: `backend/monitor/tests/test_control_exec.py`

- [ ] **Step 1: Write failing watchdog test**

Append to `backend/monitor/tests/test_control_exec.py`:

```python
@pytest.mark.asyncio
async def test_idle_watchdog_closes_stale_session(fake_docker, monkeypatch):
    from monitor.control import exec as exec_mod
    monkeypatch.setattr(exec_mod, "IDLE_TIMEOUT_S", 0.1)
    sess = await exec_mod.start_session("postgres", cols=80, rows=24)
    closed: list[str] = []
    original = exec_mod.close_session

    async def _spy(s, *, reason):
        closed.append(reason)
        await original(s, reason=reason)

    monkeypatch.setattr(exec_mod, "close_session", _spy)
    task = asyncio.create_task(exec_mod.idle_watchdog(sess, interval_s=0.02))
    await asyncio.sleep(0.3)
    task.cancel()
    assert "idle" in closed
    assert sess._closed is True
```

- [ ] **Step 2: Run test — expect failure (idle_watchdog missing)**

```
cd backend && PYTHONPATH=. pytest monitor/tests/test_control_exec.py::test_idle_watchdog_closes_stale_session -v
```

- [ ] **Step 3: Implement watchdog + use it in the route**

Append to `backend/monitor/control/exec.py`:

```python
async def idle_watchdog(sess: Session, *, interval_s: float = 30.0) -> None:
    """Close the session after IDLE_TIMEOUT_S of no activity."""
    while not sess._closed:
        await asyncio.sleep(interval_s)
        if sess._closed:
            return
        if time.monotonic() - sess.last_activity > IDLE_TIMEOUT_S:
            await close_session(sess, reason="idle")
            return
```

In `routes.py::exec_ws`, add a watchdog task alongside the pumps and use the right `reason` in the closed frame:

```python
    watchdog_task = asyncio.create_task(exec_mod.idle_watchdog(sess))
    stdout_task = asyncio.create_task(
        exec_mod.pump_stdout(sess, websocket.send_bytes),
    )
    stdin_task = asyncio.create_task(
        exec_mod.pump_stdin(sess, _recv, websocket.send_text),
    )
    done, pending = await asyncio.wait(
        {stdout_task, stdin_task}, return_when=asyncio.FIRST_COMPLETED,
    )
    for t in pending:
        t.cancel()
    watchdog_task.cancel()
    reason = sess.reason or "exec-exited"
    try:
        await websocket.send_text(
            _json_dump({"type": "closed", "reason": reason})
        )
    except Exception:
        pass
    try:
        await websocket.close(code=1000)
    except Exception:
        pass
    if not sess._closed:
        await exec_mod.close_session(sess, reason=reason)
```

Add a small helper import at the top of `routes.py`:

```python
from json import dumps as _json_dump
```

- [ ] **Step 4: Run tests — all green**

```
cd backend && PYTHONPATH=. pytest monitor/tests/test_control_exec.py monitor/tests/test_control_exec_routes.py -v
```

- [ ] **Step 5: Commit**

```bash
git add backend/monitor/control/exec.py backend/monitor/control/routes.py \
        backend/monitor/tests/test_control_exec.py
git commit -m "[backend] AST-92 idle watchdog + closed-frame with reason on teardown"
```

---

### Task 7: Nginx — WebSocket proxy config

**Files:**
- Modify: `backend/nginx/nginx.conf`

- [ ] **Step 1: Add the `map` block inside `http {}`**

Open `backend/nginx/nginx.conf`. Locate the existing `http {` opening brace. Directly beneath it (before the first `server {`) add:

```nginx
    # WebSocket upgrade helper (AST-92 /control/exec channel).
    map $http_upgrade $connection_upgrade {
        default upgrade;
        ''      close;
    }
```

- [ ] **Step 2: Replace the `/monitor/` location body with the WS-aware version**

Find the existing `location /monitor/ { … }` block and replace it with:

```nginx
        location /monitor/ {
            auth_basic "astral";
            auth_basic_user_file /etc/nginx/htpasswd;
            set $monitor_upstream http://astral_monitor:8001;
            rewrite ^/monitor(/.*)$ $1 break;
            proxy_pass $monitor_upstream;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;

            # WebSocket upgrade (AST-92 docker-exec terminal).
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $connection_upgrade;

            # Long-lived, unbuffered for WS.
            proxy_read_timeout 3600s;
            proxy_send_timeout 3600s;
            proxy_buffering off;
        }
```

- [ ] **Step 3: Smoke-check the config**

```bash
docker run --rm -v "$PWD/backend/nginx/nginx.conf":/etc/nginx/nginx.conf:ro nginx:1.25-alpine nginx -t
```
Expected output includes `syntax is ok` and `test is successful`. Missing-file warnings (htpasswd / certs) are fine — we only care about syntax.

- [ ] **Step 4: Commit**

```bash
git add backend/nginx/nginx.conf
git commit -m "[backend] AST-92 nginx WebSocket upgrade on /monitor/ + connection_upgrade map"
```

---

### Task 8: Frontend — xterm CDN + two-button back face + cache bust

**Files:**
- Modify: `backend/monitor/static/index.html`
- Modify: `backend/monitor/tests/test_main.py`

- [ ] **Step 1: Add xterm stylesheet + scripts to `<head>`**

In `backend/monitor/static/index.html`, add just after the Google Fonts `<link>` near line 9:

```html
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@xterm/xterm@5/css/xterm.css">
<script src="https://cdn.jsdelivr.net/npm/@xterm/xterm@5/lib/xterm.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/@xterm/addon-fit@0.10/lib/addon-fit.min.js"></script>
```

- [ ] **Step 2: Replace the back-face stub markup**

Find the block inside the svc-card template (around line 1804):

```html
<div class="svc-face back">
  <button class="term-close" title="close terminal" data-close-term="${name}">✕</button>
  <div class="text-[11px] tracking-[.14em] uppercase text-muted">Shell · ${name}</div>
  <div class="term-body"><span style="color:var(--gold)">$</span> <span class="mono">_</span>
<div class="mt-2 text-muted text-[11px]">Terminal UI is a stub — real exec channel lands in AST-92.</div></div>
</div>
```

Replace with:

```html
<div class="svc-face back">
  <div class="term-bar">
    <span class="text-[11px] tracking-[.14em] uppercase text-muted">Shell · ${name}</span>
    <span class="flex-1"></span>
    <button class="ibtn term-min" title="minimize — keep session open" data-min-term="${name}">−</button>
    <button class="ibtn term-close" title="close shell" data-close-term="${name}">✕</button>
  </div>
  <div class="term-body" data-term-body="${name}"></div>
</div>
```

- [ ] **Step 3: Add `.term-bar` / `.term-body` styles**

Append inside the existing `<style>` block:

```css
.term-bar{ display:flex; align-items:center; gap:8px; padding:6px 10px;
          border-bottom:1px solid var(--border); }
.term-body{ flex:1; min-height:0; padding:6px 8px; outline:none;
           cursor:text; overflow:hidden; }
.term-body .xterm,
.term-body .xterm-viewport,
.term-body .xterm-screen{ width:100% !important; height:100% !important; }
```

- [ ] **Step 4: Bump cache-bust suffix**

Change `<script src="static/controls.js?v=4">` (near line 2335) to `<script src="static/controls.js?v=5">`.

- [ ] **Step 5: Add AST-92 marker test to `test_main.py`**

Append to `backend/monitor/tests/test_main.py`:

```python
@pytest.mark.asyncio
async def test_index_html_ast92_terminal_markers():
    """Protects AST-92 terminal shell surface."""
    from monitor.main import app
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        resp = await c.get("/")
    html = resp.text
    required = [
        "@xterm/xterm@5",                # CDN include
        "@xterm/addon-fit",              # fit addon
        'data-min-term="',               # minimize button data attr
        'data-term-body="',              # term-body data attr
        "controls.js?v=5",               # cache bust
    ]
    for needle in required:
        assert needle in html, f"AST-92 marker missing: {needle}"
    assert "real exec channel lands in AST-92" not in html
    assert "Terminal UI is a stub" not in html
```

- [ ] **Step 6: Run tests**

```
cd backend && PYTHONPATH=. pytest monitor/tests/test_main.py -v
```
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add backend/monitor/static/index.html backend/monitor/tests/test_main.py
git commit -m "[backend] AST-92 frontend — xterm CDN, two-button back face, v=5 cache bust"
```

---

### Task 9: Frontend — `openTerminal` cold path (WS wire, resize, fit, focus, shortcut guard)

**Files:**
- Modify: `backend/monitor/static/controls.js`
- Modify: `backend/monitor/static/index.html` (inline script that binds click handlers)

- [ ] **Step 1: Append `openTerminal` and helpers to `controls.js`**

```js
// ── AST-92 docker-exec terminal ──────────────────────────────────────
window.STATE = window.STATE || {};
STATE.terms = STATE.terms || {};   // service → { termHost, term, fitAddon, ws, sessionId, mountedAt, stale }

function _monitorBase(){
  return location.pathname.startsWith('/monitor/') ? '/monitor' : '';
}

function _wsURL(sessionId){
  const scheme = location.protocol === 'https:' ? 'wss' : 'ws';
  return `${scheme}://${location.host}${_monitorBase()}/control/exec/${sessionId}`;
}

async function _postExecStart(service, cols, rows, token){
  const r = await fetch(`${_monitorBase()}/control/exec/start`, {
    method: 'POST',
    headers: {'Content-Type': 'application/json', 'X-Monitor-Auth': token || ''},
    body: JSON.stringify({service, cols, rows}),
  });
  if (r.status === 409) {
    const e = new Error('session-already-open'); e.status = 409; throw e;
  }
  if (!r.ok) {
    const e = new Error(await r.text()); e.status = r.status; throw e;
  }
  return r.json();
}

function _clearChildren(el){
  while (el.firstChild) el.removeChild(el.firstChild);
}

function _showTermBanner(termBody, message){
  const banner = document.createElement('div');
  banner.className = 'term-banner';
  banner.textContent = message;
  banner.style.cssText = 'padding:6px 10px;color:var(--warning);font-size:12px;';
  termBody.appendChild(banner);
}

async function openTerminal(wrap, service){
  const termBody = wrap.querySelector('.term-body');
  if (!termBody) return;

  // Warm-reopen path: existing live session → just re-attach.
  const prior = STATE.terms[service];
  if (prior && prior.ws && prior.ws.readyState === WebSocket.OPEN && !prior.stale) {
    if (!termBody.contains(prior.termHost)) {
      _clearChildren(termBody);
      termBody.appendChild(prior.termHost);
    }
    _afterFlipForward(wrap, prior);
    return;
  }
  const wasStale = !!(prior && prior.stale);
  if (prior) {
    try { prior.ws && prior.ws.close(); } catch(_){}
    delete STATE.terms[service];
  }

  // Cold open.
  _clearChildren(termBody);
  const token = (localStorage.getItem('monitorToken') || '').trim();
  if (!token) {
    _showTermBanner(termBody, 'Missing control token — set it in the dashboard.');
    return;
  }

  let startResp;
  try {
    startResp = await _postExecStart(service, 80, 24, token);
  } catch (e) {
    if (e.status === 409) {
      _showTermBanner(termBody,
        'Session already open (close the other tab, or wait 10 min for idle timeout).');
    } else {
      _showTermBanner(termBody, `Shell start failed: ${e.message || e.status}`);
    }
    return;
  }

  const termHost = document.createElement('div');
  termHost.style.cssText = 'width:100%;height:100%;';
  termBody.appendChild(termHost);

  // eslint-disable-next-line no-undef
  const term = new Terminal({
    fontFamily: '"JetBrains Mono", ui-monospace, monospace',
    fontSize: 12,
    theme: {background: '#0A0A0B', foreground: '#C8C8D4', cursor: '#C9A84C'},
    convertEol: true,
    cursorBlink: true,
  });
  // eslint-disable-next-line no-undef
  const fitAddon = new FitAddon.FitAddon();
  term.loadAddon(fitAddon);
  term.open(termHost);
  if (wasStale) {
    term.writeln('\x1b[33m[shell reconnected — previous session timed out]\x1b[0m');
  }

  const ws = new WebSocket(_wsURL(startResp.session_id), ['monitor-token', token]);
  ws.binaryType = 'arraybuffer';

  term.onData(d => {
    if (ws.readyState === WebSocket.OPEN) ws.send(new TextEncoder().encode(d));
  });

  ws.addEventListener('message', ev => {
    if (typeof ev.data === 'string') {
      let ctrl; try { ctrl = JSON.parse(ev.data); } catch(_) { return; }
      if (ctrl.type === 'closed') {
        term.writeln(`\r\n\x1b[33m[shell ${ctrl.reason || 'closed'}]\x1b[0m`);
      }
      return;
    }
    term.write(new Uint8Array(ev.data));
  });

  ws.addEventListener('close', () => {
    const entry = STATE.terms[service];
    if (entry) entry.stale = true;
  });

  STATE.terms[service] = {
    termHost, term, fitAddon, ws,
    sessionId: startResp.session_id,
    mountedAt: Date.now(),
    stale: false,
  };

  _afterFlipForward(wrap, STATE.terms[service]);
}

function _afterFlipForward(wrap, entry){
  const inner = wrap.querySelector('.svc-flip-inner');
  const done = () => {
    try { entry.fitAddon.fit(); } catch(_){}
    entry.term.focus();
    if (entry.ws && entry.ws.readyState === WebSocket.OPEN) {
      entry.ws.send(JSON.stringify({
        type: 'resize', cols: entry.term.cols, rows: entry.term.rows,
      }));
    }
  };
  const handler = (ev) => {
    if (ev.target !== inner) return;
    inner.removeEventListener('transitionend', handler);
    done();
  };
  if (inner) inner.addEventListener('transitionend', handler);
  setTimeout(done, 400);

  if (!wrap._termResizeObs) {
    wrap._termResizeObs = new ResizeObserver(() => {
      try { entry.fitAddon.fit(); } catch(_){}
      if (entry.ws && entry.ws.readyState === WebSocket.OPEN) {
        entry.ws.send(JSON.stringify({
          type: 'resize', cols: entry.term.cols, rows: entry.term.rows,
        }));
      }
    });
    wrap._termResizeObs.observe(wrap.querySelector('.term-body'));
  }
}

// Invoked from existing global keyboard-shortcut handlers.
window._termHasFocus = function(){
  return !!document.activeElement?.closest('.term-body');
};

window.addEventListener('beforeunload', () => {
  if (!STATE.terms) return;
  for (const k of Object.keys(STATE.terms)) {
    try { STATE.terms[k].ws && STATE.terms[k].ws.close(1000, 'tab-close'); } catch(_){}
  }
});
```

- [ ] **Step 2: Rewrite the inline click handler in index.html**

Find the block around line 1814 starting with `// AST-78-ext2 — terminal flip wiring …`. Replace the `svc-terminal`/`term-close` wiring (and any new `term-min` binding) with:

```html
<script>
  // AST-92 — terminal flip + open + minimize/close (re-bound each render).
  document.querySelectorAll('.svc-terminal').forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      const name = btn.dataset.service;
      const wrap = btn.closest('.svc-flip');
      if (!wrap) return;
      wrap.classList.add('flipped');
      openTerminal(wrap, name);
    });
  });
  document.querySelectorAll('.term-min').forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      const wrap = btn.closest('.svc-flip');
      if (wrap) wrap.classList.remove('flipped');
      // Keep ws + xterm alive — that's the whole point of minimize.
    });
  });
  document.querySelectorAll('.term-close').forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      const name = btn.dataset.closeTerm;
      const wrap = btn.closest('.svc-flip');
      if (wrap) wrap.classList.remove('flipped');
      const entry = STATE.terms && STATE.terms[name];
      if (entry) {
        try { entry.ws && entry.ws.close(1000, 'user-close'); } catch(_){}
        try { entry.term.dispose(); } catch(_){}
        delete STATE.terms[name];
      }
    });
  });
</script>
```

- [ ] **Step 3: Add shortcut guards to existing `keydown` handlers**

Find every `keydown` handler in `controls.js` and `index.html`:

```
cd backend/monitor/static && grep -n "addEventListener('keydown'" *.js *.html
```

At the top of each handler body, add:

```js
if (window._termHasFocus && window._termHasFocus()) return;
```

- [ ] **Step 4: Confirm the token localStorage key name**

Search for how the dashboard already persists the token:

```
cd backend/monitor/static && grep -n "localStorage" controls.js index.html
```

If the stored key is not `monitorToken`, change the two references in `_postExecStart` and `openTerminal` (inside the cold-open `localStorage.getItem(...)`) to match the existing key. This keeps the new feature aligned with the existing UX from AST-70..77.

- [ ] **Step 5: Manual smoke — local compose up**

```
cd backend && docker compose -f docker-compose.local.yml up -d --build astral_monitor
```

Open http://localhost/monitor/. Click the terminal icon on the `fastapi` card. Expect:
- Card flips; xterm prompt appears within ~1 s.
- `ls /app` → streams the FastAPI source dir back.
- Resize the browser window → terminal reflows with no truncation.
- `−` (minimize) → flip back. Click terminal icon again → same scroll-back, no new audit row.
- `✕` (close) → flip back. Re-open → fresh shell (new audit row).

- [ ] **Step 6: Commit**

```bash
git add backend/monitor/static/controls.js backend/monitor/static/index.html
git commit -m "[backend] AST-92 openTerminal cold path + minimize/close + shortcut guards"
```

---

### Task 10: Prod smoke + CHANGELOG + PR

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Full test-suite sweep**

```
cd backend && PYTHONPATH=. pytest monitor/tests -v
```
Expected: all green (Task 1–6 tests + Task 8 marker test).

- [ ] **Step 2: Push branch**

```bash
git push origin HEAD
```

- [ ] **Step 3: Deploy to prod**

SSH in (path per CLAUDE.md is `/home/ubuntu/astral/backend/`):

```bash
ssh -i ~/.ssh/astral_oci ubuntu@astral-reader.duckdns.org
cd /home/ubuntu/astral
git pull
cd backend
docker compose up -d --build astral_monitor nginx
docker compose ps
```

Wait for both containers to report `healthy`.

- [ ] **Step 4: Run the prod manual smoke**

At https://astral-reader.duckdns.org/monitor/ (Basic Auth):

1. Click terminal on `fastapi` → prompt appears.
2. `ls /app` → FastAPI source dir listed.
3. Resize browser → terminal reflows.
4. Minimize (−) → wait ~45 s → re-open → same scroll-back, no new `exec.start` in the audit-log card.
5. Close (✕) → re-open → fresh session, new `exec.start` row.
6. Open a second tab, attempt the same service → 409 banner.
7. Leave idle 10 min → watchdog closes it → re-open shows `[shell reconnected — previous session timed out]` above a fresh prompt.

- [ ] **Step 5: Append CHANGELOG entry**

At the top of `CHANGELOG.md`:

```markdown
- [backend] AST-92 — monitor dashboard docker-exec terminal channel. Terminal-icon button on service cards now opens a real xterm.js shell backed by `docker exec` inside the corresponding container. WS at `/control/exec/{session_id}`, gated by `MONITOR_CONTROL_TOKEN` subprotocol + Origin allowlist. Minimize (−) keeps scroll-back and the live shell across flip-back/flip-forward; close (✕) fully tears down. 10-min idle watchdog.
```

- [ ] **Step 6: Commit + push + PR**

```bash
git add CHANGELOG.md
git commit -m "[backend] AST-92 changelog entry"
git push origin HEAD

gh pr create --base development --title "[backend] AST-92 monitor dashboard docker-exec terminal channel" --body "$(cat <<'EOF'
## Summary
- New `POST /control/exec/start` + `WS /control/exec/{session_id}` in monitor — brokers `docker exec` to an xterm.js terminal in the service-card flip view.
- Auth reuses `MONITOR_CONTROL_TOKEN`: HTTP via `X-Monitor-Auth`, WS via `Sec-WebSocket-Protocol: monitor-token,<tok>` plus Origin allowlist.
- Allowlist hard-coded to six compose services (`postgres`, `redis`, `fastapi`, `arq_worker`, `nginx`, `certbot`); `astral_monitor` deliberately excluded.
- Frontend `openTerminal` mounts xterm into a detached `termHost` DIV so service-grid re-renders do not destroy it. Minimize (−) keeps the session alive with full scroll-back; close (✕) tears it down.
- Nginx `/monitor/` now handles WebSocket upgrades (`map` + `proxy_http_version 1.1` + Upgrade/Connection + `proxy_buffering off`).

## Test plan
- [x] `pytest backend/monitor/tests` — allowlist, auth (401/503), 409 duplicate, WS handshake (subprotocol / Origin / unknown session), binary pump, resize-arg order, ping/pong, idle watchdog
- [ ] Manual smoke on prod — open shell, run commands, minimize+reopen preserves buffer, close+reopen is fresh, 409 on second tab, idle-timeout reconnect note

Fixes AST-92

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Print the returned PR URL.

---

## Self-Review

**Spec coverage:**
- In-scope `POST /control/exec/start` → Task 3. ✔
- `WS /control/exec/{session_id}` → Task 4 (handshake) + Task 5 (pumps). ✔
- Allowlist + auth + audit → Tasks 1, 2, 3, 4. ✔
- Binary I/O + text control (resize / ping / closed) → Task 5. ✔
- Idle watchdog → Task 6. ✔
- Persistent scroll-back via minimize → Task 9 (`STATE.terms` + detached `termHost`). ✔
- Disconnect/reconnect note on stale-reopen → Task 9 (`wasStale` branch). ✔
- Nginx WS → Task 7. ✔
- Cache bust + markers → Task 8. ✔
- `exec_resize(height, width)` order → Task 2 test + Task 5 test, both lock it. ✔
- Rate cap 1 MB/s → Task 5 `pump_stdout`. ✔
- Orphaned-exec acknowledgment → Task 2 `close_session` (`exec_inspect` + `orphaned` audit field). ✔

**Placeholder scan:** no "TBD" / "TODO" / "add appropriate"; every step has actual code or exact commands.

**Type consistency:**
- `Session.sock._sock.{recv,sendall}` used consistently across start/close/pumps.
- `EXEC_ALLOWLIST` (frozenset) used same way in tests and production.
- `STATE.terms[service]` shape identical in cold-open, warm-reopen, minimize, close, beforeunload.
- Function names consistent: `start_session`, `close_session`, `pump_stdout`, `pump_stdin`, `idle_watchdog`, `origin_allowed`, `token_from_subprotocols`.

Self-review passes.

---

**Plan complete and saved to [docs/superpowers/plans/2026-04-23-ast-92-docker-exec-terminal.md](docs/superpowers/plans/2026-04-23-ast-92-docker-exec-terminal.md). Two execution options:**

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

**Which approach?**
