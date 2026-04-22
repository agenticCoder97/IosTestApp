"""On-demand pg_dump via docker exec postgres.

The monitor does not bundle the postgres client, so we invoke
`pg_dump` inside the postgres container and copy the resulting file
onto the monitor's state volume. One concurrent run enforced by an
in-process lock.
"""
from __future__ import annotations

import asyncio
import logging
import os
import time
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from monitor.control import docker_ops
from monitor.control.audit import STATE_DIR

logger = logging.getLogger("monitor.control.backup")

BACKUP_DIR = STATE_DIR / "backups"
_POSTGRES_SVC = "postgres"

_PG_USER = os.getenv("POSTGRES_USER", "astral")
_PG_DB = os.getenv("POSTGRES_DB", "astral")


@dataclass
class BackupJob:
    job_id: str
    started_at: float                              # monotonic
    started_iso: str
    status: str = "running"                        # running | done | failed
    path: Optional[str] = None
    size_bytes: int = 0
    duration_s: int = 0
    error: Optional[str] = None
    extras: dict = field(default_factory=dict)


_JOBS: dict[str, BackupJob] = {}
_LOCK = asyncio.Lock()


def _filename() -> str:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return f"astral-{stamp}.dump"


async def start_backup() -> BackupJob:
    if _LOCK.locked():
        raise RuntimeError("backup already in progress")
    await _LOCK.acquire()
    job = BackupJob(
        job_id=f"bkp-{uuid.uuid4().hex[:12]}",
        started_at=time.monotonic(),
        started_iso=datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    )
    _JOBS[job.job_id] = job
    asyncio.create_task(_run_backup(job))
    return job


async def _run_backup(job: BackupJob) -> None:
    try:
        BACKUP_DIR.mkdir(parents=True, exist_ok=True)
        fname = _filename()

        # pg_dump writes to stdout inside the container; we capture
        # the exec output and spill to a file on the state volume.
        # -Fc gives compact custom format suitable for pg_restore.
        result = await docker_ops.exec_in_container(
            _POSTGRES_SVC,
            ["pg_dump", "-U", _PG_USER, "-d", _PG_DB, "-Fc"],
            timeout_s=600.0,
        )
        if result["exit_code"] != 0:
            raise RuntimeError(
                f"pg_dump exit {result['exit_code']}: {result['stderr'][:200]}"
            )
        out_path = BACKUP_DIR / fname
        # exec stdout is decoded text; the custom format is binary.
        # To preserve bytes, re-encode latin-1 which round-trips
        # 0-255 bytes losslessly (pg_dump -Fc is raw binary).
        out_path.write_bytes(result["stdout"].encode("latin-1"))
        job.path = str(out_path)
        job.size_bytes = out_path.stat().st_size
        job.status = "done"
    except Exception as e:
        logger.exception("backup failed job=%s", job.job_id)
        job.status = "failed"
        job.error = str(e)[:200]
    finally:
        job.duration_s = int(time.monotonic() - job.started_at)
        if _LOCK.locked():
            _LOCK.release()


def get_job(job_id: str) -> Optional[BackupJob]:
    return _JOBS.get(job_id)


def latest_backup_path() -> Optional[Path]:
    if not BACKUP_DIR.exists():
        return None
    dumps = sorted(BACKUP_DIR.glob("astral-*.dump"), key=lambda p: p.stat().st_mtime, reverse=True)
    return dumps[0] if dumps else None
