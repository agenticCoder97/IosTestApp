"""_sample_once synthesizes health='healthy' when container is running but
has no Docker healthcheck defined."""
from unittest.mock import AsyncMock, MagicMock

import pytest

from monitor.bg import SERVICE_CACHE, _sample_once


def _container(name, status="running", health_status=None):
    c = MagicMock()
    c.name = f"backend-{name}-1"
    c.labels = {"com.docker.compose.service": name}
    c.short_id = "abc123def456"
    c.image.tags = [f"{name}:latest"]
    c.attrs = {"State": {
        "Status": status,
        "Health": {"Status": health_status} if health_status else None,
        "StartedAt": "2026-04-21T10:00:00.0Z",
    }}
    c.stats.return_value = {
        "cpu_stats": {
            "cpu_usage": {"total_usage": 2_000_000_000},
            "system_cpu_usage": 100_000_000_000,
            "online_cpus": 4,
        },
        "precpu_stats": {
            "cpu_usage": {"total_usage": 1_000_000_000},
            "system_cpu_usage": 90_000_000_000,
        },
        "memory_stats": {"usage": 100_000_000, "stats": {"cache": 0}},
    }
    return c


@pytest.mark.asyncio
async def test_running_without_healthcheck_gets_healthy(monkeypatch):
    SERVICE_CACHE.clear()
    async def _noop(*args, **kwargs):
        return {}
    monkeypatch.setattr("monitor.bg._fetch_service_extra", _noop)

    client = MagicMock()
    client.containers.list.return_value = [
        _container("redis", status="running", health_status=None),
    ]
    redis = MagicMock()
    redis.zadd = AsyncMock(return_value=1)
    redis.zremrangebyscore = AsyncMock(return_value=0)

    await _sample_once(client, redis)
    assert SERVICE_CACHE["redis"]["health"] == "healthy"


@pytest.mark.asyncio
async def test_real_healthcheck_status_preserved(monkeypatch):
    SERVICE_CACHE.clear()
    async def _noop(*args, **kwargs):
        return {}
    monkeypatch.setattr("monitor.bg._fetch_service_extra", _noop)

    client = MagicMock()
    client.containers.list.return_value = [
        _container("postgres", status="running", health_status="healthy"),
        _container("fastapi",  status="running", health_status="unhealthy"),
    ]
    redis = MagicMock()
    redis.zadd = AsyncMock(return_value=1)
    redis.zremrangebyscore = AsyncMock(return_value=0)

    await _sample_once(client, redis)
    assert SERVICE_CACHE["postgres"]["health"] == "healthy"
    assert SERVICE_CACHE["fastapi"]["health"] == "unhealthy"


@pytest.mark.asyncio
async def test_stopped_container_stays_none(monkeypatch):
    SERVICE_CACHE.clear()
    async def _noop(*args, **kwargs):
        return {}
    monkeypatch.setattr("monitor.bg._fetch_service_extra", _noop)

    client = MagicMock()
    client.containers.list.return_value = [
        _container("arq_worker", status="exited", health_status=None),
    ]
    redis = MagicMock()
    redis.zadd = AsyncMock(return_value=1)
    redis.zremrangebyscore = AsyncMock(return_value=0)

    await _sample_once(client, redis)
    assert SERVICE_CACHE["arq_worker"]["health"] is None
