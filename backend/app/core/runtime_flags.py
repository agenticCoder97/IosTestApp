"""Runtime flag resolver with Redis override.

The monitor dashboard (AST-70) writes flag overrides to Redis at
`mon:flag:<KEY>` as JSON `{"value": bool, ...}`. This helper lets
the backend / ARQ worker read the override with a fallback to the
settings-level default.

Usage — async:
    if await flag_enabled("MANGADEX_DISABLED", default=settings.mangadex_disabled):
        ...

Usage — sync (scraper entrypoints, no event loop):
    if flag_enabled_sync("FFNET_NEW_SCRAPER_DISABLED", default=settings.ffnet_new_scraper_disabled):
        ...

Cache: values are cached in-process for 5 seconds so tight scraper
loops don't hammer Redis. Clear with `clear_flag_cache()` in tests.
"""
from __future__ import annotations

import json
import logging
import os
import time
from typing import Optional

import redis
import redis.asyncio as aioredis

logger = logging.getLogger("astral.runtime_flags")

_REDIS_URL = os.getenv("REDIS_URL", "redis://redis:6379/0")
_CACHE_TTL_S = 5.0

_async_client: Optional[aioredis.Redis] = None
_sync_client: Optional[redis.Redis] = None
_cache: dict[str, tuple[float, Optional[bool]]] = {}


def _get_async_client() -> aioredis.Redis:
    global _async_client
    if _async_client is None:
        _async_client = aioredis.from_url(
            _REDIS_URL, decode_responses=True, socket_connect_timeout=1.0,
        )
    return _async_client


def _get_sync_client() -> redis.Redis:
    global _sync_client
    if _sync_client is None:
        _sync_client = redis.Redis.from_url(
            _REDIS_URL, decode_responses=True, socket_connect_timeout=1.0,
        )
    return _sync_client


def _cached(key: str) -> Optional[bool]:
    entry = _cache.get(key)
    if entry is None:
        return None
    ts, val = entry
    if time.monotonic() - ts > _CACHE_TTL_S:
        return None
    return val


def _store(key: str, value: Optional[bool]) -> None:
    _cache[key] = (time.monotonic(), value)


def _parse(raw: Optional[str]) -> Optional[bool]:
    if not raw:
        return None
    try:
        data = json.loads(raw)
    except (TypeError, ValueError):
        return None
    if isinstance(data, dict) and "value" in data:
        return bool(data["value"])
    return None


async def flag_enabled(key: str, *, default: bool) -> bool:
    cached = _cached(key)
    if cached is not None:
        return cached
    try:
        raw = await _get_async_client().get(f"mon:flag:{key}")
        parsed = _parse(raw)
    except Exception as e:
        logger.debug("flag async fetch failed key=%s err=%s", key, e)
        parsed = None
    value = parsed if parsed is not None else default
    _store(key, value)
    return value


def flag_enabled_sync(key: str, *, default: bool) -> bool:
    cached = _cached(key)
    if cached is not None:
        return cached
    try:
        raw = _get_sync_client().get(f"mon:flag:{key}")
        parsed = _parse(raw if isinstance(raw, (str, type(None))) else None)
    except Exception as e:
        logger.debug("flag sync fetch failed key=%s err=%s", key, e)
        parsed = None
    value = parsed if parsed is not None else default
    _store(key, value)
    return value


def clear_flag_cache() -> None:
    _cache.clear()
