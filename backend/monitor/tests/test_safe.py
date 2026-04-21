"""safe() wrapper — passes through on success; degraded on timeout/exception."""
import asyncio

import pytest
from fakeredis import FakeAsyncRedis

from monitor.cache import safe


@pytest.mark.asyncio
async def test_safe_passes_through_on_success():
    r = FakeAsyncRedis(decode_responses=True)

    async def ok():
        return {"value": 1}

    data, meta = await safe(ok, "ok_collector", redis=r, timeout=1.0)
    assert data == {"value": 1}
    assert meta is None


@pytest.mark.asyncio
async def test_safe_marks_degraded_on_timeout():
    r = FakeAsyncRedis(decode_responses=True)

    async def hang():
        await asyncio.sleep(5)

    data, meta = await safe(hang, "slow", redis=r, timeout=0.05, fallback={"x": 0})
    assert data == {"x": 0}
    assert meta is not None and meta["degraded"] is True
    assert "timeout" in meta["reason"].lower()


@pytest.mark.asyncio
async def test_safe_marks_degraded_on_exception():
    r = FakeAsyncRedis(decode_responses=True)

    async def boom():
        raise RuntimeError("nope")

    data, meta = await safe(boom, "broken", redis=r, timeout=1.0, fallback={"x": 0})
    assert data == {"x": 0}
    assert meta is not None and meta["degraded"] is True
    assert "nope" in meta["reason"]


@pytest.mark.asyncio
async def test_safe_uses_last_good_when_available():
    from monitor.cache import set_last_good

    r = FakeAsyncRedis(decode_responses=True)
    await set_last_good(r, "flaky", {"cached_value": 7})

    async def boom():
        raise RuntimeError("temporary")

    data, meta = await safe(boom, "flaky", redis=r, timeout=1.0, fallback={"cached_value": 0})
    assert data == {"cached_value": 7}
    assert meta["degraded"] is True
