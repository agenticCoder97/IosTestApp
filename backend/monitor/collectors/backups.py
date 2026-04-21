"""backups collector — list the astral-backups bucket (AST-51).

Cron: weekly Sunday 03:00 UTC. next_run_in_s computed from current time.
status = 'ok' if a dump exists <=10d old, 'stale' otherwise.
"""
from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timedelta, timezone

from monitor.schema import BackupRun, BackupsBlock

logger = logging.getLogger("monitor.backups")

_BUCKET = "astral-backups"
_RETENTION_DAYS = 56
_STALE_AFTER_DAYS = 10


def _NOW() -> datetime:
    return datetime.now(timezone.utc)


async def collect() -> BackupsBlock:
    objects = await _list_bucket()
    objects = sorted(objects, key=lambda o: o.time_created, reverse=True)

    now = _NOW()

    recent_runs = [
        BackupRun(
            started=o.time_created,
            duration_s=0,
            size_bytes=int(o.size or 0),
            status="ok",
        )
        for o in objects[:10]
    ]

    if not objects:
        last_dump = None
        last_size = None
        status = "stale"
    else:
        last_dump = objects[0].time_created
        last_size = int(objects[0].size or 0)
        age_days = (now - last_dump).total_seconds() / 86400
        status = "ok" if age_days <= _STALE_AFTER_DAYS else "stale"

    return BackupsBlock(
        last_pg_dump=last_dump,
        last_size_bytes=last_size,
        status=status,
        next_run_in_s=_seconds_until_next_sunday_3am(now),
        bucket=_BUCKET,
        retention_days=_RETENTION_DAYS,
        recent_runs=recent_runs,
    )


def _seconds_until_next_sunday_3am(now: datetime) -> int:
    days_ahead = (6 - now.weekday()) % 7
    target = (now + timedelta(days=days_ahead)).replace(hour=3, minute=0, second=0, microsecond=0)
    if target <= now:
        target += timedelta(days=7)
    return int((target - now).total_seconds())


async def _list_bucket():
    def _sync():
        import oci
        signer = oci.auth.signers.InstancePrincipalsSecurityTokenSigner()
        client = oci.object_storage.ObjectStorageClient(config={}, signer=signer)
        ns = client.get_namespace().data
        out = client.list_objects(ns, _BUCKET, fields="name,size,timeCreated", limit=1000)
        return out.data.objects or []

    return await asyncio.to_thread(_sync)
