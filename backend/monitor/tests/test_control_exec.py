"""Unit tests for monitor.control.exec — session registry, allowlist,
start/close lifecycle, watchdog, rate limit. All docker calls are mocked.
"""
from __future__ import annotations

import asyncio
from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest


@pytest.fixture(autouse=True)
def _reset_exec_state():
    """Ensure module-level _REGISTRY and _SERVICE_LOCKS start clean for every
    test in this module, so test order cannot hide regressions."""
    from monitor.control import exec as exec_mod
    exec_mod._REGISTRY.clear()
    exec_mod._SERVICE_LOCKS.clear()
    yield
    exec_mod._REGISTRY.clear()
    exec_mod._SERVICE_LOCKS.clear()


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


@pytest.mark.asyncio
async def test_start_session_audits_failure_and_reraises(fake_docker, monkeypatch):
    from monitor.control import exec as exec_mod
    fake_docker.api.exec_create.side_effect = RuntimeError("docker down")
    records: list[dict] = []
    monkeypatch.setattr(
        exec_mod, "audit_record",
        lambda action, *, ok, detail=None, source_ip=None:
            records.append({"action": action, "ok": ok, "detail": detail}),
    )
    with pytest.raises(RuntimeError, match="docker down"):
        await exec_mod.start_session("postgres", cols=80, rows=24)
    assert records == [
        {"action": "exec.start", "ok": False, "detail": "postgres: docker down"},
    ]
    # Session should NOT be registered if start fails.
    assert exec_mod._REGISTRY == {}


def test_origin_allowed_rejects_trailing_newline():
    from monitor.control.exec import origin_allowed
    assert origin_allowed("http://localhost:8000\n") is False
    assert origin_allowed("http://localhost:8000\r\n") is False


def test_origin_allowed_is_case_insensitive():
    from monitor.control.exec import origin_allowed
    assert origin_allowed("HTTP://LOCALHOST:8000") is True
    assert origin_allowed("HTTPS://ASTRAL-READER.DUCKDNS.ORG") is True
    assert origin_allowed("HTTPS://EVIL.EXAMPLE.COM") is False


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
