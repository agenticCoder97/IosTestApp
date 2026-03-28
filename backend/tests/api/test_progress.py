import uuid
import pytest
from tests.conftest import make_comic, make_fanfic


@pytest.mark.asyncio
async def test_update_comic_progress_creates_new(client, db_session):
    comic = make_comic()
    db_session.add(comic)
    await db_session.commit()

    response = await client.put(
        f"/progress/comic/{comic.id}",
        json={"last_chapter_number": 5, "last_page_number": 12},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["last_chapter_number"] == 5
    assert body["last_page_number"] == 12
    assert body["content_type"] == "comic"
    assert body["story_id"] == str(comic.id)


@pytest.mark.asyncio
async def test_update_comic_progress_updates_existing(client, db_session):
    comic = make_comic()
    db_session.add(comic)
    await db_session.commit()

    # First write
    await client.put(
        f"/progress/comic/{comic.id}",
        json={"last_chapter_number": 3, "last_page_number": 5},
    )
    # Second write (update)
    response = await client.put(
        f"/progress/comic/{comic.id}",
        json={"last_chapter_number": 8, "last_page_number": 17},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["last_chapter_number"] == 8
    assert body["last_page_number"] == 17


@pytest.mark.asyncio
async def test_update_fanfic_progress_creates_new(client, db_session):
    fanfic = make_fanfic()
    db_session.add(fanfic)
    await db_session.commit()

    response = await client.put(
        f"/progress/fanfic/{fanfic.id}",
        json={"last_chapter_number": 7, "scroll_offset_percent": 0.42},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["last_chapter_number"] == 7
    assert abs(body["scroll_offset_percent"] - 0.42) < 0.001
    assert body["content_type"] == "fanfic"


@pytest.mark.asyncio
async def test_update_fanfic_progress_updates_existing(client, db_session):
    fanfic = make_fanfic()
    db_session.add(fanfic)
    await db_session.commit()

    await client.put(
        f"/progress/fanfic/{fanfic.id}",
        json={"last_chapter_number": 2, "scroll_offset_percent": 0.1},
    )
    response = await client.put(
        f"/progress/fanfic/{fanfic.id}",
        json={"last_chapter_number": 10, "scroll_offset_percent": 0.75},
    )
    body = response.json()
    assert body["last_chapter_number"] == 10
    assert abs(body["scroll_offset_percent"] - 0.75) < 0.001


@pytest.mark.asyncio
async def test_get_comic_progress_success(client, db_session):
    comic = make_comic()
    db_session.add(comic)
    await db_session.commit()

    await client.put(
        f"/progress/comic/{comic.id}",
        json={"last_chapter_number": 4, "last_page_number": 9},
    )
    response = await client.get(f"/progress/comic/{comic.id}")
    assert response.status_code == 200
    body = response.json()
    assert body["last_chapter_number"] == 4
    assert body["last_page_number"] == 9


@pytest.mark.asyncio
async def test_get_progress_not_found_returns_404(client):
    response = await client.get(f"/progress/comic/{uuid.uuid4()}")
    assert response.status_code == 404


@pytest.mark.asyncio
async def test_get_fanfic_progress_not_found_returns_404(client):
    response = await client.get(f"/progress/fanfic/{uuid.uuid4()}")
    assert response.status_code == 404


@pytest.mark.asyncio
async def test_comic_and_fanfic_progress_isolated(client, db_session):
    """Progress records for comic and fanfic with same UUID must be separate."""
    shared_id = uuid.uuid4()
    comic = make_comic(id=shared_id)
    fanfic = make_fanfic(
        id=shared_id,
        source_url="https://archiveofourown.org/works/unique-999",
    )
    db_session.add(comic)
    db_session.add(fanfic)
    await db_session.commit()

    await client.put(
        f"/progress/comic/{shared_id}",
        json={"last_chapter_number": 10, "last_page_number": 5},
    )
    await client.put(
        f"/progress/fanfic/{shared_id}",
        json={"last_chapter_number": 3, "scroll_offset_percent": 0.9},
    )

    comic_prog = (await client.get(f"/progress/comic/{shared_id}")).json()
    fanfic_prog = (await client.get(f"/progress/fanfic/{shared_id}")).json()

    assert comic_prog["last_chapter_number"] == 10
    assert fanfic_prog["last_chapter_number"] == 3
