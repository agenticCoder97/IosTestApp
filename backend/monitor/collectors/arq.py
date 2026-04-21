"""arq collector — introspect ARQ state from Redis.

ARQ 0.26 key schema (from arq.constants):
  arq:queue                 ZSET  pending job IDs (score = scheduled ts ms)
  arq:in-progress:{job_id}  STR   TTL lock while a worker holds the job
  arq:job:{job_id}          STR   serialized job tuple
  arq:result:{job_id}       STR   serialized JobResult dataclass

Note the hyphen in `in-progress` — easy to typo as `in_progress`.
We use arq's own deserialize_job_raw / deserialize_result helpers
to avoid hand-rolling the schema (and to match whatever serializer
the worker is configured with).
"""
from __future__ import annotations

import logging
import os
import time
from datetime import datetime, timezone

from arq.jobs import deserialize_job_raw, deserialize_result

from monitor.cache import get_cache_redis
from monitor.schema import ArqActiveJob, ArqBlock, ArqCompletedJob, ArqFailedJob

logger = logging.getLogger("monitor.arq")

_ARQ_MAX_JOBS = int(os.getenv("ARQ_MAX_JOBS", "3"))


async def collect() -> ArqBlock:
    r = get_cache_redis()

    # Pending queue depth — zset of job_ids scheduled to run
    queue_depth = int(await r.zcard("arq:queue") or 0)

    # In-flight jobs are detected by the per-job TTL lock prefix.
    # decode_responses=True on this client, so keys come back as str.
    in_progress_ids: list[str] = []
    async for k in r.scan_iter(match="arq:in-progress:*", count=200):
        in_progress_ids.append(k.split(":", 2)[-1])
    in_flight = len(in_progress_ids)

    active: list[ArqActiveJob] = []
    now_ms = int(time.time() * 1000)
    for job_id in in_progress_ids[:20]:
        raw = await r.get(f"arq:job:{job_id}")
        if not raw:
            continue
        if isinstance(raw, str):
            # decode_responses=True returned latin-1; re-encode to bytes
            # for arq's deserializer (it expects raw bytes).
            raw = raw.encode("latin-1")
        try:
            fn, args, _kwargs, _job_try, enqueue_time = deserialize_job_raw(raw)
        except Exception as e:
            logger.debug("arq: job %s deserialize failed: %s", job_id, e)
            continue
        target = _extract_target(fn, args)
        started = datetime.fromtimestamp(enqueue_time / 1000, tz=timezone.utc)
        elapsed_s = max(0, int((now_ms - enqueue_time) / 1000))
        active.append(ArqActiveJob(
            job_id=job_id, fn=fn, source=_extract_source(target), target=target,
            started=started, elapsed_s=elapsed_s,
        ))

    # Walk every result key once; bucket by success and finish recency.
    # ARQ's default keep_result is 1h, so this naturally caps at the
    # last hour of activity — completed_24h is best-effort, not exact.
    completed_24h = 0
    failed_24h = 0
    completed: list[dict] = []
    failed: list[dict] = []
    cutoff_ms = now_ms - 24 * 3600 * 1000
    async for key in r.scan_iter(match="arq:result:*", count=200):
        raw = await r.get(key)
        if not raw:
            continue
        if isinstance(raw, str):
            raw = raw.encode("latin-1")
        try:
            jr = deserialize_result(raw)
        except Exception:
            continue
        finish_ms = int(jr.finish_time.timestamp() * 1000) if jr.finish_time else 0
        if finish_ms < cutoff_ms:
            continue
        if jr.success:
            completed_24h += 1
        else:
            failed_24h += 1
        target = _extract_target(jr.function, jr.args)
        common = dict(
            job_id=jr.job_id, fn=jr.function,
            source=_extract_source(target), target=target,
            finished=jr.finish_time,
        )
        if jr.success:
            duration_s = int((jr.finish_time - jr.start_time).total_seconds()) if jr.start_time and jr.finish_time else 0
            completed.append({**common, "duration_s": duration_s})
        else:
            failed.append({**common, "error": str(jr.result or "")[:120]})

    # newest first, capped at 5 each
    completed.sort(key=lambda d: d["finished"], reverse=True)
    failed.sort(key=lambda d: d["finished"], reverse=True)
    completed = completed[:5]
    failed = failed[:5]

    return ArqBlock(
        queue_depth=queue_depth,
        in_flight=in_flight,
        workers=_ARQ_MAX_JOBS,
        completed_24h=completed_24h,
        failed_24h=failed_24h,
        active=active,
        recent_completed=[ArqCompletedJob(**d) for d in completed],
        recent_failed=[ArqFailedJob(**d) for d in failed],
    )


def _extract_target(fn: str, args) -> str:
    if args and isinstance(args[0], str):
        return args[0]
    return fn or ""


def _extract_source(target: str) -> str:
    for k in ("ao3", "ffnet", "nhentai", "toongod", "hentai20", "mangadex"):
        if target.startswith(k + ":") or k in target:
            return k
    return "unknown"
