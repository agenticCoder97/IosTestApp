import uuid
import pytest
from datetime import datetime, timezone
from tests.conftest import make_fanfic
from app.services import fanfic_service
from app.models.fanfic import FanficChapter


# ---------------------------------------------------------------------------
# list_fanfics
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_list_fanfics_empty(db_session):
    result = await fanfic_service.list_fanfics(db_session, page=1, page_size=20)
    assert result.total == 0
    assert result.items == []


@pytest.mark.asyncio
async def test_list_fanfics_returns_all(db_session):
    db_session.add(make_fanfic(source_url="https://ao3.org/works/1"))
    db_session.add(make_fanfic(source_url="https://ao3.org/works/2"))
    await db_session.commit()

    result = await fanfic_service.list_fanfics(db_session, page=1, page_size=20)
    assert result.total == 2


@pytest.mark.asyncio
async def test_list_fanfics_excludes_deleted(db_session):
    db_session.add(make_fanfic(
        source_url="https://ao3.org/works/live"
    ))
    db_session.add(make_fanfic(
        source_url="https://ao3.org/works/deleted",
        deleted_at=datetime.now(timezone.utc),
    ))
    await db_session.commit()

    result = await fanfic_service.list_fanfics(db_session, page=1, page_size=20)
    assert result.total == 1


@pytest.mark.asyncio
async def test_list_fanfics_filter_fandom_case_insensitive(db_session):
    db_session.add(make_fanfic(fandom="Harry Potter", source_url="https://ao3.org/works/1"))
    db_session.add(make_fanfic(fandom="Naruto", source_url="https://ao3.org/works/2"))
    await db_session.commit()

    result = await fanfic_service.list_fanfics(db_session, page=1, page_size=20, fandom="harry")
    assert result.total == 1
    assert result.items[0].fandom == "Harry Potter"


@pytest.mark.asyncio
async def test_list_fanfics_filter_rating_exact(db_session):
    db_session.add(make_fanfic(rating="M", source_url="https://ao3.org/works/1"))
    db_session.add(make_fanfic(rating="T", source_url="https://ao3.org/works/2"))
    db_session.add(make_fanfic(rating="T", source_url="https://ao3.org/works/3"))
    await db_session.commit()

    result = await fanfic_service.list_fanfics(db_session, page=1, page_size=20, rating="T")
    assert result.total == 2


@pytest.mark.asyncio
async def test_list_fanfics_filter_completion_status(db_session):
    db_session.add(make_fanfic(
        completion_status="complete", source_url="https://ao3.org/works/1"
    ))
    db_session.add(make_fanfic(
        completion_status="ongoing", source_url="https://ao3.org/works/2"
    ))
    await db_session.commit()

    result = await fanfic_service.list_fanfics(
        db_session, page=1, page_size=20, completion_status="complete"
    )
    assert result.total == 1
    assert result.items[0].completion_status == "complete"


@pytest.mark.asyncio
async def test_list_fanfics_combined_filters(db_session):
    db_session.add(make_fanfic(
        fandom="Harry Potter", rating="M", completion_status="complete",
        source_url="https://ao3.org/works/1",
    ))
    db_session.add(make_fanfic(
        fandom="Harry Potter", rating="T", completion_status="ongoing",
        source_url="https://ao3.org/works/2",
    ))
    db_session.add(make_fanfic(
        fandom="Naruto", rating="M", completion_status="complete",
        source_url="https://ao3.org/works/3",
    ))
    await db_session.commit()

    result = await fanfic_service.list_fanfics(
        db_session, page=1, page_size=20,
        fandom="Harry", rating="M", completion_status="complete",
    )
    assert result.total == 1


@pytest.mark.asyncio
async def test_list_fanfics_sort_word_count_desc(db_session):
    db_session.add(make_fanfic(word_count=10000, source_url="https://ao3.org/works/1"))
    db_session.add(make_fanfic(word_count=50000, source_url="https://ao3.org/works/2"))
    db_session.add(make_fanfic(word_count=25000, source_url="https://ao3.org/works/3"))
    await db_session.commit()

    result = await fanfic_service.list_fanfics(
        db_session, page=1, page_size=20, sort="word_count"
    )
    counts = [f.word_count for f in result.items]
    assert counts == sorted(counts, reverse=True)


@pytest.mark.asyncio
async def test_list_fanfics_sort_title(db_session):
    db_session.add(make_fanfic(title="Zephyr", source_url="https://ao3.org/works/1"))
    db_session.add(make_fanfic(title="Aardvark", source_url="https://ao3.org/works/2"))
    await db_session.commit()

    result = await fanfic_service.list_fanfics(
        db_session, page=1, page_size=20, sort="title"
    )
    titles = [f.title for f in result.items]
    assert titles == sorted(titles)


# ---------------------------------------------------------------------------
# get_fanfic
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_get_fanfic_found(db_session):
    fanfic = make_fanfic(title="A Study in Starlight")
    db_session.add(fanfic)
    await db_session.commit()

    result = await fanfic_service.get_fanfic(db_session, fanfic.id)
    assert result is not None
    assert result.title == "A Study in Starlight"


@pytest.mark.asyncio
async def test_get_fanfic_not_found(db_session):
    result = await fanfic_service.get_fanfic(db_session, uuid.uuid4())
    assert result is None


@pytest.mark.asyncio
async def test_get_fanfic_deleted_returns_none(db_session):
    fanfic = make_fanfic(deleted_at=datetime.now(timezone.utc))
    db_session.add(fanfic)
    await db_session.commit()

    result = await fanfic_service.get_fanfic(db_session, fanfic.id)
    assert result is None


@pytest.mark.asyncio
async def test_get_fanfic_includes_chapters(db_session):
    fanfic = make_fanfic()
    db_session.add(fanfic)
    ch = FanficChapter(
        id=uuid.uuid4(), fanfic_id=fanfic.id,
        chapter_number=1.0, title="Ch1",
        content="Content here.", word_count=500,
        scrape_status="scraped",
    )
    db_session.add(ch)
    await db_session.commit()

    result = await fanfic_service.get_fanfic(db_session, fanfic.id)
    assert result.chapters is not None
    assert len(result.chapters) == 1
    assert result.chapters[0].title == "Ch1"


# ---------------------------------------------------------------------------
# get_chapter
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_get_chapter_success(db_session):
    fanfic = make_fanfic()
    db_session.add(fanfic)
    ch = FanficChapter(
        id=uuid.uuid4(), fanfic_id=fanfic.id,
        chapter_number=3.0, title="The Truth",
        content="Long prose here.", word_count=8000,
        scrape_status="scraped",
    )
    db_session.add(ch)
    await db_session.commit()

    result = await fanfic_service.get_chapter(db_session, fanfic.id, ch.id)
    assert result is not None
    assert result.title == "The Truth"
    assert result.word_count == 8000


@pytest.mark.asyncio
async def test_get_chapter_wrong_fanfic_returns_none(db_session):
    fanfic_a = make_fanfic(source_url="https://ao3.org/works/a")
    fanfic_b = make_fanfic(source_url="https://ao3.org/works/b")
    db_session.add(fanfic_a)
    db_session.add(fanfic_b)
    ch = FanficChapter(
        id=uuid.uuid4(), fanfic_id=fanfic_a.id,
        chapter_number=1.0, scrape_status="scraped",
    )
    db_session.add(ch)
    await db_session.commit()

    result = await fanfic_service.get_chapter(db_session, fanfic_b.id, ch.id)
    assert result is None


@pytest.mark.asyncio
async def test_get_chapter_not_found(db_session):
    fanfic = make_fanfic()
    db_session.add(fanfic)
    await db_session.commit()

    result = await fanfic_service.get_chapter(db_session, fanfic.id, uuid.uuid4())
    assert result is None


# ---------------------------------------------------------------------------
# soft_delete_fanfic
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_soft_delete_fanfic_returns_true(db_session):
    fanfic = make_fanfic()
    db_session.add(fanfic)
    await db_session.commit()

    success = await fanfic_service.soft_delete_fanfic(db_session, fanfic.id)
    assert success is True


@pytest.mark.asyncio
async def test_soft_delete_fanfic_hides_from_list(db_session):
    fanfic = make_fanfic()
    db_session.add(fanfic)
    await db_session.commit()

    await fanfic_service.soft_delete_fanfic(db_session, fanfic.id)

    result = await fanfic_service.list_fanfics(db_session, page=1, page_size=20)
    assert result.total == 0


@pytest.mark.asyncio
async def test_soft_delete_fanfic_not_found(db_session):
    success = await fanfic_service.soft_delete_fanfic(db_session, uuid.uuid4())
    assert success is False
