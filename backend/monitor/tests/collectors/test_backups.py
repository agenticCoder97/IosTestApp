"""backups.collect() — list astral-backups bucket."""
from datetime import datetime, timezone
from unittest.mock import MagicMock

import pytest

from monitor.collectors import backups as bk_mod


def _obj(name, size, time_created):
    o = MagicMock()
    o.name = name
    o.size = size
    o.time_created = time_created
    return o


@pytest.mark.asyncio
async def test_collect_parses_recent_runs(monkeypatch):
    async def _list():
        return [
            _obj("pg_dump_20260420_030012.sql.gz", 2_050_000_000,
                 datetime(2026, 4, 20, 3, 0, 42, tzinfo=timezone.utc)),
            _obj("pg_dump_20260413_030005.sql.gz", 2_010_000_000,
                 datetime(2026, 4, 13, 3, 0, 38, tzinfo=timezone.utc)),
        ]

    monkeypatch.setattr(bk_mod, "_list_bucket", _list)
    monkeypatch.setattr(bk_mod, "_NOW", lambda: datetime(2026, 4, 21, 10, 0, 0, tzinfo=timezone.utc))

    block = await bk_mod.collect()
    assert block.bucket == "astral-backups"
    assert block.last_size_bytes == 2_050_000_000
    assert block.status == "ok"
    assert len(block.recent_runs) == 2
    assert block.retention_days == 56


@pytest.mark.asyncio
async def test_collect_marks_stale_when_no_recent(monkeypatch):
    async def _list():
        return [_obj("pg_dump_20260301_030000.sql.gz", 1_000_000_000,
                     datetime(2026, 3, 1, 3, 0, 0, tzinfo=timezone.utc))]

    monkeypatch.setattr(bk_mod, "_list_bucket", _list)
    monkeypatch.setattr(bk_mod, "_NOW", lambda: datetime(2026, 4, 21, 10, 0, 0, tzinfo=timezone.utc))

    block = await bk_mod.collect()
    assert block.status == "stale"


@pytest.mark.asyncio
async def test_collect_empty_bucket_stale(monkeypatch):
    async def _list():
        return []

    monkeypatch.setattr(bk_mod, "_list_bucket", _list)
    monkeypatch.setattr(bk_mod, "_NOW", lambda: datetime(2026, 4, 21, 10, 0, 0, tzinfo=timezone.utc))

    block = await bk_mod.collect()
    assert block.status == "stale"
    assert block.last_pg_dump is None
