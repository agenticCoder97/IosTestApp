import uuid
import pytest
from app.services import progress_service
from app.schemas.progress import ComicProgressRequest, FanficProgressRequest


@pytest.mark.asyncio
async def test_upsert_comic_progress_creates_new(db_session):
    story_id = uuid.uuid4()
    body = ComicProgressRequest(last_chapter_number=5, last_page_number=12)

    result = await progress_service.upsert_comic_progress(db_session, story_id, body)

    assert result.content_type == "comic"
    assert result.story_id == story_id
    assert result.last_chapter_number == 5
    assert result.last_page_number == 12
    assert result.scroll_offset_percent is None


@pytest.mark.asyncio
async def test_upsert_comic_progress_updates_existing(db_session):
    story_id = uuid.uuid4()
    await progress_service.upsert_comic_progress(
        db_session, story_id,
        ComicProgressRequest(last_chapter_number=2, last_page_number=4),
    )
    result = await progress_service.upsert_comic_progress(
        db_session, story_id,
        ComicProgressRequest(last_chapter_number=10, last_page_number=20),
    )

    assert result.last_chapter_number == 10
    assert result.last_page_number == 20


@pytest.mark.asyncio
async def test_upsert_comic_progress_page_number_optional(db_session):
    story_id = uuid.uuid4()
    result = await progress_service.upsert_comic_progress(
        db_session, story_id,
        ComicProgressRequest(last_chapter_number=1),
    )
    assert result.last_chapter_number == 1
    assert result.last_page_number is None


@pytest.mark.asyncio
async def test_upsert_fanfic_progress_creates_new(db_session):
    story_id = uuid.uuid4()
    body = FanficProgressRequest(last_chapter_number=7, scroll_offset_percent=0.42)

    result = await progress_service.upsert_fanfic_progress(db_session, story_id, body)

    assert result.content_type == "fanfic"
    assert result.story_id == story_id
    assert result.last_chapter_number == 7
    assert abs(result.scroll_offset_percent - 0.42) < 0.001
    assert result.last_page_number is None


@pytest.mark.asyncio
async def test_upsert_fanfic_progress_updates_existing(db_session):
    story_id = uuid.uuid4()
    await progress_service.upsert_fanfic_progress(
        db_session, story_id,
        FanficProgressRequest(last_chapter_number=1, scroll_offset_percent=0.1),
    )
    result = await progress_service.upsert_fanfic_progress(
        db_session, story_id,
        FanficProgressRequest(last_chapter_number=15, scroll_offset_percent=0.99),
    )

    assert result.last_chapter_number == 15
    assert abs(result.scroll_offset_percent - 0.99) < 0.001


@pytest.mark.asyncio
async def test_comic_and_fanfic_progress_are_independent(db_session):
    """Same story_id should produce two separate records by content_type."""
    story_id = uuid.uuid4()
    await progress_service.upsert_comic_progress(
        db_session, story_id,
        ComicProgressRequest(last_chapter_number=8, last_page_number=3),
    )
    await progress_service.upsert_fanfic_progress(
        db_session, story_id,
        FanficProgressRequest(last_chapter_number=2, scroll_offset_percent=0.5),
    )

    comic_prog = await progress_service.get_progress(db_session, "comic", story_id)
    fanfic_prog = await progress_service.get_progress(db_session, "fanfic", story_id)

    assert comic_prog.last_chapter_number == 8
    assert fanfic_prog.last_chapter_number == 2


@pytest.mark.asyncio
async def test_get_progress_not_found_returns_none(db_session):
    result = await progress_service.get_progress(db_session, "comic", uuid.uuid4())
    assert result is None


@pytest.mark.asyncio
async def test_get_progress_returns_correct_record(db_session):
    story_id = uuid.uuid4()
    await progress_service.upsert_fanfic_progress(
        db_session, story_id,
        FanficProgressRequest(last_chapter_number=4, scroll_offset_percent=0.75),
    )

    result = await progress_service.get_progress(db_session, "fanfic", story_id)
    assert result is not None
    assert result.last_chapter_number == 4


@pytest.mark.asyncio
async def test_upsert_updates_timestamp(db_session):
    """updated_at should advance on second upsert."""
    story_id = uuid.uuid4()
    first = await progress_service.upsert_comic_progress(
        db_session, story_id,
        ComicProgressRequest(last_chapter_number=1),
    )
    second = await progress_service.upsert_comic_progress(
        db_session, story_id,
        ComicProgressRequest(last_chapter_number=2),
    )
    assert second.updated_at >= first.updated_at
