"""Thin Redis cache layer with graceful degradation.

Every operation is wrapped in try/except — if Redis is down, the caller
gets None (cache miss) and the app falls through to Postgres as usual.
"""
import logging
from typing import Optional
import redis.asyncio as aioredis
from app.core.config import settings

logger = logging.getLogger(__name__)

_pool: Optional[aioredis.Redis] = None


async def _get_redis() -> aioredis.Redis:
    global _pool
    if _pool is None:
        _pool = await aioredis.from_url(
            settings.redis_url,
            decode_responses=True,
            socket_connect_timeout=2,
            socket_timeout=2,
        )
    return _pool


async def get(key: str) -> Optional[str]:
    """Return cached value or None on miss/error."""
    try:
        r = await _get_redis()
        return await r.get(key)
    except Exception as e:
        logger.debug("cache get failed | key=%s error=%s", key, e)
        return None


async def set(key: str, value: str, ttl: int = 300) -> None:
    """Set a cached value with TTL in seconds. Fire-and-forget."""
    try:
        r = await _get_redis()
        await r.set(key, value, ex=ttl)
    except Exception as e:
        logger.debug("cache set failed | key=%s error=%s", key, e)


async def delete(*keys: str) -> None:
    """Delete one or more cache keys. Fire-and-forget."""
    if not keys:
        return
    try:
        r = await _get_redis()
        await r.delete(*keys)
    except Exception as e:
        logger.debug("cache delete failed | keys=%s error=%s", keys, e)


async def delete_pattern(pattern: str) -> None:
    """Delete all keys matching a glob pattern (e.g. 'comics:*'). Fire-and-forget."""
    try:
        r = await _get_redis()
        cursor = 0
        while True:
            cursor, keys = await r.scan(cursor=cursor, match=pattern, count=100)
            if keys:
                await r.delete(*keys)
            if cursor == 0:
                break
    except Exception as e:
        logger.debug("cache delete_pattern failed | pattern=%s error=%s", pattern, e)


async def invalidate_comics(comic_id: str = None) -> None:
    """Invalidate all comic-related caches. Optionally target a specific comic."""
    await delete_pattern("comics:list:*")
    if comic_id:
        await delete_pattern(f"comic:detail:{comic_id}")
        await delete_pattern(f"chapter_pages:{comic_id}:*")


async def invalidate_fanfics(fanfic_id: str = None) -> None:
    """Invalidate all fanfic-related caches. Optionally target a specific fanfic."""
    await delete_pattern("fanfics:list:*")
    if fanfic_id:
        await delete_pattern(f"fanfic:detail:{fanfic_id}")
        await delete_pattern(f"fanfic_chapter:{fanfic_id}:*")


async def invalidate_progress(content_type: str) -> None:
    """Invalidate progress cache for a content type."""
    await delete(f"progress:{content_type}")


async def invalidate_scrape_jobs() -> None:
    """Invalidate scrape job list and individual job caches."""
    await delete_pattern("scrape:*")
