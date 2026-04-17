import uuid
from datetime import datetime, timezone

import pytest
from sqlalchemy import select

from tests.conftest import make_comic
from app.models.comic import Comic, ComicChapter, Page


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
