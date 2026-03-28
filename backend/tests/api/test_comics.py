import uuid
import pytest
from tests.conftest import make_comic


# ---------------------------------------------------------------------------
# GET /comics
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_list_comics_empty(client):
    response = await client.get("/comics")
    assert response.status_code == 200
    body = response.json()
    assert body["items"] == []
    assert body["total"] == 0
    assert body["page"] == 1
    assert body["has_next"] is False


@pytest.mark.asyncio
async def test_list_comics_returns_items(client, db_session):
    comic = make_comic(title="Solo Leveling")
    db_session.add(comic)
    await db_session.commit()

    response = await client.get("/comics")
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["title"] == "Solo Leveling"


@pytest.mark.asyncio
async def test_list_comics_excludes_soft_deleted(client, db_session):
    from datetime import datetime, timezone

    deleted = make_comic(title="Deleted", deleted_at=datetime.now(timezone.utc))
    active = make_comic(title="Active")
    db_session.add(deleted)
    db_session.add(active)
    await db_session.commit()

    response = await client.get("/comics")
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["title"] == "Active"


@pytest.mark.asyncio
async def test_list_comics_sort_title(client, db_session):
    db_session.add(make_comic(title="Zebra Comic"))
    db_session.add(make_comic(title="Alpha Comic"))
    await db_session.commit()

    response = await client.get("/comics?sort=title")
    body = response.json()
    titles = [c["title"] for c in body["items"]]
    assert titles == sorted(titles)


@pytest.mark.asyncio
async def test_list_comics_pagination(client, db_session):
    for i in range(5):
        db_session.add(make_comic(
            source_url=f"https://nhentai.net/g/{i}/"
        ))
    await db_session.commit()

    response = await client.get("/comics?page=1&page_size=2")
    body = response.json()
    assert len(body["items"]) == 2
    assert body["total"] == 5
    assert body["has_next"] is True
    assert body["total_pages"] == 3


# ---------------------------------------------------------------------------
# GET /comics/{comic_id}
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_get_comic_success(client, db_session):
    comic = make_comic(title="Tower of God")
    db_session.add(comic)
    await db_session.commit()

    response = await client.get(f"/comics/{comic.id}")
    assert response.status_code == 200
    assert response.json()["title"] == "Tower of God"
    assert response.json()["id"] == str(comic.id)


@pytest.mark.asyncio
async def test_get_comic_not_found(client):
    response = await client.get(f"/comics/{uuid.uuid4()}")
    assert response.status_code == 404


@pytest.mark.asyncio
async def test_get_comic_soft_deleted_returns_404(client, db_session):
    from datetime import datetime, timezone

    comic = make_comic(deleted_at=datetime.now(timezone.utc))
    db_session.add(comic)
    await db_session.commit()

    response = await client.get(f"/comics/{comic.id}")
    assert response.status_code == 404


# ---------------------------------------------------------------------------
# PATCH /comics/{comic_id}
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_update_comic_title(client, db_session):
    comic = make_comic(title="Old Title")
    db_session.add(comic)
    await db_session.commit()

    response = await client.patch(
        f"/comics/{comic.id}", json={"title": "New Title"}
    )
    assert response.status_code == 200
    assert response.json()["title"] == "New Title"


@pytest.mark.asyncio
async def test_update_comic_thumbnail(client, db_session):
    comic = make_comic()
    db_session.add(comic)
    await db_session.commit()

    response = await client.patch(
        f"/comics/{comic.id}",
        json={"thumbnail_path": "/new/path/cover.jpg"},
    )
    assert response.status_code == 200
    assert response.json()["thumbnail_path"] == "/new/path/cover.jpg"


@pytest.mark.asyncio
async def test_update_comic_not_found(client):
    response = await client.patch(
        f"/comics/{uuid.uuid4()}", json={"title": "Ghost"}
    )
    assert response.status_code == 404


# ---------------------------------------------------------------------------
# DELETE /comics/{comic_id}
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_delete_comic_success(client, db_session):
    comic = make_comic()
    db_session.add(comic)
    await db_session.commit()

    response = await client.delete(f"/comics/{comic.id}")
    assert response.status_code == 204

    # Confirm it no longer appears in list
    list_resp = await client.get("/comics")
    assert list_resp.json()["total"] == 0


@pytest.mark.asyncio
async def test_delete_comic_not_found(client):
    response = await client.delete(f"/comics/{uuid.uuid4()}")
    assert response.status_code == 404


# ---------------------------------------------------------------------------
# GET /comics/{comic_id}/chapters/{chapter_id}/pages
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_get_chapter_pages_empty(client, db_session):
    from app.models.comic import ComicChapter

    comic = make_comic()
    db_session.add(comic)
    chapter = ComicChapter(
        id=uuid.uuid4(),
        comic_id=comic.id,
        chapter_number=1.0,
        total_pages=0,
        scrape_status="pending",
    )
    db_session.add(chapter)
    await db_session.commit()

    response = await client.get(f"/comics/{comic.id}/chapters/{chapter.id}/pages")
    assert response.status_code == 200
    assert response.json() == []


@pytest.mark.asyncio
async def test_get_chapter_pages_returns_sorted(client, db_session):
    from app.models.comic import ComicChapter, Page

    comic = make_comic()
    db_session.add(comic)
    chapter = ComicChapter(
        id=uuid.uuid4(),
        comic_id=comic.id,
        chapter_number=1.0,
        total_pages=3,
        scrape_status="scraped",
    )
    db_session.add(chapter)
    for page_num in [3, 1, 2]:
        db_session.add(Page(
            id=uuid.uuid4(),
            chapter_id=chapter.id,
            page_number=page_num,
            file_path=f"/images/ch1/p{page_num}.jpg",
        ))
    await db_session.commit()

    response = await client.get(f"/comics/{comic.id}/chapters/{chapter.id}/pages")
    assert response.status_code == 200
    pages = response.json()
    assert len(pages) == 3
    assert [p["page_number"] for p in pages] == [1, 2, 3]
