"""arq.collect() — pulls queue + in-flight + recent from Redis."""
import json
import time

import pytest
from fakeredis import FakeAsyncRedis

from monitor.collectors import arq as arq_mod


@pytest.mark.asyncio
async def test_collect_empty_queue(monkeypatch):
    r = FakeAsyncRedis(decode_responses=True)
    monkeypatch.setattr(arq_mod, "get_cache_redis", lambda: r)
    block = await arq_mod.collect()
    assert block.queue_depth == 0
    assert block.in_flight == 0
    assert block.active == []


@pytest.mark.asyncio
async def test_collect_populated_queue(monkeypatch):
    r = FakeAsyncRedis(decode_responses=True)
    for i in range(3):
        await r.zadd("arq:queue", {f"job_{i}": time.time() * 1000 + i})

    await r.hset(
        "arq:in_progress:job_inflight",
        mapping={"function": "scrape_chapter", "enqueue_time": int(time.time() * 1000 - 70_000)},
    )
    await r.set(
        "arq:job:job_inflight",
        json.dumps({
            "function": "scrape_chapter",
            "args": ["ao3:55312041/ch3"],
            "kwargs": {},
            "enqueue_time": int(time.time() * 1000 - 70_000),
        }),
    )

    monkeypatch.setattr(arq_mod, "get_cache_redis", lambda: r)

    block = await arq_mod.collect()
    assert block.queue_depth == 3
    assert block.in_flight == 1
    assert len(block.active) == 1
