"""Shared bytes-mode Redis client for arq serializer reads.

Duplicated previously in collectors/arq.py; lifted here so control
endpoints can reuse the same cached connection rather than opening a
new handshake per call.
"""
from __future__ import annotations

import os

import redis.asyncio as aioredis

_REDIS_URL = os.getenv("REDIS_URL", "redis://redis:6379/0")
_client: aioredis.Redis | None = None


def get_bytes_client() -> aioredis.Redis:
    global _client
    if _client is None:
        _client = aioredis.from_url(
            _REDIS_URL, decode_responses=False, socket_connect_timeout=2,
        )
    return _client
