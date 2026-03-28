import uuid
import pytest
from tests.conftest import make_fanfic


# ---------------------------------------------------------------------------
# GET /fanfic
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_list_fanfics_empty(client):
    response = await client.get("/fanfic")
    assert response.status_code == 200
    body = response.json()
    assert body["items"] == []
    assert body["total"] == 0


@pytest.mark.asyncio
async def test_list_fanfics_returns_items(client, db_session):
    db_session.add(make_fanfic(title="A Study in Starlight"))
    db_session.add(make_fanfic(
        title="The Long Way Round",
        source_url="https://archiveofourown.org/works/99999",
    ))
    await db_session.commit()

    response = await client.get("/fanfic")
    body = response.json()
    assert body["total"] == 2


@pytest.mark.asyncio
async def test_list_fanfics_excludes_soft_deleted(client, db_session):
    from datetime import datetime, timezone

    db_session.add(make_fanfic(
        title="Active Fic",
        source_url="https://archiveofourown.org/works/111",
    ))
    db_session.add(make_fanfic(
        title="Deleted Fic",
        source_url="https://archiveofourown.org/works/222",
        deleted_at=datetime.now(timezone.utc),
    ))
    await db_session.commit()

    response = await client.get("/fanfic")
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["title"] == "Active Fic"


@pytest.mark.asyncio
async def test_list_fanfics_filter_by_fandom(client, db_session):
    db_session.add(make_fanfic(
        fandom="Harry Potter",
        source_url="https://archiveofourown.org/works/111",
    ))
    db_session.add(make_fanfic(
        fandom="Naruto",
        source_url="https://archiveofourown.org/works/222",
    ))
    await db_session.commit()

    response = await client.get("/fanfic?fandom=Harry+Potter")
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["fandom"] == "Harry Potter"


@pytest.mark.asyncio
async def test_list_fanfics_filter_by_rating(client, db_session):
    db_session.add(make_fanfic(
        rating="M",
        source_url="https://archiveofourown.org/works/111",
    ))
    db_session.add(make_fanfic(
        rating="T",
        source_url="https://archiveofourown.org/works/222",
    ))
    await db_session.commit()

    response = await client.get("/fanfic?rating=M")
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["rating"] == "M"


@pytest.mark.asyncio
async def test_list_fanfics_filter_by_completion_status(client, db_session):
    db_session.add(make_fanfic(
        completion_status="complete",
        source_url="https://archiveofourown.org/works/111",
    ))
    db_session.add(make_fanfic(
        completion_status="ongoing",
        source_url="https://archiveofourown.org/works/222",
    ))
    await db_session.commit()

    response = await client.get("/fanfic?completion_status=complete")
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["completion_status"] == "complete"


@pytest.mark.asyncio
async def test_list_fanfics_sort_word_count(client, db_session):
    db_session.add(make_fanfic(
        word_count=10000,
        source_url="https://archiveofourown.org/works/111",
    ))
    db_session.add(make_fanfic(
        word_count=50000,
        source_url="https://archiveofourown.org/works/222",
    ))
    await db_session.commit()

    response = await client.get("/fanfic?sort=word_count")
    body = response.json()
    word_counts = [f["word_count"] for f in body["items"]]
    assert word_counts == sorted(word_counts, reverse=True)


@pytest.mark.asyncio
async def test_list_fanfics_sort_title(client, db_session):
    db_session.add(make_fanfic(
        title="Zebra Fic",
        source_url="https://archiveofourown.org/works/111",
    ))
    db_session.add(make_fanfic(
        title="Alpha Fic",
        source_url="https://archiveofourown.org/works/222",
    ))
    await db_session.commit()

    response = await client.get("/fanfic?sort=title")
    body = response.json()
    titles = [f["title"] for f in body["items"]]
    assert titles == sorted(titles)


@pytest.mark.asyncio
async def test_list_fanfics_pagination(client, db_session):
    for i in range(6):
        db_session.add(make_fanfic(
            source_url=f"https://archiveofourown.org/works/{i}"
        ))
    await db_session.commit()

    response = await client.get("/fanfic?page=2&page_size=2")
    body = response.json()
    assert len(body["items"]) == 2
    assert body["total"] == 6
    assert body["total_pages"] == 3


# ---------------------------------------------------------------------------
# GET /fanfic/{fanfic_id}
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_get_fanfic_success(client, db_session):
    fanfic = make_fanfic(title="Echoes in the Void")
    db_session.add(fanfic)
    await db_session.commit()

    response = await client.get(f"/fanfic/{fanfic.id}")
    assert response.status_code == 200
    body = response.json()
    assert body["title"] == "Echoes in the Void"
    assert body["id"] == str(fanfic.id)


@pytest.mark.asyncio
async def test_get_fanfic_not_found(client):
    response = await client.get(f"/fanfic/{uuid.uuid4()}")
    assert response.status_code == 404


@pytest.mark.asyncio
async def test_get_fanfic_soft_deleted_returns_404(client, db_session):
    from datetime import datetime, timezone

    fanfic = make_fanfic(deleted_at=datetime.now(timezone.utc))
    db_session.add(fanfic)
    await db_session.commit()

    response = await client.get(f"/fanfic/{fanfic.id}")
    assert response.status_code == 404


# ---------------------------------------------------------------------------
# GET /fanfic/{fanfic_id}/chapters/{chapter_id}
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_get_fanfic_chapter_success(client, db_session):
    from app.models.fanfic import FanficChapter

    fanfic = make_fanfic()
    db_session.add(fanfic)
    chapter = FanficChapter(
        id=uuid.uuid4(),
        fanfic_id=fanfic.id,
        chapter_number=1.0,
        title="Prologue",
        content="Once upon a time...",
        word_count=500,
        scrape_status="scraped",
    )
    db_session.add(chapter)
    await db_session.commit()

    response = await client.get(f"/fanfic/{fanfic.id}/chapters/{chapter.id}")
    assert response.status_code == 200
    body = response.json()
    assert body["title"] == "Prologue"
    assert body["word_count"] == 500


@pytest.mark.asyncio
async def test_get_fanfic_chapter_not_found(client, db_session):
    fanfic = make_fanfic()
    db_session.add(fanfic)
    await db_session.commit()

    response = await client.get(f"/fanfic/{fanfic.id}/chapters/{uuid.uuid4()}")
    assert response.status_code == 404


# ---------------------------------------------------------------------------
# DELETE /fanfic/{fanfic_id}
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_delete_fanfic_success(client, db_session):
    fanfic = make_fanfic()
    db_session.add(fanfic)
    await db_session.commit()

    response = await client.delete(f"/fanfic/{fanfic.id}")
    assert response.status_code == 204

    list_resp = await client.get("/fanfic")
    assert list_resp.json()["total"] == 0


@pytest.mark.asyncio
async def test_delete_fanfic_not_found(client):
    response = await client.delete(f"/fanfic/{uuid.uuid4()}")
    assert response.status_code == 404
