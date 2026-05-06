"""Astral OCI monitor — FastAPI entrypoint.

Routes:
  GET /healthz                  compose liveness probe
  GET /                         dashboard HTML
  GET /static/*                 static assets
  GET /metrics?range=6h         full aggregate
  GET /metrics/service/{name}   single ServiceBlock
  GET /metrics/logs/stream      Phase 2 — 501 for v1

Bg tasks started in lifespan: docker_sampler, log_tailer,
nginx_access_sampler (see monitor.bg).
"""
from __future__ import annotations

import asyncio
import logging
import os
import subprocess
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from functools import partial
from pathlib import Path

import redis.asyncio as aioredis
from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.responses import FileResponse, JSONResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles

from monitor import bg, cache, logs_stream
from monitor.collectors import arq, backups, cert, cost, deploys as deploys_coll
from monitor.collectors import logs as logs_coll
from monitor.collectors import requests_ as requests_coll
from monitor.collectors import services as services_coll
from monitor.collectors import storage
from monitor.control.routes import router as control_router
from typing import cast

from monitor.requests_metrics import build_request_debug, records_for_window
from monitor.schema import EndpointDetail, MetricsResponse, RequestDebugResponse
from monitor.traffic import RankMode, RequestFilters, StatusBand, TrafficClass

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
logger = logging.getLogger("monitor")

_STATIC_DIR = Path(__file__).parent / "static"
_REDIS_URL = os.getenv("REDIS_URL", "redis://redis:6379/0")
_DB_URL = os.getenv("DATABASE_URL", "postgresql+asyncpg://astral:astral@postgres:5432/astral")


@asynccontextmanager
async def lifespan(_app: FastAPI):
    redis = aioredis.from_url(_REDIS_URL, decode_responses=True, socket_connect_timeout=2)
    cache.set_redis(redis)

    import asyncpg
    pg_dsn = _DB_URL.replace("postgresql+asyncpg://", "postgresql://")
    try:
        pg_pool = await asyncpg.create_pool(pg_dsn, min_size=1, max_size=2, timeout=3)
        storage.set_pg_pool(pg_pool)
    except Exception as e:
        logger.warning("monitor pg pool failed: %s", e)
        pg_pool = None

    # Grow the asyncio default ThreadPoolExecutor — /metrics runs 8
    # collectors via asyncio.gather; several use asyncio.to_thread for
    # OCI / docker-py sync calls. Combined with docker_sampler's 7 stats
    # calls every 10 s, the default 8-worker pool saturates and callers
    # queue. 32 workers is plenty for a monitor service.
    import concurrent.futures
    asyncio.get_event_loop().set_default_executor(
        concurrent.futures.ThreadPoolExecutor(max_workers=32, thread_name_prefix="monitor")
    )

    # Warm the OCI SDK before serving traffic — first instance-principal
    # signer handshake + first Budget/Usage API call can take several
    # seconds cold. Warm-up also writes to last_good via safe() so
    # /metrics timeouts fall back to warm cache instead of zero fallbacks.
    async def _warm_oci():
        try:
            await asyncio.gather(
                cache.safe(cost.collect,    "cost",    redis=redis, timeout=15.0, fallback=None),
                cache.safe(backups.collect, "backups", redis=redis, timeout=15.0, fallback=None),
                return_exceptions=True,
            )
            logger.info("monitor: OCI warm-up complete")
        except Exception as e:
            logger.warning("monitor: OCI warm-up failed: %s", e)

    tasks = [
        asyncio.create_task(bg.supervise(bg.docker_sampler, "docker_sampler")),
        asyncio.create_task(bg.supervise(bg.log_tailer, "log_tailer")),
        asyncio.create_task(bg.supervise(bg.nginx_access_sampler, "nginx_access_sampler")),
        asyncio.create_task(bg.supervise(bg.storage_trend_hoister, "storage_trend_hoister")),
        asyncio.create_task(_warm_oci()),
    ]
    logger.info("monitor started: %d bg tasks, redis=%s", len(tasks), _REDIS_URL)

    try:
        yield
    finally:
        for t in tasks:
            t.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
        await redis.aclose()
        if pg_pool is not None:
            await pg_pool.close()


app = FastAPI(title="astral-monitor", docs_url=None, redoc_url=None, lifespan=lifespan)
app.mount("/static", StaticFiles(directory=_STATIC_DIR), name="static")
app.include_router(control_router)


@app.get("/healthz")
async def healthz() -> JSONResponse:
    return JSONResponse({"status": "ok"})


@app.get("/")
async def index() -> FileResponse:
    return FileResponse(_STATIC_DIR / "index.html", media_type="text/html")


@app.get("/metrics")
async def metrics(range: str = Query("6h", pattern="^(1h|6h|24h|7d|30d)$")) -> JSONResponse:
    redis = cache.get_cache_redis_or_none()
    # (name, collector, fallback_factory, timeout_s)
    # OCI-SDK-backed collectors (cost, backups) get a longer timeout because
    # the instance-principal signer's first handshake can exceed 2 s cold
    # and cost now makes TWO OCI calls (budget + usage) via asyncio.gather.
    # du -sb on /mnt/astral-media (storage) can also take a few seconds on
    # a populated volume.
    collectors = [
        ("cost",     cost.collect,                                _empty_cost,             12.0),
        ("services", services_coll.collect,                       lambda: [],              2.0),
        ("requests", partial(requests_coll.collect, range),       lambda: _empty_requests(range), 2.0),
        ("arq",      arq.collect,                                 _empty_arq,              4.0),
        ("storage",  storage.collect,                             _empty_storage,          10.0),
        ("backups",  backups.collect,                             _empty_backups,          12.0),
        ("cert",     cert.collect,                                _empty_cert,             2.0),
        ("logs",     partial(logs_coll.collect, bg.LOG_METRICS_LIMIT),             lambda: [],              2.0),
        ("deploys",  deploys_coll.collect,                        _empty_deploys,          2.0),
    ]
    results = await asyncio.gather(
        *[cache.safe(c, name, redis=redis, timeout=t, fallback=fb())
          for name, c, fb, t in collectors],
    )
    payload: dict = {
        "schema_version": "1.0.0",
        "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "build": _build_sha(),
        "tenancy_ocid": os.getenv("OCI_TENANCY_OCID", "unknown"),
        "region": os.getenv("OCI_REGION", "unknown"),
        "instance_ocid": os.getenv("OCI_INSTANCE_OCID", "unknown"),
    }
    for (name, _c, _fb, _t), (data, meta) in zip(collectors, results):
        payload[name] = _serialize(data)
        if meta is not None:
            payload[f"{name}_meta"] = meta

    validated = MetricsResponse.model_validate(payload)
    return JSONResponse(validated.model_dump(mode="json", by_alias=True))


# ── empty / fallback builders used when a collector fails and has no last_good ──

def _empty_cost():
    from monitor.schema import CostBlock, AlwaysFree, CapUsage
    zero = CapUsage(used=0, cap=0, unit="")
    return CostBlock(
        currency="USD", month_to_date=0.0, forecast=0.0, budget=1.0, last_alert=None,
        always_free=AlwaysFree(
            a1_ocpu=CapUsage(used=4, cap=4, unit="ocpu"),
            a1_ram_gb=CapUsage(used=24, cap=24, unit="GB"),
            block_vol_gb=CapUsage(used=0, cap=200, unit="GB"),
            egress_tb=CapUsage(used=0, cap=10, unit="TB"),
            object_std_gb=CapUsage(used=0, cap=20, unit="GB"),
        ),
    )


def _empty_requests(window: str):
    from monitor.schema import RequestsBlock
    win = window if window in ("1h", "6h", "24h", "7d", "30d") else "6h"
    return RequestsBlock(
        window=win, series_rps=[], series_p95_ms=[],
        status_codes={"2xx": 0, "3xx": 0, "4xx": 0, "5xx": 0}, slowest=[],
    )


def _empty_arq():
    from monitor.schema import ArqBlock
    return ArqBlock(
        queue_depth=0, in_flight=0, workers=3,
        completed_24h=0, failed_24h=0,
        active=[], recent_completed=[], recent_failed=[],
    )


def _empty_storage():
    from monitor.schema import StorageBlock, StorageTrend
    return StorageBlock(
        postgres_bytes=None, media_bytes=None, block_vol=None, object_storage=None,
        trend_7d=StorageTrend(postgres=[0], media=[0], block_free=[0], object_used=[0]),
    )


def _empty_backups():
    from monitor.schema import BackupsBlock
    return BackupsBlock(
        last_pg_dump=None, last_size_bytes=None, status="stale",
        next_run_in_s=0, bucket="astral-backups",
        retention_days=56, recent_runs=[],
    )


def _empty_cert():
    from monitor.schema import CertBlock, CertRenew
    return CertBlock(
        domain="astral-reader.duckdns.org", issuer=None,
        not_before=None, not_after=None, days_left=None,
        last_renew=CertRenew(at=None, status="failed"),
    )


def _empty_deploys():
    from monitor.schema import DeploysBlock
    return DeploysBlock(recent=[])


@app.get("/metrics/requests")
async def metrics_requests(
    range: str = Query("6h", pattern="^(1h|6h|24h|7d|30d)$"),
    traffic: str = Query("app", pattern="^(app|static|monitor|noise|unknown)$"),
    method: str = Query("all"),
    status: str = Query("all", pattern="^(all|2xx|3xx|4xx|5xx)$"),
    q: str = Query(""),
    rank: str = Query("p95", pattern="^(p95|count|error_rate)$"),
) -> JSONResponse:
    filters = RequestFilters(
        traffic=cast(TrafficClass, traffic),
        method=method,
        status=cast(StatusBand, status),
        q=q,
        rank=cast(RankMode, rank),
    )
    block = await requests_coll.collect(range, filters)
    return JSONResponse(block.model_dump(mode="json", by_alias=True))


@app.get("/metrics/requests/debug")
async def metrics_requests_debug(
    range: str = Query("6h", pattern="^(1h|6h|24h|7d|30d)$"),
    traffic: str = Query("app", pattern="^(app|static|monitor|noise|unknown)$"),
    method: str = Query("all"),
    status: str = Query("all", pattern="^(all|2xx|3xx|4xx|5xx)$"),
    q: str = Query(""),
    rank: str = Query("p95", pattern="^(p95|count|error_rate)$"),
    limit: int = Query(25, ge=1, le=100),
) -> JSONResponse:
    filters = RequestFilters(
        traffic=cast(TrafficClass, traffic),
        method=method,
        status=cast(StatusBand, status),
        q=q,
        rank=cast(RankMode, rank),
    )
    window_records = records_for_window(list(bg.NGINX_ACCESS_RECORDS), range)
    debug = build_request_debug(window_records, filters, limit, sampler_meta=dict(bg.NGINX_SAMPLER_META))
    validated = RequestDebugResponse.model_validate(debug)
    return JSONResponse(validated.model_dump(mode="json"))


@app.get("/metrics/service/{name}")
async def metrics_service(name: str) -> JSONResponse:
    entry = bg.SERVICE_CACHE.get(name)
    if not entry:
        raise HTTPException(status_code=404, detail=f"unknown service: {name}")
    from monitor.schema import ServiceBlock
    block = ServiceBlock.model_validate(entry)
    return JSONResponse(block.model_dump(mode="json"))


@app.get("/metrics/logs/stream")
async def metrics_logs_stream(
    request: Request,
    service: str | None = Query(default=None),
    level: str = Query(default="debug", pattern="^(debug|info|warn|error)$"),
    q: str | None = Query(default=None),
) -> StreamingResponse:
    services = {s.strip() for s in service.split(",") if s.strip()} if service else None
    filt = logs_stream.LogFilter(services=services, min_level=level, q=q or None)

    async def gen():
        async for frame in logs_stream.subscribe(filt):
            if await request.is_disconnected():
                break
            yield frame

    return StreamingResponse(
        gen(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
            "Connection": "keep-alive",
        },
    )


@app.get("/metrics/endpoint")
async def metrics_endpoint(
    path: str = Query(..., min_length=1),
    method: str = Query("GET"),
    range: str = Query("6h", pattern="^(1h|6h|24h|7d|30d)$"),
) -> JSONResponse:
    cache_for_window = bg.NGINX_ENDPOINT_CACHE.get(range, {})
    buckets = cache_for_window.get((method, path))
    if not buckets:
        raise HTTPException(
            status_code=404,
            detail=f"no data for {method} {path} in window {range}",
        )
    total = sum(b["count"] for b in buckets)
    err = sum(b["status_4xx"] + b["status_5xx"] for b in buckets)
    error_rate = (err / total * 100.0) if total else 0.0
    peak_p99 = max((b["p99_ms"] for b in buckets), default=0)
    detail = EndpointDetail(
        method=method, path=path, window=range,  # type: ignore[arg-type]
        total_requests=total,
        error_rate_pct=round(error_rate, 2),
        peak_p99_ms=int(peak_p99),
        buckets=buckets,  # type: ignore[arg-type]
    )
    return JSONResponse(detail.model_dump(mode="json"))


def _serialize(data):
    if data is None:
        return None
    if hasattr(data, "model_dump"):
        return data.model_dump(mode="json", by_alias=True)
    if isinstance(data, list):
        return [_serialize(d) for d in data]
    return data


def _build_sha() -> str:
    if sha := os.getenv("MONITOR_BUILD_SHA"):
        return sha[:7]
    try:
        out = subprocess.run(
            ["git", "-C", str(Path(__file__).resolve().parents[2]),
             "rev-parse", "--short", "HEAD"],
            capture_output=True, text=True, timeout=1,
        )
        return out.stdout.strip() or "unknown"
    except Exception:
        return "unknown"
