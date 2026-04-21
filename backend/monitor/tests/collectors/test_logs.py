"""logs.collect() — slice LOG_DEQUE with optional svc+q filters."""
from datetime import datetime, timezone

import pytest

from monitor.bg import LOG_DEQUE
from monitor.collectors import logs as logs_mod


@pytest.mark.asyncio
async def test_collect_returns_recent_lines():
    LOG_DEQUE.clear()
    for i in range(150):
        LOG_DEQUE.append({
            "ts": datetime(2026, 4, 21, 14, 0, i % 60, tzinfo=timezone.utc),
            "svc": "fastapi" if i % 2 else "nginx",
            "lvl": "info", "msg": f"line {i}",
        })
    lines = await logs_mod.collect(limit=100)
    assert len(lines) == 100
    assert lines[-1].msg == "line 149"


@pytest.mark.asyncio
async def test_collect_filters_by_service():
    LOG_DEQUE.clear()
    for i in range(10):
        LOG_DEQUE.append({
            "ts": datetime(2026, 4, 21, 14, 0, i, tzinfo=timezone.utc),
            "svc": "fastapi" if i % 2 else "redis",
            "lvl": "info", "msg": f"line {i}",
        })
    lines = await logs_mod.collect(limit=100, svc="fastapi")
    assert all(line.svc == "fastapi" for line in lines)


@pytest.mark.asyncio
async def test_collect_filters_by_query():
    LOG_DEQUE.clear()
    LOG_DEQUE.append({
        "ts": datetime(2026, 4, 21, 14, 0, 0, tzinfo=timezone.utc),
        "svc": "fastapi", "lvl": "error",
        "msg": "TimeoutError on /api/v1/x",
    })
    LOG_DEQUE.append({
        "ts": datetime(2026, 4, 21, 14, 0, 1, tzinfo=timezone.utc),
        "svc": "fastapi", "lvl": "info", "msg": "hello",
    })
    lines = await logs_mod.collect(limit=100, q="Timeout")
    assert len(lines) == 1
    assert "Timeout" in lines[0].msg
