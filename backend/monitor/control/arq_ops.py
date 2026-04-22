"""Re-enqueue failed ARQ jobs from the monitor dashboard.

Reads the serialized job tuple from `arq:job:<id>` or the result at
`arq:result:<id>` and pushes a fresh copy into `arq:queue` with a new
job_id. Uses arq's own pool to preserve serializer settings.
"""
from __future__ import annotations

import logging
import os
import uuid

from arq import create_pool
from arq.connections import RedisSettings
from arq.jobs import deserialize_job_raw, deserialize_result

from monitor.control.arq_bytes import get_bytes_client

logger = logging.getLogger("monitor.control.arq")

_REDIS_URL = os.getenv("REDIS_URL", "redis://redis:6379/0")


def _settings_from_url(url: str) -> RedisSettings:
    from urllib.parse import urlparse
    u = urlparse(url)
    return RedisSettings(
        host=u.hostname or "redis",
        port=u.port or 6379,
        database=int((u.path or "/0").lstrip("/") or 0),
        password=u.password,
    )


async def retry_failed_job(job_id: str) -> dict:
    """Read the failed job's payload and enqueue a fresh copy."""
    rb = get_bytes_client()

    # Prefer arq:job:* (still has original args); fall back to arq:result:*
    raw_job = await rb.get(f"arq:job:{job_id}")
    if raw_job:
        fn, args, kwargs, _job_try, _enq_ms = deserialize_job_raw(raw_job)
    else:
        raw_res = await rb.get(f"arq:result:{job_id}")
        if not raw_res:
            raise LookupError(f"job {job_id} not found in arq:job:* or arq:result:*")
        jr = deserialize_result(raw_res)
        if jr.success:
            raise ValueError("only failed jobs can be retried")
        fn, args, kwargs = jr.function, jr.args, jr.kwargs

    new_job_id = f"retry-{uuid.uuid4().hex[:16]}"
    pool = await create_pool(_settings_from_url(_REDIS_URL))
    try:
        new_job = await pool.enqueue_job(fn, *args, _job_id=new_job_id, **(kwargs or {}))
    finally:
        await pool.close()

    return {
        "original_job_id": job_id,
        "new_job_id": new_job.job_id if new_job else new_job_id,
        "function": fn,
    }
