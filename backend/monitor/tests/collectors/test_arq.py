"""arq.collect() — pulls queue + in-flight + recent from Redis.

Uses arq's own serialize helpers to build fixtures so the tests exercise
the same schema the real worker writes. The pre-AST-58 version of these
tests built JSON fixtures against `arq:in_progress:` (underscore), which
silently hid two bugs in the collector: wrong key prefix (real ARQ uses
hyphen) and wrong serializer assumption.

Two fake redises are monkeypatched: the decode-mode client (for queue
depth + key scans) and the bytes-mode client (for arq:job:* /
arq:result:* payload reads).
"""
import time
from datetime import datetime, timezone

import pytest
from arq.jobs import serialize_job, serialize_result
from fakeredis import FakeAsyncRedis

from monitor.collectors import arq as arq_mod


def _patch(monkeypatch):
    r = FakeAsyncRedis(decode_responses=True)
    rb = FakeAsyncRedis(decode_responses=False, server=r.connection_pool.connection_kwargs.get("server"))
    # fakeredis shares state via the default server when no server= is given,
    # but we still want both views to see the same keyspace — use one backing
    # server instance explicitly.
    from fakeredis import FakeServer
    srv = FakeServer()
    r = FakeAsyncRedis(decode_responses=True, server=srv)
    rb = FakeAsyncRedis(decode_responses=False, server=srv)
    monkeypatch.setattr(arq_mod, "get_cache_redis", lambda: r)
    monkeypatch.setattr(arq_mod, "_get_bytes_client", lambda: rb)
    return r, rb


@pytest.mark.asyncio
async def test_collect_empty_queue(monkeypatch):
    _patch(monkeypatch)
    block = await arq_mod.collect()
    assert block.queue_depth == 0
    assert block.in_flight == 0
    assert block.active == []
    assert block.completed_24h == 0
    assert block.failed_24h == 0


@pytest.mark.asyncio
async def test_collect_populated_queue(monkeypatch):
    r, rb = _patch(monkeypatch)

    # 3 jobs pending in the default queue
    for i in range(3):
        await r.zadd("arq:queue", {f"job_{i}": time.time() * 1000 + i})

    # 1 job in-flight — real ARQ key prefix is `arq:in-progress:` (hyphen)
    now_ms = int(time.time() * 1000)
    enq_ms = now_ms - 70_000
    await r.set("arq:in-progress:job_inflight", "1", ex=60)
    raw_job = serialize_job(
        function_name="scrape_chapter",
        args=("ao3:55312041/ch3",),
        kwargs={},
        job_try=1,
        enqueue_time_ms=enq_ms,
        serializer=None,
    )
    await rb.set("arq:job:job_inflight", raw_job)

    block = await arq_mod.collect()
    assert block.queue_depth == 3
    assert block.in_flight == 1
    assert len(block.active) == 1
    job = block.active[0]
    assert job.fn == "scrape_chapter"
    assert job.target == "ao3:55312041/ch3"
    assert job.source == "ao3"
    assert job.elapsed_s >= 70


@pytest.mark.asyncio
async def test_collect_recent_completed_and_failed(monkeypatch):
    r, rb = _patch(monkeypatch)
    now = datetime.now(timezone.utc)
    now_ms = int(now.timestamp() * 1000)

    ok = serialize_result(
        function="scrape_chapter",
        args=("ao3:1/ch1",),
        kwargs={},
        job_try=1,
        enqueue_time_ms=now_ms - 10_000,
        success=True,
        result={"pages": 18},
        start_ms=now_ms - 9_000,
        finished_ms=now_ms - 1_000,
        ref="ref",
        queue_name="arq:queue",
        job_id="ok_job",
        serializer=None,
    )
    bad = serialize_result(
        function="scrape_chapter",
        args=("ffnet:2/ch1",),
        kwargs={},
        job_try=2,
        enqueue_time_ms=now_ms - 20_000,
        success=False,
        result=RuntimeError("upstream 503"),
        start_ms=now_ms - 19_000,
        finished_ms=now_ms - 2_000,
        ref="ref",
        queue_name="arq:queue",
        job_id="bad_job",
        serializer=None,
    )
    await rb.set("arq:result:ok_job", ok)
    await rb.set("arq:result:bad_job", bad)

    block = await arq_mod.collect()
    assert block.completed_24h == 1
    assert block.failed_24h == 1
    assert len(block.recent_completed) == 1
    assert block.recent_completed[0].source == "ao3"
    assert len(block.recent_failed) == 1
    assert block.recent_failed[0].source == "ffnet"
    assert "upstream 503" in block.recent_failed[0].error
