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
