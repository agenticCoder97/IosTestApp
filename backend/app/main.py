import logging
import time
from contextlib import asynccontextmanager
from pathlib import Path
from fastapi import FastAPI, Request, Response
from fastapi.staticfiles import StaticFiles
from app.core.config import settings
from app.core.logging_config import configure_logging
from app.db.database import engine, Base
from app.models import *  # noqa: F401, F403 — import all models so Base.metadata is populated
from app.api.v1.routes import comics, fanfic, scrape, authors, progress, health, stats

configure_logging()
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Astral API starting up")
    Path(settings.block_volume_path).mkdir(parents=True, exist_ok=True)
    logger.info("Running database migrations (create_all)")
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    logger.info("Database tables ensured")
    yield
    logger.info("Astral API shutting down")
    await engine.dispose()
    logger.info("Database engine disposed")


app = FastAPI(title="Astral API", version="1.0.0", lifespan=lifespan)


@app.middleware("http")
async def log_requests(request: Request, call_next) -> Response:
    start = time.perf_counter()
    logger.info(
        "Request started | method=%s path=%s query=%s client=%s",
        request.method,
        request.url.path,
        str(request.url.query) or "-",
        request.client.host if request.client else "unknown",
    )
    response = await call_next(request)
    elapsed_ms = (time.perf_counter() - start) * 1000
    logger.info(
        "Request complete | method=%s path=%s status=%d elapsed_ms=%.1f",
        request.method,
        request.url.path,
        response.status_code,
        elapsed_ms,
    )
    return response


app.mount("/static", StaticFiles(directory=settings.block_volume_path), name="static")
app.include_router(health.router, prefix="/api/v1")
app.include_router(comics.router, prefix="/api/v1")
app.include_router(fanfic.router, prefix="/api/v1")
app.include_router(scrape.router, prefix="/api/v1")
app.include_router(authors.router, prefix="/api/v1")
app.include_router(progress.router, prefix="/api/v1")
app.include_router(stats.router, prefix="/api/v1")

logger.info("Astral API routes registered")
