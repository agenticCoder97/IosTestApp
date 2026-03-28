import uuid
from unittest.mock import AsyncMock, MagicMock, patch
import pytest
from tests.conftest import make_scrape_job, make_comic, make_fanfic


# ---------------------------------------------------------------------------
# Helper: patch out Redis + ARQ so scrape initiation doesn't need real infra
# ---------------------------------------------------------------------------

def _mock_redis_and_arq():
    """Returns a combined context manager that stubs out all Redis / ARQ calls."""
    mock_redis = AsyncMock()
    mock_arq = AsyncMock()
    mock_arq.enqueue_job = AsyncMock()

    patches = [
        patch("app.services.scrape_service.aioredis.from_url", return_value=mock_redis),
        patch("app.services.scrape_service.ArqRedis", return_value=mock_arq),
    ]
    return patches


# ---------------------------------------------------------------------------
# POST /scrape/comic
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_initiate_comic_scrape(client):
    with patch("app.services.scrape_service.aioredis.from_url") as mock_redis_fn:
        mock_redis_conn = AsyncMock()
        mock_redis_conn.set = AsyncMock()
        mock_redis_conn.aclose = AsyncMock()
        mock_redis_fn.return_value = mock_redis_conn

        with patch("app.services.scrape_service.ArqRedis") as mock_arq_cls:
            mock_arq = AsyncMock()
            mock_arq.enqueue_job = AsyncMock()
            mock_arq.aclose = AsyncMock()
            mock_arq_cls.return_value = mock_arq

            response = await client.post(
                "/scrape/comic",
                json={
                    "url": "https://nhentai.net/g/123456/",
                    "source_key": "nhentai",
                    "cookies": [],
                    "user_agent": "Mozilla/5.0",
                    "content_type": "comic",
                },
            )

    assert response.status_code == 202
    body = response.json()
    assert body["status"] == "queued"
    assert body["content_type"] == "comic"
    assert body["source_key"] == "nhentai"


@pytest.mark.asyncio
async def test_initiate_fanfic_scrape(client):
    with patch("app.services.scrape_service.aioredis.from_url") as mock_redis_fn:
        mock_redis_conn = AsyncMock()
        mock_redis_conn.set = AsyncMock()
        mock_redis_conn.aclose = AsyncMock()
        mock_redis_fn.return_value = mock_redis_conn

        with patch("app.services.scrape_service.ArqRedis") as mock_arq_cls:
            mock_arq = AsyncMock()
            mock_arq.enqueue_job = AsyncMock()
            mock_arq.aclose = AsyncMock()
            mock_arq_cls.return_value = mock_arq

            response = await client.post(
                "/scrape/fanfic",
                json={
                    "url": "https://archiveofourown.org/works/1234",
                    "source_key": "ao3",
                    "cookies": [{"name": "cf_clearance", "value": "abc", "domain": ".archiveofourown.org"}],
                    "user_agent": "Mozilla/5.0",
                    "content_type": "fanfic",
                },
            )

    assert response.status_code == 202
    body = response.json()
    assert body["content_type"] == "fanfic"
    assert body["source_key"] == "ao3"


@pytest.mark.asyncio
async def test_initiate_scrape_reuses_existing_story(client, db_session):
    """Second scrape on the same URL reuses the existing Comic row."""
    existing_comic = make_comic(source_url="https://nhentai.net/g/999/")
    db_session.add(existing_comic)
    await db_session.commit()

    with patch("app.services.scrape_service.aioredis.from_url") as mock_redis_fn:
        mock_redis_conn = AsyncMock()
        mock_redis_conn.set = AsyncMock()
        mock_redis_conn.aclose = AsyncMock()
        mock_redis_fn.return_value = mock_redis_conn

        with patch("app.services.scrape_service.ArqRedis") as mock_arq_cls:
            mock_arq = AsyncMock()
            mock_arq.enqueue_job = AsyncMock()
            mock_arq.aclose = AsyncMock()
            mock_arq_cls.return_value = mock_arq

            response = await client.post(
                "/scrape/comic",
                json={
                    "url": "https://nhentai.net/g/999/",
                    "source_key": "nhentai",
                    "cookies": [],
                    "user_agent": "Mozilla/5.0",
                    "content_type": "comic",
                },
            )

    assert response.status_code == 202
    body = response.json()
    assert body["story_id"] == str(existing_comic.id)


# ---------------------------------------------------------------------------
# GET /scrape
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_list_scrape_jobs_empty(client):
    response = await client.get("/scrape")
    assert response.status_code == 200
    body = response.json()
    assert body["items"] == []
    assert body["total"] == 0


@pytest.mark.asyncio
async def test_list_scrape_jobs_returns_items(client, db_session):
    for i in range(3):
        db_session.add(make_scrape_job(
            source_url=f"https://nhentai.net/g/{i}/",
            status=["queued", "running", "complete"][i],
        ))
    await db_session.commit()

    response = await client.get("/scrape")
    body = response.json()
    assert body["total"] == 3


@pytest.mark.asyncio
async def test_list_scrape_jobs_excludes_deleted(client, db_session):
    from datetime import datetime, timezone

    db_session.add(make_scrape_job(source_url="https://nhentai.net/g/active/"))
    db_session.add(make_scrape_job(
        source_url="https://nhentai.net/g/deleted/",
        deleted_at=datetime.now(timezone.utc),
    ))
    await db_session.commit()

    response = await client.get("/scrape")
    assert response.json()["total"] == 1


# ---------------------------------------------------------------------------
# GET /scrape/{job_id}
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_get_scrape_job_success(client, db_session):
    job = make_scrape_job(status="running", chapters_scraped=5, total_chapters=10)
    db_session.add(job)
    await db_session.commit()

    response = await client.get(f"/scrape/{job.id}")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "running"
    assert body["chapters_scraped"] == 5
    assert body["total_chapters"] == 10


@pytest.mark.asyncio
async def test_get_scrape_job_not_found(client):
    response = await client.get(f"/scrape/{uuid.uuid4()}")
    assert response.status_code == 404


# ---------------------------------------------------------------------------
# POST /scrape/{job_id}/retry
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_retry_scrape_job(client, db_session):
    job = make_scrape_job(status="failed")
    db_session.add(job)
    await db_session.commit()

    with patch("app.services.scrape_service.aioredis.from_url") as mock_redis_fn:
        mock_redis_conn = AsyncMock()
        mock_redis_conn.aclose = AsyncMock()
        mock_redis_fn.return_value = mock_redis_conn

        with patch("app.services.scrape_service.ArqRedis") as mock_arq_cls:
            mock_arq = AsyncMock()
            mock_arq.enqueue_job = AsyncMock()
            mock_arq.aclose = AsyncMock()
            mock_arq_cls.return_value = mock_arq

            response = await client.post(f"/scrape/{job.id}/retry")

    assert response.status_code == 202
    body = response.json()
    assert body["job_type"] == "retry"
    assert body["status"] == "queued"
    # Should be a NEW job ID
    assert body["id"] != str(job.id)


@pytest.mark.asyncio
async def test_retry_nonexistent_job_returns_404(client):
    response = await client.post(f"/scrape/{uuid.uuid4()}/retry")
    assert response.status_code == 404


# ---------------------------------------------------------------------------
# POST /scrape/{story_id}/update (delta)
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_delta_update_comic(client, db_session):
    comic = make_comic()
    db_session.add(comic)
    await db_session.commit()

    with patch("app.services.scrape_service.aioredis.from_url") as mock_redis_fn:
        mock_redis_conn = AsyncMock()
        mock_redis_conn.aclose = AsyncMock()
        mock_redis_fn.return_value = mock_redis_conn

        with patch("app.services.scrape_service.ArqRedis") as mock_arq_cls:
            mock_arq = AsyncMock()
            mock_arq.enqueue_job = AsyncMock()
            mock_arq.aclose = AsyncMock()
            mock_arq_cls.return_value = mock_arq

            response = await client.post(f"/scrape/{comic.id}/update")

    assert response.status_code == 202
    body = response.json()
    assert body["job_type"] == "delta"
    assert body["content_type"] == "comic"
    assert body["story_id"] == str(comic.id)


@pytest.mark.asyncio
async def test_delta_update_fanfic(client, db_session):
    fanfic = make_fanfic()
    db_session.add(fanfic)
    await db_session.commit()

    with patch("app.services.scrape_service.aioredis.from_url") as mock_redis_fn:
        mock_redis_conn = AsyncMock()
        mock_redis_conn.aclose = AsyncMock()
        mock_redis_fn.return_value = mock_redis_conn

        with patch("app.services.scrape_service.ArqRedis") as mock_arq_cls:
            mock_arq = AsyncMock()
            mock_arq.enqueue_job = AsyncMock()
            mock_arq.aclose = AsyncMock()
            mock_arq_cls.return_value = mock_arq

            response = await client.post(f"/scrape/{fanfic.id}/update")

    assert response.status_code == 202
    body = response.json()
    assert body["job_type"] == "delta"
    assert body["content_type"] == "fanfic"


@pytest.mark.asyncio
async def test_delta_update_unknown_story_returns_404(client):
    with patch("app.services.scrape_service.aioredis.from_url"):
        with patch("app.services.scrape_service.ArqRedis"):
            response = await client.post(f"/scrape/{uuid.uuid4()}/update")
    assert response.status_code == 404
