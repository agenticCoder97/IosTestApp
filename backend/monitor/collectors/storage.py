"""storage collector — statvfs + du + pg_database_size + OCI Object Storage."""
from __future__ import annotations

import asyncio
import logging
import os
from typing import Optional

from monitor.cache import get_cache_redis
from monitor.schema import BlockVolStorage, ObjectStorage, StorageBlock, StorageTrend

logger = logging.getLogger("monitor.storage")

MEDIA_DIR = "/mnt/astral-media"

_pg_pool_handle = None


def set_pg_pool(pool) -> None:
    global _pg_pool_handle
    _pg_pool_handle = pool


def get_pg_pool_or_none():
    return _pg_pool_handle


async def collect() -> StorageBlock:
    pg_bytes = await _pg_db_size(get_pg_pool_or_none())
    media_bytes = await _du_bytes(MEDIA_DIR)
    block_vol = _statvfs_block(MEDIA_DIR)
    obj = await _object_storage_head()
    trend = await _trend_7d()

    return StorageBlock(
        postgres_bytes=pg_bytes,
        media_bytes=media_bytes,
        block_vol=block_vol,
        object_storage=ObjectStorage(**obj) if obj else None,
        trend_7d=trend,
    )


def _statvfs_block(path: str) -> Optional[BlockVolStorage]:
    try:
        s = os.statvfs(path)
        total = s.f_blocks * s.f_frsize
        free = s.f_bavail * s.f_frsize
        used = total - free
        return BlockVolStorage(
            total_bytes=total, used_bytes=used, free_bytes=free, mount=path,
        )
    except Exception as e:
        logger.debug("statvfs %s failed: %s", path, e)
        return None


async def _du_bytes(path: str) -> Optional[int]:
    try:
        proc = await asyncio.create_subprocess_exec(
            "du", "-sb", path,
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL,
        )
        out, _ = await asyncio.wait_for(proc.communicate(), timeout=8.0)
        return int(out.split(b"\t", 1)[0])
    except Exception as e:
        logger.debug("du -sb %s failed: %s", path, e)
        return None


async def _pg_db_size(pool) -> Optional[int]:
    if pool is None:
        return None
    try:
        async with pool.acquire() as conn:
            row = await conn.fetchrow("SELECT pg_database_size(current_database()) AS b")
            return int(row["b"]) if row else None
    except Exception as e:
        logger.debug("pg_database_size failed: %s", e)
        return None


async def _object_storage_head() -> Optional[dict]:
    try:
        import oci
        signer = oci.auth.signers.InstancePrincipalsSecurityTokenSigner()
        client = oci.object_storage.ObjectStorageClient(config={}, signer=signer)
        namespace = client.get_namespace().data
        resp = client.get_bucket(namespace, "astral-backups")
        used = resp.data.approximate_size or 0
        return {"bucket": "astral-backups", "used_bytes": int(used), "tier": "standard"}
    except Exception as e:
        logger.debug("object_storage_head failed: %s", e)
        return None


async def _trend_7d() -> StorageTrend:
    r = get_cache_redis()

    async def _z(key):
        try:
            members = await r.zrange(key, 0, -1)
            return [int(float(m)) for m in members]
        except Exception:
            return []

    pg = await _z("mon:sparkline:storage:postgres")
    media = await _z("mon:sparkline:storage:media")
    free = await _z("mon:sparkline:storage:block_free")
    obj = await _z("mon:sparkline:storage:object_used")
    return StorageTrend(
        postgres=pg or [0],
        media=media or [0],
        block_free=free or [0],
        object_used=obj or [0],
    )
