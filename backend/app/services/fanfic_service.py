import logging
import uuid
from datetime import datetime, timezone
from typing import Optional
from math import ceil
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload
from app.models.fanfic import Fanfic, FanficChapter, FanficAuthor
from app.schemas.fanfic import FanficResponse, FanficChapterResponse
from app.schemas.shared import PaginatedResponse, AuthorResponse

logger = logging.getLogger(__name__)


def _chapter_to_schema(ch: FanficChapter, include_content: bool = False) -> FanficChapterResponse:
    return FanficChapterResponse(
        id=ch.id,
        chapter_number=ch.chapter_number,
        title=ch.title,
        content=ch.content if include_content else None,
        word_count=ch.word_count,
        source_url=ch.source_url,
        scrape_status=ch.scrape_status,
        created_at=ch.created_at,
    )


def _fanfic_to_schema(fanfic: Fanfic, include_chapters: bool = False) -> FanficResponse:
    authors = []
    for fa in (fanfic.fanfic_authors or []):
        if fa.author:
            authors.append(AuthorResponse(id=fa.author.id, name=fa.author.name))

    chapters = None
    if include_chapters and fanfic.chapters is not None:
        chapters = [_chapter_to_schema(ch) for ch in fanfic.chapters if ch.deleted_at is None]

    return FanficResponse(
        id=fanfic.id,
        title=fanfic.title,
        source_key=fanfic.source_key,
        source_url=fanfic.source_url,
        source_id=fanfic.source_id,
        summary=fanfic.summary,
        fandom=fanfic.fandom,
        relationship=fanfic.pairing,
        characters=fanfic.characters,
        rating=fanfic.rating,
        warnings=fanfic.warnings,
        completion_status=fanfic.completion_status,
        word_count=fanfic.word_count,
        total_chapters=fanfic.total_chapters,
        published_at=fanfic.published_at,
        updated_at_source=fanfic.updated_at_source,
        language=fanfic.language,
        freeform_tags=fanfic.freeform_tags,
        hits=fanfic.hits,
        kudos=fanfic.kudos,
        comments_count=fanfic.comments_count,
        bookmarks_count=fanfic.bookmarks_count,
        thumbnail_path=fanfic.thumbnail_path,
        authors=authors if authors else None,
        chapters=chapters,
        created_at=fanfic.created_at,
        updated_at=fanfic.updated_at,
    )


async def list_fanfics(
    db: AsyncSession,
    page: int,
    page_size: int,
    fandom: Optional[str] = None,
    rating: Optional[str] = None,
    completion_status: Optional[str] = None,
    sort: Optional[str] = None,
) -> PaginatedResponse[FanficResponse]:
    filters_applied = []
    if fandom:
        filters_applied.append(f"fandom={fandom}")
    if rating:
        filters_applied.append(f"rating={rating}")
    if completion_status:
        filters_applied.append(f"completion_status={completion_status}")
    logger.info(
        "list_fanfics called | page=%d page_size=%d sort=%s filters=[%s]",
        page, page_size, sort or "default", ", ".join(filters_applied) or "none",
    )

    conditions = [Fanfic.deleted_at.is_(None)]
    if fandom:
        conditions.append(Fanfic.fandom.ilike(f"%{fandom}%"))
    if rating:
        conditions.append(Fanfic.rating == rating)
    if completion_status:
        conditions.append(Fanfic.completion_status == completion_status)

    count_result = await db.execute(
        select(func.count()).select_from(Fanfic).where(*conditions)
    )
    total = count_result.scalar_one()
    logger.info("list_fanfics total count=%d", total)

    query = select(Fanfic).where(*conditions)
    if sort == "word_count":
        query = query.order_by(Fanfic.word_count.desc())
    elif sort == "updated":
        query = query.order_by(Fanfic.updated_at_source.desc())
    elif sort == "title":
        query = query.order_by(Fanfic.title)
    else:
        query = query.order_by(Fanfic.created_at.desc())

    query = query.options(
        selectinload(Fanfic.fanfic_authors).selectinload(FanficAuthor.author),
        selectinload(Fanfic.chapters),
    ).offset((page - 1) * page_size).limit(page_size)

    result = await db.execute(query)
    fanfics = result.scalars().all()

    logger.info("list_fanfics returning %d items for page %d", len(fanfics), page)
    total_pages = ceil(total / page_size) if total > 0 else 1
    return PaginatedResponse(
        items=[_fanfic_to_schema(f, include_chapters=True) for f in fanfics],
        total=total,
        page=page,
        page_size=page_size,
        total_pages=total_pages,
        has_next=page < total_pages,
    )


async def get_fanfic(db: AsyncSession, fanfic_id: uuid.UUID) -> Optional[FanficResponse]:
    logger.info("get_fanfic called | fanfic_id=%s", fanfic_id)
    result = await db.execute(
        select(Fanfic)
        .where(Fanfic.id == fanfic_id, Fanfic.deleted_at.is_(None))
        .options(
            selectinload(Fanfic.fanfic_authors).selectinload(FanficAuthor.author),
            selectinload(Fanfic.chapters),
        )
    )
    fanfic = result.scalar_one_or_none()
    if not fanfic:
        logger.warning("get_fanfic not found | fanfic_id=%s", fanfic_id)
        return None
    logger.info("get_fanfic found | fanfic_id=%s title=%s", fanfic_id, fanfic.title)
    return _fanfic_to_schema(fanfic, include_chapters=True)


async def get_chapter(
    db: AsyncSession,
    fanfic_id: uuid.UUID,
    chapter_id: uuid.UUID,
) -> Optional[FanficChapterResponse]:
    logger.info("get_chapter called | fanfic_id=%s chapter_id=%s", fanfic_id, chapter_id)
    result = await db.execute(
        select(FanficChapter).where(
            FanficChapter.id == chapter_id,
            FanficChapter.fanfic_id == fanfic_id,
            FanficChapter.deleted_at.is_(None),
        )
    )
    chapter = result.scalar_one_or_none()
    if not chapter:
        logger.warning("get_chapter not found | fanfic_id=%s chapter_id=%s", fanfic_id, chapter_id)
        return None
    logger.info("get_chapter found | fanfic_id=%s chapter_id=%s title=%s", fanfic_id, chapter_id, chapter.title)
    return _chapter_to_schema(chapter, include_content=True)


async def soft_delete_fanfic(db: AsyncSession, fanfic_id: uuid.UUID) -> bool:
    logger.info("soft_delete_fanfic called | fanfic_id=%s", fanfic_id)
    result = await db.execute(
        select(Fanfic).where(Fanfic.id == fanfic_id, Fanfic.deleted_at.is_(None))
    )
    fanfic = result.scalar_one_or_none()
    if not fanfic:
        logger.warning("soft_delete_fanfic not found | fanfic_id=%s", fanfic_id)
        return False
    fanfic.deleted_at = datetime.now(timezone.utc)
    await db.commit()
    logger.info("soft_delete_fanfic completed | fanfic_id=%s title=%s", fanfic_id, fanfic.title)
    return True
