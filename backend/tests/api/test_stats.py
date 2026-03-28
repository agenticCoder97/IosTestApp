import uuid
import pytest
from datetime import datetime, timezone
from tests.conftest import make_comic, make_fanfic, make_scrape_job


@pytest.mark.asyncio
async def test_stats_empty_db(client):
    response = await client.get("/stats")
    assert response.status_code == 200
    body = response.json()
    assert body["total_comics"] == 0
    assert body["total_fanfics"] == 0
    assert body["total_pages_scraped"] == 0
    assert body["total_chapters_scraped"] == 0
    assert body["active_scrape_jobs"] == 0


@pytest.mark.asyncio
async def test_stats_counts_comics_and_fanfics(client, db_session):
    db_session.add(make_comic(source_url="https://example.com/a"))
    db_session.add(make_comic(source_url="https://example.com/b"))
    db_session.add(make_fanfic(source_url="https://ao3.org/works/1"))
    await db_session.commit()

    response = await client.get("/stats")
    body = response.json()
    assert body["total_comics"] == 2
    assert body["total_fanfics"] == 1


@pytest.mark.asyncio
async def test_stats_excludes_soft_deleted(client, db_session):
    db_session.add(make_comic(
        source_url="https://example.com/deleted",
        deleted_at=datetime.now(timezone.utc),
    ))
    db_session.add(make_comic(source_url="https://example.com/live"))
    await db_session.commit()

    response = await client.get("/stats")
    body = response.json()
    assert body["total_comics"] == 1


@pytest.mark.asyncio
async def test_stats_counts_active_jobs(client, db_session):
    db_session.add(make_scrape_job(status="queued", source_url="https://example.com/1"))
    db_session.add(make_scrape_job(status="running", source_url="https://example.com/2"))
    db_session.add(make_scrape_job(status="complete", source_url="https://example.com/3"))
    await db_session.commit()

    response = await client.get("/stats")
    body = response.json()
    assert body["active_scrape_jobs"] == 2


@pytest.mark.asyncio
async def test_stats_counts_partial_comics_as_in_progress(client, db_session):
    db_session.add(make_comic(status="partial", source_url="https://example.com/partial"))
    db_session.add(make_comic(status="complete", source_url="https://example.com/done"))
    await db_session.commit()

    response = await client.get("/stats")
    body = response.json()
    assert body["comics_in_progress"] == 1
