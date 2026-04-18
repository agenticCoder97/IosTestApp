import uuid
from datetime import datetime, timezone

import pytest
from sqlalchemy import select, and_

from tests.conftest import make_comic, make_progress, make_scrape_job
from app.models.comic import Comic, ComicChapter, Page
from app.models.progress import ReadingProgress
from app.models.scrape import ScrapeJob


async def _seed_comic(db_session):
    comic = make_comic()
    db_session.add(comic)
    await db_session.commit()
    await db_session.refresh(comic)

    chapter = ComicChapter(
        id=uuid.uuid4(),
        comic_id=comic.id,
        chapter_number=1.0,
        total_pages=2,
        scrape_status="scraped",
    )
    db_session.add(chapter)
    await db_session.commit()
    await db_session.refresh(chapter)

    for i in range(2):
        db_session.add(Page(
            id=uuid.uuid4(),
            chapter_id=chapter.id,
            page_number=i + 1,
            file_path=f"comics/{comic.id}/{chapter.id}/page_{i + 1:04d}.jpg",
        ))
    await db_session.commit()
    return comic, chapter


@pytest.mark.asyncio
async def test_permanent_delete_comic_removes_all_rows(db_session):
    comic, chapter = await _seed_comic(db_session)
    comic_id = comic.id
    chapter_id = chapter.id

    from app.services import comic_service
    result = await comic_service.permanent_delete_comic(db_session, comic_id)
    assert result is True

    # Parent row gone
    remaining_comic = (await db_session.execute(
        select(Comic).where(Comic.id == comic_id)
    )).scalar_one_or_none()
    assert remaining_comic is None

    # Child chapters gone
    remaining_chapters = (await db_session.execute(
        select(ComicChapter).where(ComicChapter.comic_id == comic_id)
    )).scalars().all()
    assert remaining_chapters == []

    # Grandchild pages gone
    remaining_pages = (await db_session.execute(
        select(Page).where(Page.chapter_id == chapter_id)
    )).scalars().all()
    assert remaining_pages == []


@pytest.mark.asyncio
async def test_permanent_delete_comic_unknown_id_is_idempotent(db_session):
    from app.services import comic_service
    result = await comic_service.permanent_delete_comic(db_session, uuid.uuid4())
    assert result is True


@pytest.mark.asyncio
async def test_permanent_delete_comic_removes_polymorphic_rows_only_for_comic(db_session):
    """Verify permanent_delete_comic deletes only its own content_type rows
    in the polymorphic reading_progress and scrape_jobs tables — bystander
    fanfic rows must survive."""
    comic, _ = await _seed_comic(db_session)
    comic_id = comic.id

    # Target rows — comic-scoped polymorphic state.
    target_progress = make_progress(content_type="comic", story_id=comic_id)
    target_job = make_scrape_job(content_type="comic", story_id=comic_id)

    # Bystander — an unrelated fanfic progress row that must NOT be touched.
    bystander_fanfic_story_id = uuid.uuid4()
    bystander_progress = make_progress(
        content_type="fanfic", story_id=bystander_fanfic_story_id
    )

    db_session.add_all([target_progress, target_job, bystander_progress])
    await db_session.commit()

    from app.services import comic_service
    result = await comic_service.permanent_delete_comic(db_session, comic_id)
    assert result is True

    # Comic-scoped reading_progress gone.
    remaining_target_progress = (await db_session.execute(
        select(ReadingProgress).where(
            and_(
                ReadingProgress.content_type == "comic",
                ReadingProgress.story_id == comic_id,
            )
        )
    )).scalars().all()
    assert remaining_target_progress == []

    # Comic-scoped scrape_jobs gone.
    remaining_target_jobs = (await db_session.execute(
        select(ScrapeJob).where(
            and_(
                ScrapeJob.content_type == "comic",
                ScrapeJob.story_id == comic_id,
            )
        )
    )).scalars().all()
    assert remaining_target_jobs == []

    # Bystander fanfic reading_progress survives.
    remaining_bystander = (await db_session.execute(
        select(ReadingProgress).where(
            and_(
                ReadingProgress.content_type == "fanfic",
                ReadingProgress.story_id == bystander_fanfic_story_id,
            )
        )
    )).scalar_one_or_none()
    assert remaining_bystander is not None
