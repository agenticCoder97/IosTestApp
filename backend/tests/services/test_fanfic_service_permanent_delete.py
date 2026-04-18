import uuid
from datetime import datetime, timezone

import pytest
from sqlalchemy import select, and_

from tests.conftest import make_fanfic, make_progress, make_scrape_job
from app.models.fanfic import Fanfic, FanficChapter, FanficAuthor
from app.models.author import Author
from app.models.progress import ReadingProgress
from app.models.scrape import ScrapeJob


async def _seed_fanfic(db_session):
    fanfic = make_fanfic()
    db_session.add(fanfic)
    await db_session.commit()
    await db_session.refresh(fanfic)

    chapter = FanficChapter(
        id=uuid.uuid4(),
        fanfic_id=fanfic.id,
        chapter_number=1.0,
        title="Chapter 1",
        content="hello world",
        word_count=2,
        scrape_status="scraped",
    )
    db_session.add(chapter)

    author = Author(id=uuid.uuid4(), name=f"Author {uuid.uuid4().hex[:6]}")
    db_session.add(author)
    await db_session.commit()
    await db_session.refresh(author)

    join = FanficAuthor(fanfic_id=fanfic.id, author_id=author.id)
    db_session.add(join)
    await db_session.commit()
    await db_session.refresh(chapter)

    return fanfic, chapter, author


@pytest.mark.asyncio
async def test_permanent_delete_fanfic_removes_all_rows(db_session):
    fanfic, chapter, author = await _seed_fanfic(db_session)
    fanfic_id = fanfic.id
    chapter_id = chapter.id
    author_id = author.id

    # Polymorphic target rows — fanfic-scoped.
    target_progress = make_progress(content_type="fanfic", story_id=fanfic_id)
    target_job = make_scrape_job(content_type="fanfic", story_id=fanfic_id)

    # Bystander comic progress row that must survive.
    bystander_comic_story_id = uuid.uuid4()
    bystander_progress = make_progress(
        content_type="comic", story_id=bystander_comic_story_id
    )

    db_session.add_all([target_progress, target_job, bystander_progress])
    await db_session.commit()

    from app.services import fanfic_service
    result = await fanfic_service.permanent_delete_fanfic(db_session, fanfic_id)
    assert result is True

    # Parent fanfic row gone.
    remaining_fanfic = (await db_session.execute(
        select(Fanfic).where(Fanfic.id == fanfic_id)
    )).scalar_one_or_none()
    assert remaining_fanfic is None

    # Chapters gone.
    remaining_chapters = (await db_session.execute(
        select(FanficChapter).where(FanficChapter.fanfic_id == fanfic_id)
    )).scalars().all()
    assert remaining_chapters == []

    # FanficAuthor join rows gone (but Author row itself survives — shared).
    remaining_joins = (await db_session.execute(
        select(FanficAuthor).where(FanficAuthor.fanfic_id == fanfic_id)
    )).scalars().all()
    assert remaining_joins == []

    remaining_author = (await db_session.execute(
        select(Author).where(Author.id == author_id)
    )).scalar_one_or_none()
    assert remaining_author is not None

    # Fanfic-scoped reading_progress gone.
    remaining_target_progress = (await db_session.execute(
        select(ReadingProgress).where(
            and_(
                ReadingProgress.content_type == "fanfic",
                ReadingProgress.story_id == fanfic_id,
            )
        )
    )).scalars().all()
    assert remaining_target_progress == []

    # Fanfic-scoped scrape_jobs gone.
    remaining_target_jobs = (await db_session.execute(
        select(ScrapeJob).where(
            and_(
                ScrapeJob.content_type == "fanfic",
                ScrapeJob.story_id == fanfic_id,
            )
        )
    )).scalars().all()
    assert remaining_target_jobs == []

    # Bystander comic reading_progress survives.
    remaining_bystander = (await db_session.execute(
        select(ReadingProgress).where(
            and_(
                ReadingProgress.content_type == "comic",
                ReadingProgress.story_id == bystander_comic_story_id,
            )
        )
    )).scalar_one_or_none()
    assert remaining_bystander is not None


@pytest.mark.asyncio
async def test_permanent_delete_fanfic_unknown_id_is_idempotent(db_session):
    from app.services import fanfic_service
    result = await fanfic_service.permanent_delete_fanfic(db_session, uuid.uuid4())
    assert result is True


@pytest.mark.asyncio
async def test_permanent_delete_fanfic_cleans_fanfic_authors(db_session):
    """Double-check: FanficAuthor join rows are cleaned up even if the
    happy-path assertion changes in the future."""
    fanfic, _, _ = await _seed_fanfic(db_session)
    fanfic_id = fanfic.id

    from app.services import fanfic_service
    result = await fanfic_service.permanent_delete_fanfic(db_session, fanfic_id)
    assert result is True

    remaining_joins = (await db_session.execute(
        select(FanficAuthor).where(FanficAuthor.fanfic_id == fanfic_id)
    )).scalars().all()
    assert remaining_joins == []
