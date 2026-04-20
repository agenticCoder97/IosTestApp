"""Process-wide Redis singletons for cache reads/writes and ARQ enqueueing.

Both the FastAPI app and the ARQ worker call ``init_pools()`` at startup and
``close_pools()`` at shutdown. Within request/task handlers, use the
``get_cache_redis()`` and ``get_arq()`` accessors — never create ad-hoc
connections via ``aioredis.from_url(...)``.

Why two pools?
- Cache pool uses ``decode_responses=True`` (we deal in JSON strings).
- ARQ pool wraps a different protocol — ARQ stores its own job hashes with
  its internal binary payload format.

Both pools currently point at the same Redis DSN/db. Splitting them onto
separate logical DBs (cache=0, arq=1) is left as a future change — would
require a worker-side DSN bump in lockstep with the API.
"""
from __future__ import annotations

import logging
from typing import Optional

import redis.asyncio as aioredis
from arq import create_pool
from arq.connections import ArqRedis, RedisSettings

from app.core.config import settings

logger = logging.getLogger(__name__)

_cache_redis: Optional[aioredis.Redis] = None
_arq_pool: Optional[ArqRedis] = None


async def init_pools() -> None:
    """Initialize both pools. Idempotent — safe to call multiple times."""
    global _cache_redis, _arq_pool

    if _cache_redis is None:
        _cache_redis = await aioredis.from_url(
            settings.redis_url,
            decode_responses=True,
            socket_connect_timeout=2,
            socket_timeout=2,
        )
        logger.info("Redis cache pool initialized | dsn=%s", settings.redis_url)

    if _arq_pool is None:
        _arq_pool = await create_pool(RedisSettings.from_dsn(settings.redis_url))
        logger.info("ARQ pool initialized | dsn=%s", settings.redis_url)


async def close_pools() -> None:
    """Close both pools and reset module state. Called from app/worker shutdown."""
    global _cache_redis, _arq_pool

    if _cache_redis is not None:
        await _cache_redis.aclose()
        _cache_redis = None
        logger.info("Redis cache pool closed")

    if _arq_pool is not None:
        await _arq_pool.aclose()
        _arq_pool = None
        logger.info("ARQ pool closed")


def get_cache_redis() -> aioredis.Redis:
    """Return the shared cache Redis client. Raises if not yet initialized."""
    if _cache_redis is None:
        raise RuntimeError(
            "Cache Redis pool is not initialized — call init_pools() at startup"
        )
    return _cache_redis


def get_arq() -> ArqRedis:
    """Return the shared ARQ enqueue pool. Raises if not yet initialized."""
    if _arq_pool is None:
        raise RuntimeError(
            "ARQ pool is not initialized — call init_pools() at startup"
        )
    return _arq_pool
