"""arq collector — introspect ARQ state from Redis."""
from __future__ import annotations

import json
import logging
import os
import time
from datetime import datetime, timezone

from monitor.cache import get_cache_redis
from monitor.schema import ArqActiveJob, ArqBlock, ArqCompletedJob, ArqFailedJob

logger = logging.getLogger("monitor.arq")

_ARQ_MAX_JOBS = int(os.getenv("ARQ_MAX_JOBS", "3"))


async def collect() -> ArqBlock:
    r = get_cache_redis()

    queue_depth = int(await r.zcard("arq:queue") or 0)

    in_progress_keys = []
    async for k in r.scan_iter(match="arq:in_progress:*", count=200):
        in_progress_keys.append(k)
    in_flight = len(in_progress_keys)

    active = []
    now_ms = int(time.time() * 1000)
    for key in in_progress_keys[:20]:
        job_id = key.split(":", 2)[-1]
        payload = await r.get(f"arq:job:{job_id}")
        if not payload:
            continue
        try:
            jd = json.loads(payload)
        except Exception:
            continue
        fn = jd.get("function", "unknown")
        target = _extract_target(jd)
        source = _extract_source(target)
        enqueue = jd.get("enqueue_time", now_ms)
        started = datetime.fromtimestamp(enqueue / 1000, tz=timezone.utc)
        elapsed_s = max(0, int((now_ms - enqueue) / 1000))
        active.append(ArqActiveJob(
            job_id=job_id, fn=fn, source=source, target=target,
            started=started, elapsed_s=elapsed_s,
        ))

    completed_24h = int(await r.get("mon:arq_completed_24h") or 0)
    failed_24h = int(await r.get("mon:arq_failed_24h") or 0)

    recent_completed = await _recent_jobs(r, "arq:result:*", status_ok=True)
    recent_failed = await _recent_jobs(r, "arq:result:*", status_ok=False)

    return ArqBlock(
        queue_depth=queue_depth,
        in_flight=in_flight,
        workers=_ARQ_MAX_JOBS,
        completed_24h=completed_24h,
        failed_24h=failed_24h,
        active=active,
        recent_completed=[ArqCompletedJob(**d) for d in recent_completed],
        recent_failed=[ArqFailedJob(**d) for d in recent_failed],
    )


async def _recent_jobs(r, pattern: str, status_ok: bool, limit: int = 5) -> list[dict]:
    out = []
    async for key in r.scan_iter(match=pattern, count=200):
        if len(out) >= limit:
            break
        raw = await r.get(key)
        if not raw:
            continue
        try:
            jd = json.loads(raw)
        except Exception:
            continue
        if bool(jd.get("success")) != status_ok:
            continue
        job_id = key.split(":", 2)[-1]
        finished_at = jd.get("finish_time")
        enqueue = jd.get("enqueue_time", finished_at)
        duration_s = int((finished_at - enqueue) / 1000) if finished_at and enqueue else 0
        fn = jd.get("function", "unknown")
        target = _extract_target(jd)
        common = dict(
            job_id=job_id, fn=fn, source=_extract_source(target), target=target,
            finished=datetime.fromtimestamp((finished_at or 0) / 1000, tz=timezone.utc),
        )
        if status_ok:
            common["duration_s"] = duration_s
        else:
            common["error"] = str(jd.get("result") or "")[:120]
        out.append(common)
    return out


def _extract_target(jd: dict) -> str:
    args = jd.get("args") or []
    if args and isinstance(args[0], str):
        return args[0]
    return jd.get("function", "")


def _extract_source(target: str) -> str:
    for k in ("ao3", "ffnet", "nhentai", "toongod", "hentai20", "mangadex"):
        if target.startswith(k + ":") or k in target:
            return k
    return "unknown"
