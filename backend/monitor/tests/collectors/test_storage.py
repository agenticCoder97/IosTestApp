"""storage.collect() — statvfs + du + pg_database_size + OCI head."""
from unittest.mock import MagicMock

import pytest
from fakeredis import FakeAsyncRedis

from monitor.collectors import storage as storage_mod


@pytest.mark.asyncio
async def test_collect_assembles_from_all_sources(monkeypatch):
    fake_stat = MagicMock()
    fake_stat.f_frsize = 4096
    fake_stat.f_blocks = 39_322_624
    fake_stat.f_bavail = 4_165_352
    monkeypatch.setattr(storage_mod.os, "statvfs", lambda _p: fake_stat)

    async def _du(_path):
        return 142_000_000_000

    monkeypatch.setattr(storage_mod, "_du_bytes", _du)

    async def _pg(_pool):
        return 2_147_483_648

    monkeypatch.setattr(storage_mod, "_pg_db_size", _pg)

    async def _os_head():
        return {"bucket": "astral-backups", "used_bytes": 3_650_000_000, "tier": "standard"}

    monkeypatch.setattr(storage_mod, "_object_storage_head", _os_head)
    monkeypatch.setattr(storage_mod, "get_cache_redis", lambda: FakeAsyncRedis(decode_responses=True))
    monkeypatch.setattr(storage_mod, "get_pg_pool_or_none", lambda: None)

    block = await storage_mod.collect()
    assert block.postgres_bytes == 2_147_483_648
    assert block.media_bytes == 142_000_000_000
    assert block.block_vol.total_bytes == 4096 * 39_322_624
    assert block.object_storage.bucket == "astral-backups"


@pytest.mark.asyncio
async def test_collect_tolerates_missing_pg(monkeypatch):
    fake_stat = MagicMock(f_frsize=4096, f_blocks=1000, f_bavail=500)
    monkeypatch.setattr(storage_mod.os, "statvfs", lambda _p: fake_stat)

    async def _du(_path):
        return 0

    async def _none():
        return None

    monkeypatch.setattr(storage_mod, "_du_bytes", _du)
    monkeypatch.setattr(storage_mod, "_object_storage_head", _none)
    monkeypatch.setattr(storage_mod, "get_pg_pool_or_none", lambda: None)
    monkeypatch.setattr(storage_mod, "get_cache_redis", lambda: FakeAsyncRedis(decode_responses=True))

    block = await storage_mod.collect()
    assert block.postgres_bytes is None
