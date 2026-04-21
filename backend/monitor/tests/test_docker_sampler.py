"""docker_sampler — single-tick population of SERVICE_CACHE."""
from unittest.mock import AsyncMock, MagicMock

import pytest

from monitor.bg import SERVICE_CACHE, _sample_once


def _fake_container(name):
    c = MagicMock()
    c.name = f"backend-{name}-1"
    c.labels = {"com.docker.compose.service": name}
    c.short_id = "abc123def456"
    c.image.tags = [f"{name}:latest"]
    c.attrs = {"State": {
        "Status": "running",
        "Health": {"Status": "healthy"},
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
        "memory_stats": {"usage": 412_000_000, "stats": {"cache": 10_000_000}},
    }
    return c


@pytest.mark.asyncio
async def test_sample_once_populates_all_six_services():
    SERVICE_CACHE.clear()
    client = MagicMock()
    client.containers.list.return_value = [
        _fake_container(n) for n in (
            "postgres", "redis", "fastapi", "arq_worker", "nginx", "certbot"
        )
    ]

    redis = MagicMock()
    redis.zadd = AsyncMock(return_value=1)
    redis.zremrangebyscore = AsyncMock(return_value=0)

    await _sample_once(client, redis)

    assert set(SERVICE_CACHE.keys()) == {
        "postgres", "redis", "fastapi", "arq_worker", "nginx", "certbot"
    }
    fastapi = SERVICE_CACHE["fastapi"]
    assert fastapi["status"] == "up"
    assert fastapi["health"] == "healthy"
    assert fastapi["cpu_pct"] > 0
