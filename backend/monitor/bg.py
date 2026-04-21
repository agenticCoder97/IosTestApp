"""Long-lived background tasks for the monitor service."""
from __future__ import annotations

import asyncio
import logging
from collections import deque
from typing import Any, Awaitable, Callable, Deque

logger = logging.getLogger("monitor.bg")

_BACKOFF_INITIAL_S = 10
_BACKOFF_MAX_S = 60

SERVICE_CACHE: dict[str, dict[str, Any]] = {}
LOG_DEQUE: Deque[dict[str, Any]] = deque(maxlen=500)
NGINX_WINDOW_CACHE: dict[str, dict[str, Any]] = {}


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
    containers = client.containers.list(
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
        started_at = state.get("StartedAt") or ""
        try:
            started_dt = datetime.fromisoformat(started_at.replace("Z", "+00:00"))
            uptime_s = int((datetime.now(timezone.utc) - started_dt).total_seconds())
        except Exception:
            uptime_s = 0

        try:
            stats = c.stats(stream=False)
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

        try:
            await redis.zadd(f"mon:sparkline:{svc}", {str(cpu_pct): now_ms})
            await redis.zremrangebyscore(
                f"mon:sparkline:{svc}", 0, now_ms - 7 * 24 * 3600 * 1000,
            )
        except Exception as e:
            logger.debug("sparkline update failed svc=%s err=%s", svc, e)


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
        return container.logs(stream=True, follow=True, tail=0, timestamps=True)

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
        LOG_DEQUE.append({"ts": ts, "svc": svc, "lvl": lvl, "msg": msg[:500]})


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
from datetime import datetime as _dt, timezone as _tz
from pathlib import Path as _Path

NGINX_ACCESS_PATH = _Path("/var/log/nginx/access.log")

_LOG_RE = _re.compile(
    r'^(?P<ip>\S+) - (?P<user>\S+) '
    r'\[(?P<ts>[^\]]+)\] '
    r'"(?P<method>\S+) (?P<path>\S+) (?P<proto>[^"]+)" '
    r'(?P<status>\d{3}) (?P<bytes>\d+|-) '
    r'rt=(?P<rt>[\d.]+) urt="(?P<urt>[^"]*)" '
    r'"(?P<referer>[^"]*)" "(?P<ua>[^"]*)"$'
)

_WINDOWS_S = {"1h": 3600, "6h": 21600, "24h": 86400, "7d": 604800, "30d": 2592000}


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
    return {
        "ts_ms": int(ts.timestamp() * 1000),
        "method": m["method"],
        "path": m["path"],
        "status": int(m["status"]),
        "rt_ms": rt_ms,
    }


def _compute_window(records: list[dict], window: str) -> dict:
    status_codes = {"2xx": 0, "3xx": 0, "4xx": 0, "5xx": 0}
    by_path: dict[tuple[str, str], list[int]] = {}
    bucket_ms = max(60_000, _WINDOWS_S[window] * 1000 // 60)
    series_rps_buckets: dict[int, int] = {}
    series_p95_buckets: dict[int, list[int]] = {}

    for r in records:
        s = r["status"]
        if   200 <= s < 300: status_codes["2xx"] += 1
        elif 300 <= s < 400: status_codes["3xx"] += 1
        elif 400 <= s < 500: status_codes["4xx"] += 1
        elif 500 <= s < 600: status_codes["5xx"] += 1
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
    slowest = slowest[:10]

    return {
        "window": window,
        "series_rps": series_rps,
        "series_p95_ms": series_p95,
        "status_codes": status_codes,
        "slowest": slowest,
    }


def _pct(values: list[int], p: int) -> int:
    if not values:
        return 0
    xs = sorted(values)
    k = int(len(xs) * p / 100)
    return xs[min(k, len(xs) - 1)]


async def nginx_access_sampler() -> None:
    """Every 60s: tail access.log, compute all 5 windows, write NGINX_WINDOW_CACHE."""
    while True:
        try:
            if not NGINX_ACCESS_PATH.exists():
                await asyncio.sleep(60)
                continue
            from collections import deque as _deque
            tail_buf: Deque[str] = _deque(maxlen=100_000)
            with NGINX_ACCESS_PATH.open("r", errors="replace") as fh:
                for line in fh:
                    tail_buf.append(line)

            now_ms = int(_dt.now(_tz.utc).timestamp() * 1000)
            all_records = []
            for line in tail_buf:
                rec = _parse_log_line(line)
                if rec is not None:
                    all_records.append(rec)

            for w, seconds in _WINDOWS_S.items():
                cutoff = now_ms - seconds * 1000
                window_records = [r for r in all_records if r["ts_ms"] >= cutoff]
                NGINX_WINDOW_CACHE[w] = _compute_window(window_records, w)
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
