"""Two-layer cache for the monitor service.

Layer 1: in-process dict with monotonic-clock TTL.
Layer 2: Redis (JSON + SETEX). Survives container restarts.

safe() gives every collector a degraded-fallback story.
"""
from __future__ import annotations

import asyncio
import json
import logging
import time
from typing import Any, Awaitable, Callable, Optional

import redis.asyncio as aioredis

logger = logging.getLogger("monitor.cache")

_LAST_GOOD_TTL_S = 86_400


class InProcCache:
    def __init__(self) -> None:
        self._store: dict[str, tuple[float, Any]] = {}

    def get(self, key: str) -> Optional[Any]:
        entry = self._store.get(key)
        if entry is None:
            return None
        expires_at, value = entry
        if time.monotonic() >= expires_at:
            self._store.pop(key, None)
            return None
        return value

    def set(self, key: str, value: Any, ttl: int) -> None:
        self._store[key] = (time.monotonic() + ttl, value)


class RedisCache:
    def __init__(self, redis: aioredis.Redis) -> None:
        self._r = redis

    async def get(self, key: str) -> Optional[Any]:
        raw = await self._r.get(key)
        if raw is None:
            return None
        try:
            return json.loads(raw)
        except (TypeError, ValueError):
            logger.warning("cache.RedisCache: bad JSON at key=%s", key)
            return None

    async def set(self, key: str, value: Any, ttl: int) -> None:
        try:
            await self._r.set(key, json.dumps(value, default=str), ex=ttl)
        except Exception as e:
            logger.debug("cache.RedisCache.set failed key=%s err=%s", key, e)


def _as_jsonable(v: Any) -> Any:
    """Convert pydantic v2 models (and lists of them) into JSON-serializable
    dicts/lists. Fallback ``default=str`` in json.dumps turns a pydantic
    BaseModel into its ``str()`` repr (e.g. ``"currency='USD' ..."``), which
    round-trips back as a string and fails the /metrics schema validation."""
    if hasattr(v, "model_dump"):
        return v.model_dump(mode="json", by_alias=True)
    if isinstance(v, list):
        return [_as_jsonable(x) for x in v]
    if isinstance(v, dict):
        return {k: _as_jsonable(x) for k, x in v.items()}
    return v


async def set_last_good(redis: aioredis.Redis, name: str, value: Any) -> None:
    try:
        await redis.set(
            f"mon:last_good:{name}",
            json.dumps(_as_jsonable(value), default=str),
            ex=_LAST_GOOD_TTL_S,
        )
    except Exception as e:
        logger.debug("set_last_good failed name=%s err=%s", name, e)


async def get_last_good(redis: aioredis.Redis, name: str) -> Optional[Any]:
    try:
        raw = await redis.get(f"mon:last_good:{name}")
        if raw is None:
            return None
        return json.loads(raw)
    except Exception as e:
        logger.debug("get_last_good failed name=%s err=%s", name, e)
        return None


async def safe(
    coll: Callable[[], Awaitable[Any]],
    name: str,
    *,
    redis: Optional[aioredis.Redis] = None,
    timeout: float = 2.0,
    fallback: Any = None,
) -> tuple[Any, Optional[dict]]:
    """Call coll() under a timeout; on failure fall back to last-known-good."""
    try:
        data = await asyncio.wait_for(coll(), timeout)
        if redis is not None:
            await set_last_good(redis, name, data)
        return data, None
    except asyncio.TimeoutError:
        reason = f"timeout after {timeout}s"
    except Exception as e:
        reason = f"{type(e).__name__}: {e}"[:120]
        logger.warning("collector %s failed: %s", name, reason)

    last = await get_last_good(redis, name) if redis is not None else None
    data_out = last if last is not None else fallback
    meta = {
        "degraded": True,
        "reason": reason,
        "last_good": _maybe_iso(last.get("generated_at") if isinstance(last, dict) else None),
    }
    return data_out, meta


def _maybe_iso(v: Any) -> Optional[str]:
    if v is None:
        return None
    if isinstance(v, str):
        return v
    if hasattr(v, "isoformat"):
        return v.isoformat()
    return str(v)


# ── module-level redis handle, set by main.lifespan ────────────────────

_REDIS: Optional[aioredis.Redis] = None


def set_redis(r: aioredis.Redis) -> None:
    global _REDIS
    _REDIS = r


def get_cache_redis_or_none() -> Optional[aioredis.Redis]:
    return _REDIS


def get_cache_redis() -> aioredis.Redis:
    if _REDIS is None:
        raise RuntimeError("monitor redis not initialized — call set_redis() in lifespan")
    return _REDIS
