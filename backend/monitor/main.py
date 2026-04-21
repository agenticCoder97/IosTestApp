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
from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles

from monitor import bg, cache
from monitor.collectors import arq, backups, cert, cost, logs as logs_coll
from monitor.collectors import requests_ as requests_coll
from monitor.collectors import services as services_coll
from monitor.collectors import storage
from monitor.schema import MetricsResponse

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

    tasks = [
        asyncio.create_task(bg.supervise(bg.docker_sampler, "docker_sampler")),
        asyncio.create_task(bg.supervise(bg.log_tailer, "log_tailer")),
        asyncio.create_task(bg.supervise(bg.nginx_access_sampler, "nginx_access_sampler")),
        asyncio.create_task(bg.supervise(bg.storage_trend_hoister, "storage_trend_hoister")),
    ]
    logger.info("monitor started: 3 bg tasks, redis=%s", _REDIS_URL)

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


@app.get("/healthz")
async def healthz() -> JSONResponse:
    return JSONResponse({"status": "ok"})


@app.get("/")
async def index() -> FileResponse:
    return FileResponse(_STATIC_DIR / "index.html", media_type="text/html")


@app.get("/metrics")
async def metrics(range: str = Query("6h", pattern="^(1h|6h|24h|7d|30d)$")) -> JSONResponse:
    redis = cache.get_cache_redis_or_none()
    collectors = [
        ("cost", cost.collect),
        ("services", services_coll.collect),
        ("requests", partial(requests_coll.collect, range)),
        ("arq", arq.collect),
        ("storage", storage.collect),
        ("backups", backups.collect),
        ("cert", cert.collect),
        ("logs", partial(logs_coll.collect, 100)),
    ]
    results = await asyncio.gather(
        *[cache.safe(c, name, redis=redis, timeout=2.0, fallback=None)
          for name, c in collectors],
    )
    payload: dict = {
        "schema_version": "1.0.0",
        "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "build": _build_sha(),
        "tenancy_ocid": os.getenv("OCI_TENANCY_OCID", "unknown"),
        "region": os.getenv("OCI_REGION", "unknown"),
        "instance_ocid": os.getenv("OCI_INSTANCE_OCID", "unknown"),
    }
    for (name, _), (data, meta) in zip(collectors, results):
        if data is None and name in ("services", "logs"):
            data = []
        payload[name] = _serialize(data)
        if meta is not None:
            payload[f"{name}_meta"] = meta

    validated = MetricsResponse.model_validate(payload)
    return JSONResponse(validated.model_dump(mode="json", by_alias=True))


@app.get("/metrics/service/{name}")
async def metrics_service(name: str) -> JSONResponse:
    entry = bg.SERVICE_CACHE.get(name)
    if not entry:
        raise HTTPException(status_code=404, detail=f"unknown service: {name}")
    from monitor.schema import ServiceBlock
    block = ServiceBlock.model_validate(entry)
    return JSONResponse(block.model_dump(mode="json"))


@app.get("/metrics/logs/stream")
async def metrics_logs_stream() -> JSONResponse:
    raise HTTPException(status_code=501, detail="log stream is a phase-2 feature")


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
