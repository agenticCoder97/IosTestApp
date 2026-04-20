import uuid
from unittest.mock import AsyncMock, patch
import pytest
from tests.conftest import make_scrape_job, make_comic, make_fanfic
from app.services import scrape_service


def _patch_redis_arq():
    """Patch Redis and ARQ to prevent real network calls."""
    mock_redis = AsyncMock()
    mock_redis.set = AsyncMock()
    mock_redis.get = AsyncMock(return_value=None)
    mock_redis.aclose = AsyncMock()

    mock_arq = AsyncMock()
    mock_arq.enqueue_job = AsyncMock()
    mock_arq.aclose = AsyncMock()

    return (
        patch("app.services.scrape_service.get_cache_redis", return_value=mock_redis),
        patch("app.services.scrape_service.get_arq", return_value=mock_arq),
    )


# ---------------------------------------------------------------------------
# get_job
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_get_job_success(db_session):
    job = make_scrape_job(status="running", chapters_scraped=5, total_chapters=20)
    db_session.add(job)
    await db_session.commit()

    result = await scrape_service.get_job(db_session, job.id)
    assert result.status == "running"
    assert result.chapters_scraped == 5
    assert result.total_chapters == 20


@pytest.mark.asyncio
async def test_get_job_not_found_raises_404(db_session):
    from fastapi import HTTPException

    with pytest.raises(HTTPException) as exc_info:
        await scrape_service.get_job(db_session, uuid.uuid4())
    assert exc_info.value.status_code == 404


@pytest.mark.asyncio
async def test_get_job_soft_deleted_raises_404(db_session):
    from datetime import datetime, timezone
    from fastapi import HTTPException

    job = make_scrape_job(deleted_at=datetime.now(timezone.utc))
    db_session.add(job)
    await db_session.commit()

    with pytest.raises(HTTPException):
        await scrape_service.get_job(db_session, job.id)


# ---------------------------------------------------------------------------
# list_jobs
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_list_jobs_empty(db_session):
    result = await scrape_service.list_jobs(db_session, page=1, page_size=20)
    assert result.total == 0


@pytest.mark.asyncio
async def test_list_jobs_returns_all(db_session):
    for i in range(3):
        db_session.add(make_scrape_job(source_url=f"https://example.com/{i}"))
    await db_session.commit()

    result = await scrape_service.list_jobs(db_session, page=1, page_size=20)
    assert result.total == 3


@pytest.mark.asyncio
async def test_list_jobs_pagination(db_session):
    for i in range(5):
        db_session.add(make_scrape_job(source_url=f"https://example.com/{i}"))
    await db_session.commit()

    result = await scrape_service.list_jobs(db_session, page=1, page_size=2)
    assert len(result.items) == 2
    assert result.total == 5
    assert result.has_next is True


# ---------------------------------------------------------------------------
# retry_job
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_retry_job_creates_new_job(db_session):
    job = make_scrape_job(status="failed", content_type="comic")
    db_session.add(job)
    await db_session.commit()

    p1, p2 = _patch_redis_arq()
    with p1, p2:
        result = await scrape_service.retry_job(db_session, job.id)

    assert result.id != job.id
    assert result.job_type == "retry"
    assert result.status == "queued"
    assert result.story_id == job.story_id


@pytest.mark.asyncio
async def test_retry_job_not_found_raises_404(db_session):
    from fastapi import HTTPException

    p1, p2 = _patch_redis_arq()
    with p1, p2, pytest.raises(HTTPException) as exc_info:
        await scrape_service.retry_job(db_session, uuid.uuid4())
    assert exc_info.value.status_code == 404


# ---------------------------------------------------------------------------
# delta_update
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_delta_update_comic(db_session):
    comic = make_comic()
    db_session.add(comic)
    await db_session.commit()

    p1, p2 = _patch_redis_arq()
    with p1, p2:
        result = await scrape_service.delta_update(db_session, comic.id)

    assert result.job_type == "delta"
    assert result.content_type == "comic"
    assert result.story_id == comic.id
    assert result.source_key == comic.source_key


@pytest.mark.asyncio
async def test_delta_update_fanfic(db_session):
    fanfic = make_fanfic()
    db_session.add(fanfic)
    await db_session.commit()

    p1, p2 = _patch_redis_arq()
    with p1, p2:
        result = await scrape_service.delta_update(db_session, fanfic.id)

    assert result.job_type == "delta"
    assert result.content_type == "fanfic"


@pytest.mark.asyncio
async def test_delta_update_unknown_raises_404(db_session):
    from fastapi import HTTPException

    p1, p2 = _patch_redis_arq()
    with p1, p2, pytest.raises(HTTPException) as exc_info:
        await scrape_service.delta_update(db_session, uuid.uuid4())
    assert exc_info.value.status_code == 404
