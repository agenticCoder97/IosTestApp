import uuid
import pytest
from datetime import datetime, timezone
from tests.conftest import make_comic
from app.services import comic_service
from app.schemas.comic import ComicUpdateRequest
from app.models.comic import ComicChapter, Page


# ---------------------------------------------------------------------------
# list_comics
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_list_comics_returns_empty(db_session):
    result = await comic_service.list_comics(db_session, page=1, page_size=20)
    assert result.total == 0
    assert result.items == []
    assert result.has_next is False


@pytest.mark.asyncio
async def test_list_comics_returns_all(db_session):
    db_session.add(make_comic(source_url="https://example.com/a"))
    db_session.add(make_comic(source_url="https://example.com/b"))
    await db_session.commit()

    result = await comic_service.list_comics(db_session, page=1, page_size=20)
    assert result.total == 2
    assert len(result.items) == 2


@pytest.mark.asyncio
async def test_list_comics_skips_deleted(db_session):
    db_session.add(make_comic(
        source_url="https://example.com/deleted",
        deleted_at=datetime.now(timezone.utc),
    ))
    db_session.add(make_comic(source_url="https://example.com/live"))
    await db_session.commit()

    result = await comic_service.list_comics(db_session, page=1, page_size=20)
    assert result.total == 1


@pytest.mark.asyncio
async def test_list_comics_pagination_has_next(db_session):
    for i in range(5):
        db_session.add(make_comic(source_url=f"https://example.com/{i}"))
    await db_session.commit()

    result = await comic_service.list_comics(db_session, page=1, page_size=3)
    assert result.total == 5
    assert result.has_next is True
    assert len(result.items) == 3


@pytest.mark.asyncio
async def test_list_comics_last_page_no_next(db_session):
    for i in range(5):
        db_session.add(make_comic(source_url=f"https://example.com/{i}"))
    await db_session.commit()

    result = await comic_service.list_comics(db_session, page=2, page_size=3)
    assert len(result.items) == 2
    assert result.has_next is False


@pytest.mark.asyncio
async def test_list_comics_sort_title_ascending(db_session):
    db_session.add(make_comic(title="Zebra", source_url="https://example.com/z"))
    db_session.add(make_comic(title="Alpha", source_url="https://example.com/a"))
    await db_session.commit()

    result = await comic_service.list_comics(db_session, page=1, page_size=20, sort="title")
    titles = [c.title for c in result.items]
    assert titles == sorted(titles)


# ---------------------------------------------------------------------------
# get_comic
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_get_comic_found(db_session):
    comic = make_comic(title="Test Comic")
    db_session.add(comic)
    await db_session.commit()

    result = await comic_service.get_comic(db_session, comic.id)
    assert result is not None
    assert result.title == "Test Comic"
    assert result.id == comic.id


@pytest.mark.asyncio
async def test_get_comic_not_found_returns_none(db_session):
    result = await comic_service.get_comic(db_session, uuid.uuid4())
    assert result is None


@pytest.mark.asyncio
async def test_get_comic_deleted_returns_none(db_session):
    comic = make_comic(deleted_at=datetime.now(timezone.utc))
    db_session.add(comic)
    await db_session.commit()

    result = await comic_service.get_comic(db_session, comic.id)
    assert result is None


@pytest.mark.asyncio
async def test_get_comic_includes_chapters(db_session):
    comic = make_comic()
    db_session.add(comic)
    ch = ComicChapter(
        id=uuid.uuid4(),
        comic_id=comic.id,
        chapter_number=1.0,
        total_pages=18,
        scrape_status="scraped",
    )
    db_session.add(ch)
    await db_session.commit()

    result = await comic_service.get_comic(db_session, comic.id)
    assert result.chapters is not None
    assert len(result.chapters) == 1
    assert result.chapters[0].chapter_number == 1.0


# ---------------------------------------------------------------------------
# get_chapter_pages
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_get_chapter_pages_returns_sorted(db_session):
    comic = make_comic()
    db_session.add(comic)
    ch = ComicChapter(
        id=uuid.uuid4(), comic_id=comic.id, chapter_number=1.0,
        total_pages=3, scrape_status="scraped",
    )
    db_session.add(ch)
    for n in [3, 1, 2]:
        db_session.add(Page(
            id=uuid.uuid4(), chapter_id=ch.id,
            page_number=n, file_path=f"/images/p{n}.jpg",
        ))
    await db_session.commit()

    pages = await comic_service.get_chapter_pages(db_session, comic.id, ch.id)
    assert [p.page_number for p in pages] == [1, 2, 3]


@pytest.mark.asyncio
async def test_get_chapter_pages_wrong_comic_returns_empty(db_session):
    comic_a = make_comic(source_url="https://example.com/a")
    comic_b = make_comic(source_url="https://example.com/b")
    db_session.add(comic_a)
    db_session.add(comic_b)
    ch = ComicChapter(
        id=uuid.uuid4(), comic_id=comic_a.id, chapter_number=1.0,
        total_pages=1, scrape_status="scraped",
    )
    db_session.add(ch)
    db_session.add(Page(
        id=uuid.uuid4(), chapter_id=ch.id,
        page_number=1, file_path="/images/p1.jpg",
    ))
    await db_session.commit()

    # Query chapter against wrong comic
    pages = await comic_service.get_chapter_pages(db_session, comic_b.id, ch.id)
    assert pages == []


# ---------------------------------------------------------------------------
# update_comic
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_update_comic_title(db_session):
    comic = make_comic(title="Old")
    db_session.add(comic)
    await db_session.commit()

    result = await comic_service.update_comic(
        db_session, comic.id, ComicUpdateRequest(title="New")
    )
    assert result is not None
    assert result.title == "New"


@pytest.mark.asyncio
async def test_update_comic_thumbnail(db_session):
    comic = make_comic()
    db_session.add(comic)
    await db_session.commit()

    result = await comic_service.update_comic(
        db_session, comic.id,
        ComicUpdateRequest(thumbnail_path="/path/to/thumb.jpg"),
    )
    assert result.thumbnail_path == "/path/to/thumb.jpg"


@pytest.mark.asyncio
async def test_update_comic_not_found_returns_none(db_session):
    result = await comic_service.update_comic(
        db_session, uuid.uuid4(), ComicUpdateRequest(title="Ghost")
    )
    assert result is None


@pytest.mark.asyncio
async def test_update_comic_partial_fields(db_session):
    """Passing only title should not overwrite thumbnail_path."""
    comic = make_comic(thumbnail_path="/existing/thumb.jpg")
    db_session.add(comic)
    await db_session.commit()

    result = await comic_service.update_comic(
        db_session, comic.id, ComicUpdateRequest(title="Updated Title")
    )
    assert result.title == "Updated Title"
    assert result.thumbnail_path == "/existing/thumb.jpg"


# ---------------------------------------------------------------------------
# soft_delete_comic
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_soft_delete_comic_returns_true(db_session):
    comic = make_comic()
    db_session.add(comic)
    await db_session.commit()

    success = await comic_service.soft_delete_comic(db_session, comic.id)
    assert success is True


@pytest.mark.asyncio
async def test_soft_delete_comic_hides_from_list(db_session):
    comic = make_comic()
    db_session.add(comic)
    await db_session.commit()

    await comic_service.soft_delete_comic(db_session, comic.id)

    result = await comic_service.list_comics(db_session, page=1, page_size=20)
    assert result.total == 0


@pytest.mark.asyncio
async def test_soft_delete_comic_not_found_returns_false(db_session):
    success = await comic_service.soft_delete_comic(db_session, uuid.uuid4())
    assert success is False


@pytest.mark.asyncio
async def test_double_delete_returns_false(db_session):
    comic = make_comic()
    db_session.add(comic)
    await db_session.commit()

    await comic_service.soft_delete_comic(db_session, comic.id)
    result = await comic_service.soft_delete_comic(db_session, comic.id)
    assert result is False
