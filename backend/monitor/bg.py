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


async def log_tailer() -> None:
    raise NotImplementedError


async def nginx_access_sampler() -> None:
    raise NotImplementedError
