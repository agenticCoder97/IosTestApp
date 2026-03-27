from contextlib import asynccontextmanager
from fastapi import FastAPI
from sqlalchemy import text
from app.db.database import engine, Base
from app.models import *  # noqa: F401, F403 — import all models so Base.metadata is populated
from app.api.v1.routes import comics, fanfic, scrape, authors, progress, health


@asynccontextmanager
async def lifespan(app: FastAPI):
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield
    await engine.dispose()


app = FastAPI(title="Astral API", version="1.0.0", lifespan=lifespan)

app.include_router(health.router, prefix="/api/v1")
app.include_router(comics.router, prefix="/api/v1")
app.include_router(fanfic.router, prefix="/api/v1")
app.include_router(scrape.router, prefix="/api/v1")
app.include_router(authors.router, prefix="/api/v1")
app.include_router(progress.router, prefix="/api/v1")
