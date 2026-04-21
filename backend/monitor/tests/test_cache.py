"""Two-layer cache: in-proc TTL eviction + Redis roundtrip via fakeredis."""
import pytest
from fakeredis import FakeAsyncRedis

from monitor.cache import InProcCache, RedisCache, set_last_good, get_last_good


@pytest.mark.asyncio
async def test_inproc_cache_returns_miss_until_set():
    c = InProcCache()
    assert c.get("k") is None
    c.set("k", "v", ttl=60)
    assert c.get("k") == "v"


@pytest.mark.asyncio
async def test_inproc_cache_evicts_after_ttl(monkeypatch):
    c = InProcCache()
    now = [1000.0]
    monkeypatch.setattr("monitor.cache.time.monotonic", lambda: now[0])
    c.set("k", "v", ttl=10)
    now[0] = 1005.0
    assert c.get("k") == "v"
    now[0] = 1011.0
    assert c.get("k") is None


@pytest.mark.asyncio
async def test_redis_cache_roundtrip():
    r = FakeAsyncRedis(decode_responses=True)
    c = RedisCache(r)
    await c.set("mon:k", {"a": 1, "b": [1, 2, 3]}, ttl=60)
    got = await c.get("mon:k")
    assert got == {"a": 1, "b": [1, 2, 3]}


@pytest.mark.asyncio
async def test_redis_cache_returns_none_on_miss():
    r = FakeAsyncRedis(decode_responses=True)
    c = RedisCache(r)
    assert await c.get("mon:missing") is None


@pytest.mark.asyncio
async def test_last_good_roundtrip():
    r = FakeAsyncRedis(decode_responses=True)
    payload = {"foo": "bar", "n": 42}
    await set_last_good(r, "cost", payload)
    assert await get_last_good(r, "cost") == payload
