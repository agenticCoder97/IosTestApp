"""services.collect() reads SERVICE_CACHE."""
import pytest

from monitor.bg import SERVICE_CACHE
from monitor.collectors.services import collect


@pytest.mark.asyncio
async def test_collect_returns_all_populated_services():
    SERVICE_CACHE.clear()
    SERVICE_CACHE["postgres"] = {
        "name": "postgres", "image": "postgres:16-alpine",
        "container_id": "abc", "status": "up", "health": "healthy",
        "uptime_s": 1000, "cpu_pct": 2.4, "mem_mb": 412.0, "restarts": 0,
        "extra": {}, "spark_cpu": [1.0, 1.5, 2.0],
    }
    blocks = await collect()
    assert len(blocks) == 1
    assert blocks[0].name == "postgres"
    assert blocks[0].cpu_pct == 2.4


@pytest.mark.asyncio
async def test_collect_returns_empty_when_cache_empty():
    SERVICE_CACHE.clear()
    blocks = await collect()
    assert blocks == []
