# Must be set before any app imports so pydantic-settings can build `settings`
# without requiring a real .env file.
import os
os.environ.setdefault("DATABASE_URL", "sqlite+aiosqlite:///:memory:")
os.environ.setdefault("REDIS_URL", "redis://localhost:6379/0")

import uuid
from datetime import datetime, timezone

import pytest
import pytest_asyncio
from httpx import AsyncClient, ASGITransport
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

# ---------------------------------------------------------------------------
# Single shared in-memory SQLite engine for the entire test process.
# StaticPool ensures all connections share the same in-memory database so
# data inserted in one session is visible in the next (within a test).
# ---------------------------------------------------------------------------
_TEST_ENGINE = create_async_engine(
    "sqlite+aiosqlite:///:memory:",
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
    echo=False,
)
_TestSessionLocal = async_sessionmaker(
    _TEST_ENGINE, class_=AsyncSession, expire_on_commit=False
)


@pytest_asyncio.fixture(autouse=True)
async def reset_db():
    """Drop and recreate all tables before every test for a clean slate."""
    from app.db.database import Base

    async with _TEST_ENGINE.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    yield


@pytest_asyncio.fixture
async def db_session() -> AsyncSession:
    """Direct DB session for service-layer tests."""
    async with _TestSessionLocal() as session:
        yield session


@pytest_asyncio.fixture
async def client() -> AsyncClient:
    """
    httpx AsyncClient wired to the FastAPI app via ASGITransport.
    ASGITransport does NOT trigger lifespan startup, so we manage
    table setup ourselves in reset_db.
    """
    from app.dependencies import get_db
    from app.main import app

    async def _override_get_db():
        async with _TestSessionLocal() as session:
            yield session

    app.dependency_overrides[get_db] = _override_get_db
    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test/api/v1"
    ) as c:
        yield c
    app.dependency_overrides.clear()


# ---------------------------------------------------------------------------
# Shared factory helpers used by multiple test modules
# ---------------------------------------------------------------------------

def make_comic(**kwargs):
    from app.models.comic import Comic

    defaults = dict(
        id=uuid.uuid4(),
        title="Test Comic",
        source_key="nhentai",
        source_url=f"https://nhentai.net/g/{uuid.uuid4().hex[:8]}/",
        total_chapters=10,
        total_pages=180,
        status="complete",
        created_at=datetime.now(timezone.utc),
        updated_at=datetime.now(timezone.utc),
    )
    defaults.update(kwargs)
    return Comic(**defaults)


def make_fanfic(**kwargs):
    from app.models.fanfic import Fanfic

    defaults = dict(
        id=uuid.uuid4(),
        title="Test Fanfic",
        source_key="ao3",
        source_url=f"https://archiveofourown.org/works/{uuid.uuid4().hex[:8]}",
        completion_status="ongoing",
        total_chapters=5,
        word_count=25000,
        created_at=datetime.now(timezone.utc),
        updated_at=datetime.now(timezone.utc),
    )
    defaults.update(kwargs)
    return Fanfic(**defaults)


def make_scrape_job(**kwargs):
    from app.models.scrape import ScrapeJob

    defaults = dict(
        id=uuid.uuid4(),
        content_type="comic",
        story_id=uuid.uuid4(),
        source_url="https://nhentai.net/g/123456/",
        source_key="nhentai",
        job_type="initial",
        status="queued",
        chapters_scraped=0,
        chapters_failed=0,
        created_at=datetime.now(timezone.utc),
    )
    defaults.update(kwargs)
    return ScrapeJob(**defaults)


def make_progress(**kwargs):
    from app.models.progress import ReadingProgress

    defaults = dict(
        id=uuid.uuid4(),
        content_type="comic",
        story_id=uuid.uuid4(),
        last_chapter_number=3,
        updated_at=datetime.now(timezone.utc),
    )
    defaults.update(kwargs)
    return ReadingProgress(**defaults)
