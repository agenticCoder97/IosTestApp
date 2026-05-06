"""Long-lived background tasks for the monitor service."""
from __future__ import annotations

import asyncio
import logging
from collections import deque
from typing import Any, Awaitable, Callable, Deque

logger = logging.getLogger("monitor.bg")

_BACKOFF_INITIAL_S = 10
_BACKOFF_MAX_S = 60
_LOG_DEQUE_MAXLEN = 2000       # ~10 × _LOG_TAIL_ON_ATTACH across all services
_LOG_TAIL_ON_ATTACH = 200      # lines of history fetched when a follower (re)attaches
LOG_METRICS_LIMIT = 400        # lines sliced from LOG_DEQUE per /metrics call

SERVICE_CACHE: dict[str, dict[str, Any]] = {}
LOG_DEQUE: Deque[dict[str, Any]] = deque(maxlen=_LOG_DEQUE_MAXLEN)
# App-default request metric blocks, populated by nginx_access_sampler.
NGINX_WINDOW_CACHE: dict[str, dict[str, Any]] = {}
NGINX_TOTAL_WINDOW_CACHE: dict[str, dict[str, Any]] = {}
NGINX_ACCESS_RECORDS: Deque[dict[str, Any]] = deque(maxlen=100_000)
NGINX_SAMPLER_META: dict[str, Any] = {
    "last_sample_at": None,
    "elapsed_ms": 0,
    "parse_failures": 0,
    "parse_failure_samples": [],
}

# Per-endpoint bucketed series, keyed by (method, path) → {window: [buckets]}.
# Populated by nginx_access_sampler alongside NGINX_WINDOW_CACHE.
# Capped at the top 20 endpoints per window by request count to keep
# memory bounded.
NGINX_ENDPOINT_CACHE: dict[str, dict[tuple[str, str], list[dict[str, Any]]]] = {}


async def supervise(factory: Callable[[], Awaitable[Any]], name: str) -> None:
    """Restart factory() on non-Cancelled exceptions with exponential backoff."""
    backoff = _BACKOFF_INITIAL_S
    while True:
        try:
            await factory()
            return
        except asyncio.CancelledError:
            raise
        except Exception as e:
            logger.exception("bg task %s died: %s — retry in %ss", name, e, backoff)
            await asyncio.sleep(backoff)
            backoff = min(backoff * 2, _BACKOFF_MAX_S)


async def _sample_once(client, redis) -> None:
    """Single-tick: walk containers, update SERVICE_CACHE + Redis sparklines."""
    import time as _time
    from datetime import datetime, timezone

    now_ms = int(_time.time() * 1000)
    # docker-py calls are blocking HTTP — offload to a thread so the event
    # loop stays responsive to /metrics requests during each 10s sample tick.
    containers = await asyncio.to_thread(
        client.containers.list,
        all=True,
        filters={"label": "com.docker.compose.project=backend"},
    )
    for c in containers:
        svc = c.labels.get("com.docker.compose.service")
        if not svc:
            continue
        # The monitor service itself is a compose service but shouldn't appear
        # in its own UI grid — the dashboard expects exactly 6 cards.
        if svc == "astral_monitor":
            continue
        state = c.attrs.get("State", {})
        status = state.get("Status", "unknown")
        health_obj = state.get("Health")
        health = health_obj.get("Status") if isinstance(health_obj, dict) else None
        # Absence of a Docker healthcheck is not evidence of unhealthiness —
        # synthesize "healthy" for any container whose Docker state is
        # "running", so the UI's UP/DOWN badge reflects runtime reality
        # rather than compose healthcheck presence. Exited/dead containers
        # keep health=None and the renderer correctly flags them DOWN.
        if health is None and status == "running":
            health = "healthy"
        started_at = state.get("StartedAt") or ""
        try:
            started_dt = datetime.fromisoformat(started_at.replace("Z", "+00:00"))
            uptime_s = int((datetime.now(timezone.utc) - started_dt).total_seconds())
        except Exception:
            uptime_s = 0

        try:
            stats = await asyncio.to_thread(c.stats, stream=False)
        except Exception:
            stats = None

        cpu_pct = _compute_cpu_pct(stats) if stats else 0.0
        mem_mb = _compute_mem_mb(stats) if stats else 0.0

        image_tag = (c.image.tags or [""])[0]
        ui_status = {
            "running": "up", "restarting": "restarting",
            "exited": "stopped", "paused": "unhealthy",
            "dead": "unhealthy", "created": "starting",
        }.get(status, status)

        entry = SERVICE_CACHE.setdefault(svc, {
            "name": svc, "image": image_tag, "container_id": c.short_id,
            "status": ui_status, "health": health, "uptime_s": uptime_s,
            "cpu_pct": cpu_pct, "mem_mb": mem_mb, "restarts": 0,
            "extra": {}, "spark_cpu": [],
        })
        entry.update({
            "image": image_tag, "container_id": c.short_id,
            "status": ui_status, "health": health, "uptime_s": uptime_s,
            "cpu_pct": round(cpu_pct, 2), "mem_mb": round(mem_mb, 1),
        })
        entry["spark_cpu"] = (entry.get("spark_cpu", []) + [round(cpu_pct, 2)])[-120:]

        # Service-specific `extra` dict — what each card footer renders.
        extra = await _fetch_service_extra(svc, started_at, now_ms, redis)
        if extra:
            entry["extra"] = extra

        try:
            await redis.zadd(f"mon:sparkline:{svc}", {str(cpu_pct): now_ms})
            await redis.zremrangebyscore(
                f"mon:sparkline:{svc}", 0, now_ms - 7 * 24 * 3600 * 1000,
            )
        except Exception as e:
            logger.debug("sparkline update failed svc=%s err=%s", svc, e)


async def _fetch_service_extra(svc: str, started_at_iso: str, now_ms: int, redis_cli) -> dict:
    """Per-service `extra` dict surfaced in the UI card footer.

    Each fetch is isolated — if a subsystem is down (redis, pg) we return an
    empty dict and the UI falls back to normalizeMetrics defaults in the JS.
    """
    try:
        if svc == "postgres":
            from monitor.collectors import storage as _s
            pool = _s.get_pg_pool_or_none()
            if pool is None:
                return {}
            async with pool.acquire() as conn:
                row = await conn.fetchrow(
                    "SELECT (SELECT count(*) FROM pg_stat_activity "
                    "        WHERE datname = current_database()) AS conns, "
                    "current_setting('max_connections')::int AS max_conns"
                )
            return {
                "pg_connections": int(row["conns"]) if row else 0,
                "pg_max_connections": int(row["max_conns"]) if row else 100,
            }

        if svc == "redis" and redis_cli is not None:
            info = await redis_cli.info("stats")
            keys = await redis_cli.dbsize()
            return {
                "ops_sec": int(info.get("instantaneous_ops_per_sec", 0) or 0),
                "keys": int(keys or 0),
            }

        if svc == "fastapi":
            import os as _os
            workers = int(_os.getenv("UVICORN_WORKERS", "1"))
            # Use the 60-second /api/* window so rps is genuinely "last
            # minute of prod API traffic" rather than a 1-hour average.
            cached = NGINX_WINDOW_CACHE.get("1m_api", {})
            sc = cached.get("status_codes", {}) or {}
            total = sum(int(sc.get(k, 0) or 0) for k in ("2xx", "3xx", "4xx", "5xx"))
            rps = total / 60.0
            return {"workers": workers, "rps": f"{rps:.2f}"}

        if svc == "arq_worker":
            import os as _os
            jobs_active = 0
            if redis_cli is not None:
                async for _k in redis_cli.scan_iter(match="arq:in_progress:*", count=200):
                    jobs_active += 1
            return {
                "jobs_active": jobs_active,
                "max": int(_os.getenv("ARQ_MAX_JOBS", "3")),
            }

        if svc == "nginx":
            # Prefer real stub_status data; fall back to the 1h window
            # approximation if the scrape fails (stub_status not mounted,
            # nginx down, etc.).
            from monitor.collectors import _nginx_stub
            stub = await _nginx_stub.fetch_stub()
            if stub:
                return {
                    "active_connections": stub["active_connections"],
                    "reqs_total":         stub["total_requests"],
                }
            cached = NGINX_TOTAL_WINDOW_CACHE.get("1h") or NGINX_WINDOW_CACHE.get("1h", {})
            sc = cached.get("status_codes", {}) or {}
            total = sum(int(sc.get(k, 0) or 0) for k in ("2xx", "3xx", "4xx", "5xx"))
            return {"active_connections": 0, "reqs_total": total}

        if svc == "certbot":
            # certbot container loops `certbot renew; sleep 43200` (12h).
            # next_check_in is computed from container uptime mod 12h.
            try:
                from datetime import datetime as _dt, timezone as _tzmod
                started = _dt.fromisoformat(started_at_iso.replace("Z", "+00:00"))
                age_s = int((now_ms / 1000) - started.timestamp())
            except Exception:
                age_s = 0
            secs_to_next = 43200 - (age_s % 43200)
            h, m = secs_to_next // 3600, (secs_to_next % 3600) // 60
            return {"next_check_in": f"{h}h {m}m"}

    except Exception as e:
        logger.debug("service extra fetch failed svc=%s err=%s", svc, e)
    return {}


def _compute_cpu_pct(stats: dict) -> float:
    try:
        cpu_delta = stats["cpu_stats"]["cpu_usage"]["total_usage"] \
            - stats["precpu_stats"]["cpu_usage"]["total_usage"]
        sys_delta = stats["cpu_stats"]["system_cpu_usage"] \
            - stats["precpu_stats"]["system_cpu_usage"]
        cpus = stats["cpu_stats"].get("online_cpus", 1)
        if sys_delta <= 0 or cpu_delta < 0:
            return 0.0
        return (cpu_delta / sys_delta) * cpus * 100.0
    except (KeyError, TypeError):
        return 0.0


def _compute_mem_mb(stats: dict) -> float:
    try:
        usage = stats["memory_stats"].get("usage", 0)
        cache_bytes = stats["memory_stats"].get("stats", {}).get("cache", 0)
        return max(0.0, (usage - cache_bytes) / 1024 / 1024)
    except (KeyError, TypeError):
        return 0.0


async def docker_sampler() -> None:
    """Every 10s: one full pass."""
    import docker

    from monitor.cache import get_cache_redis_or_none
    client = docker.from_env()
    redis = get_cache_redis_or_none()

    while True:
        try:
            await _sample_once(client, redis)
        except Exception as e:
            logger.warning("docker_sampler tick failed: %s", e)
        await asyncio.sleep(10)


# ─── log tailer ────────────────────────────────────────────────────────

import re as __re_for_logs
from datetime import datetime as __dt_for_logs, timezone as __tz_for_logs

_LOG_LEVEL_RE = __re_for_logs.compile(r"\b(DEBUG|INFO|WARN|ERROR)\b", __re_for_logs.IGNORECASE)
_REDACT_SUBS = [
    (__re_for_logs.compile(r"Authorization:\s*\S+", __re_for_logs.IGNORECASE), "Authorization: REDACTED"),
    (__re_for_logs.compile(r"Cookie:\s*\S+", __re_for_logs.IGNORECASE),        "Cookie: REDACTED"),
    (__re_for_logs.compile(r"token=\S+", __re_for_logs.IGNORECASE),            "token=REDACTED"),
]


def _redact(msg: str) -> str:
    for pattern, replacement in _REDACT_SUBS:
        msg = pattern.sub(replacement, msg)
    return msg


def _classify_level(msg: str, svc: str, status: int | None = None) -> str:
    if svc == "nginx" and status is not None:
        if status >= 500: return "error"
        if status >= 400: return "warn"
        return "info"
    m = _LOG_LEVEL_RE.search(msg)
    if m:
        return m.group(1).lower()
    return "info"


async def _follow_one(client, container, svc: str) -> None:
    """Follow a single container forever. Lines go to LOG_DEQUE."""
    def _iter():
        # tail=_LOG_TAIL_ON_ATTACH gives newly-attached followers recent
        # history on monitor restart, so quiet services (fastapi,
        # astral_monitor) are visible in the Logs view immediately rather
        # than only after new traffic arrives.
        return container.logs(stream=True, follow=True, tail=_LOG_TAIL_ON_ATTACH, timestamps=True)

    it = await asyncio.to_thread(_iter)
    while True:
        try:
            chunk = await asyncio.to_thread(next, it, None)
        except StopIteration:
            return
        if chunk is None:
            return
        try:
            line = chunk.decode("utf-8", errors="replace").rstrip("\n")
        except Exception:
            continue
        ts_str, _, rest = line.partition(" ")
        try:
            ts = __dt_for_logs.fromisoformat(ts_str.replace("Z", "+00:00"))
        except Exception:
            ts = __dt_for_logs.now(__tz_for_logs.utc)
        msg = _redact(rest)
        lvl = _classify_level(msg, svc)
        entry = {"ts": ts, "svc": svc, "lvl": lvl, "msg": msg[:500]}
        LOG_DEQUE.append(entry)
        try:
            from monitor import logs_stream
            logs_stream.publish(entry)
        except Exception as e:
            logger.debug("logs_stream.publish failed (SSE subscribers will miss this line): %s", e)


async def log_tailer() -> None:
    """Spin one _follow_one coroutine per compose service. Reattach on restart."""
    import docker

    client = docker.from_env()
    followers: dict[str, asyncio.Task] = {}

    while True:
        containers = await asyncio.to_thread(
            client.containers.list,
            all=True,
            filters={"label": "com.docker.compose.project=backend"},
        )
        by_svc = {
            c.labels.get("com.docker.compose.service"): c
            for c in containers
            if c.labels.get("com.docker.compose.service")
        }
        for svc, c in by_svc.items():
            t = followers.get(svc)
            if t is None or t.done():
                followers[svc] = asyncio.create_task(_follow_one(client, c, svc))
        await asyncio.sleep(30)


# ─── nginx access log sampler ─────────────────────────────────────────

import re as _re
import time as _time
from collections import Counter as _Counter
from datetime import datetime as _dt, timezone as _tz
from pathlib import Path as _Path

from monitor.requests_metrics import (
    WINDOWS_S as _REQUEST_WINDOWS_S,
    build_requests_block as _build_requests_block,
    records_for_window as _records_for_window,
)
from monitor.traffic import (
    RequestFilters as _RequestFilters,
    classify_request as _classify_request,
    normalize_path as _normalize_path,
    redact_sample as _redact_sample,
    status_band as _status_band,
)

NGINX_ACCESS_PATH = _Path("/var/log/nginx/access.log")

_LOG_RE = _re.compile(
    r'^(?P<ip>\S+) - (?P<user>\S+) '
    r'\[(?P<ts>[^\]]+)\] '
    r'"(?P<method>\S+) (?P<path>\S+) (?P<proto>[^"]+)" '
    r'(?P<status>\d{3}) (?P<bytes>\d+|-) '
    r'rt=(?P<rt>[\d.]+) urt="(?P<urt>[^"]*)" '
    r'"(?P<referer>[^"]*)" "(?P<ua>[^"]*)"$'
)

_WINDOWS_S = _REQUEST_WINDOWS_S


def _parse_log_line(line: str) -> dict | None:
    m = _LOG_RE.match(line.strip())
    if not m:
        return None
    try:
        ts = _dt.fromisoformat(m["ts"])
        if ts.tzinfo is None:
            ts = ts.replace(tzinfo=_tz.utc)
    except Exception:
        return None
    try:
        rt_ms = int(float(m["rt"]) * 1000)
    except Exception:
        rt_ms = 0
    classification = _classify_request(m["method"], m["path"])
    return {
        "ts_ms": int(ts.timestamp() * 1000),
        "method": m["method"],
        "path": m["path"],
        "status": int(m["status"]),
        "rt_ms": rt_ms,
        "traffic_class": classification.traffic_class,
        "classification_reason": classification.reason,
    }


def _compute_window(records: list[dict], window: str) -> dict:
    status_codes = {"2xx": 0, "3xx": 0, "4xx": 0, "5xx": 0}
    by_path: dict[tuple[str, str], list[int]] = {}
    bucket_ms = max(60_000, _WINDOWS_S[window] * 1000 // 60)
    series_rps_buckets: dict[int, int] = {}
    series_p95_buckets: dict[int, list[int]] = {}

    for r in records:
        s = r["status"]
        if   200 <= s < 300: band = "2xx"
        elif 300 <= s < 400: band = "3xx"
        elif 400 <= s < 500: band = "4xx"
        elif 500 <= s < 600: band = "5xx"
        else:                band = "5xx"
        status_codes[band] += 1
        by_path.setdefault((r["method"], r["path"]), []).append(r["rt_ms"])
        bucket = (r["ts_ms"] // bucket_ms) * bucket_ms
        series_rps_buckets[bucket] = series_rps_buckets.get(bucket, 0) + 1
        series_p95_buckets.setdefault(bucket, []).append(r["rt_ms"])

    series_rps = [[b, series_rps_buckets[b] / (bucket_ms / 1000)] for b in sorted(series_rps_buckets)]
    series_p95 = [[b, _pct(series_p95_buckets[b], 95)] for b in sorted(series_p95_buckets)]

    slowest = []
    for (method, path), rts in by_path.items():
        slowest.append({
            "method": method, "path": path,
            "p50_ms": _pct(rts, 50),
            "p95_ms": _pct(rts, 95),
            "p99_ms": _pct(rts, 99),
            "count": len(rts),
        })
    slowest.sort(key=lambda r: r["p95_ms"], reverse=True)
    top_slowest = slowest[:10]

    return {
        "window": window,
        "series_rps": series_rps,
        "series_p95_ms": series_p95,
        "status_codes": status_codes,
        "slowest": top_slowest,
    }


def _build_endpoint_cache(records: list[dict], window: str) -> None:
    bucket_ms = max(60_000, _WINDOWS_S[window] * 1000 // 60)
    by_path: dict[tuple[str, str], list[dict]] = {}
    endpoint_buckets: dict[tuple[str, str], dict[int, dict]] = {}

    for r in records:
        method = str(r.get("method", ""))
        path = _normalize_path(str(r.get("path", "")))
        key = (method, path)
        by_path.setdefault(key, []).append(r)
        bucket = (_coerce_int(r.get("ts_ms")) // bucket_ms) * bucket_ms
        band = _status_band(_coerce_int(r.get("status"))) or "5xx"
        ep = endpoint_buckets.setdefault(key, {})
        b = ep.setdefault(bucket, {
            "rts": [],
            "status_2xx": 0, "status_3xx": 0, "status_4xx": 0, "status_5xx": 0,
        })
        b["rts"].append(_coerce_int(r.get("rt_ms")))
        b[f"status_{band}"] += 1

    top_by_count = sorted(by_path.items(), key=lambda kv: len(kv[1]), reverse=True)[:20]
    endpoint_cache: dict[tuple[str, str], list[dict[str, Any]]] = {}
    for key, _records in top_by_count:
        buckets_sorted = sorted(endpoint_buckets.get(key, {}).items())
        endpoint_cache[key] = [
            {
                "ts_ms": ts,
                "p50_ms": _pct(b["rts"], 50),
                "p95_ms": _pct(b["rts"], 95),
                "p99_ms": _pct(b["rts"], 99),
                "count": len(b["rts"]),
                "status_2xx": b["status_2xx"],
                "status_3xx": b["status_3xx"],
                "status_4xx": b["status_4xx"],
                "status_5xx": b["status_5xx"],
            }
            for ts, b in buckets_sorted
        ]
    NGINX_ENDPOINT_CACHE[window] = endpoint_cache


def _pct(values: list[int], p: int) -> int:
    if not values:
        return 0
    xs = sorted(values)
    k = int(len(xs) * p / 100)
    return xs[min(k, len(xs) - 1)]


def _coerce_int(value: object) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def _read_access_log_records() -> tuple[list[dict], int, list[str]]:
    """Synchronous file read — invoked via asyncio.to_thread so the event
    loop stays free during the read. Returns parsed records and parse metadata."""
    from collections import deque as _deque

    if not NGINX_ACCESS_PATH.exists():
        return [], 0, []
    tail_buf: "deque[str]" = _deque(maxlen=100_000)
    with NGINX_ACCESS_PATH.open("r", errors="replace") as fh:
        for line in fh:
            tail_buf.append(line)
    out = []
    parse_failures = 0
    failure_samples: list[str] = []
    for line in tail_buf:
        rec = _parse_log_line(line)
        if rec is not None:
            out.append(rec)
            continue
        parse_failures += 1
        if len(failure_samples) < 10:
            failure_samples.append(_redact_sample(line.rstrip("\n")))
    return out, parse_failures, failure_samples


def _refresh_nginx_request_caches(
    all_records: list[dict],
    parse_failures: int,
    failure_samples: list[str],
    *,
    now_ms: int | None = None,
    elapsed_ms: int = 0,
) -> dict[str, Any]:
    if now_ms is None:
        now_ms = int(_dt.now(_tz.utc).timestamp() * 1000)

    NGINX_ACCESS_RECORDS.clear()
    NGINX_ACCESS_RECORDS.extend(all_records)

    class_counts = _Counter(str(r.get("traffic_class", "unknown")) for r in all_records)
    NGINX_SAMPLER_META.update({
        "last_sample_at": now_ms,
        "elapsed_ms": elapsed_ms,
        "parse_failures": parse_failures,
        "parse_failure_samples": failure_samples,
    })

    default_filters = _RequestFilters()
    for w in _WINDOWS_S:
        window_records = _records_for_window(all_records, w, now_ms=now_ms)
        app_block = _build_requests_block(window_records, w, default_filters)
        NGINX_WINDOW_CACHE[w] = app_block.model_dump(mode="json", by_alias=True)
        NGINX_TOTAL_WINDOW_CACHE[w] = _compute_window(window_records, w)

        if w != "1m_api":
            app_records = [
                r for r in window_records if r.get("traffic_class") == default_filters.traffic
            ]
            _build_endpoint_cache(app_records, w)

    return {
        "total_records": len(all_records),
        "parse_failures": parse_failures,
        "class_counts": dict(class_counts),
        "elapsed_ms": elapsed_ms,
    }


async def nginx_access_sampler() -> None:
    """Every 60s: tail access.log and refresh request metric caches."""
    while True:
        try:
            started = _time.perf_counter()
            all_records, parse_failures, failure_samples = await asyncio.to_thread(
                _read_access_log_records
            )
            elapsed_ms = int((_time.perf_counter() - started) * 1000)
            summary = _refresh_nginx_request_caches(
                all_records,
                parse_failures,
                failure_samples,
                elapsed_ms=elapsed_ms,
            )
            logger.info(
                "nginx_access_sampler tick total_records=%d parse_failures=%d "
                "class_counts=%s elapsed_ms=%d",
                summary["total_records"],
                summary["parse_failures"],
                summary["class_counts"],
                summary["elapsed_ms"],
            )
        except Exception as e:
            logger.warning("nginx_access_sampler failed: %s", e)
        await asyncio.sleep(60)


# ─── storage trend hoister ────────────────────────────────────────────

async def storage_trend_hoister() -> None:
    """Every hour, sample storage into Redis ZSETs so the UI's storage
    sparklines have 7d of history."""
    from monitor.collectors import storage
    from monitor.cache import get_cache_redis_or_none
    import time as _time

    while True:
        try:
            r = get_cache_redis_or_none()
            block = await storage.collect()
            now_ms = int(_time.time() * 1000)

            async def _push(key, val):
                if val is None or r is None:
                    return
                await r.zadd(f"mon:sparkline:storage:{key}", {str(int(val)): now_ms})
                await r.zremrangebyscore(
                    f"mon:sparkline:storage:{key}", 0, now_ms - 7 * 24 * 3600 * 1000,
                )

            await _push("postgres", block.postgres_bytes)
            await _push("media", block.media_bytes)
            await _push("block_free", block.block_vol.free_bytes if block.block_vol else None)
            await _push("object_used", block.object_storage.used_bytes if block.object_storage else None)
        except Exception as e:
            logger.warning("storage_trend_hoister failed: %s", e)
        await asyncio.sleep(3600)
