import json
import logging
import uuid
from datetime import datetime, timezone
from typing import Optional
from math import ceil
from app.cache.redis_pool import get_arq
from app.cache.cache_ttl import CacheTTL
from sqlalchemy import select, func, delete, and_
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload, defer
from app.models.fanfic import Fanfic, FanficChapter, FanficAuthor
from app.models.scrape import ScrapeJob
from app.models.progress import ReadingProgress
from app.schemas.fanfic import FanficResponse, FanficChapterResponse
from app.schemas.shared import PaginatedResponse, AuthorResponse
from app.core.config import settings
from app.cache import redis_cache

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
    cache_key = f"fanfics:list:{page}:{page_size}:{sort or 'default'}:{fandom or ''}:{rating or ''}:{completion_status or ''}"
    cached = await redis_cache.get(cache_key)
    if cached:
        logger.info("list_fanfics cache hit | key=%s", cache_key)
        return PaginatedResponse[FanficResponse](**json.loads(cached))

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
    ).offset((page - 1) * page_size).limit(page_size)

    result = await db.execute(query)
    fanfics = result.scalars().all()

    total_pages = ceil(total / page_size) if total > 0 else 1
    response = PaginatedResponse(
        items=[_fanfic_to_schema(f, include_chapters=False) for f in fanfics],
        total=total,
        page=page,
        page_size=page_size,
        total_pages=total_pages,
        has_next=page < total_pages,
    )
    await redis_cache.set(cache_key, response.model_dump_json(), ttl=CacheTTL.LIST)
    return response


async def get_fanfic(db: AsyncSession, fanfic_id: uuid.UUID) -> Optional[FanficResponse]:
    cache_key = f"fanfic:detail:{fanfic_id}"
    cached = await redis_cache.get(cache_key)
    if cached:
        logger.info("get_fanfic cache hit | fanfic_id=%s", fanfic_id)
        return FanficResponse(**json.loads(cached))

    result = await db.execute(
        select(Fanfic)
        .where(Fanfic.id == fanfic_id, Fanfic.deleted_at.is_(None))
        .options(
            selectinload(Fanfic.fanfic_authors).selectinload(FanficAuthor.author),
            selectinload(Fanfic.chapters).defer(FanficChapter.content),
        )
    )
    fanfic = result.scalar_one_or_none()
    if not fanfic:
        return None
    response = _fanfic_to_schema(fanfic, include_chapters=True)
    await redis_cache.set(cache_key, response.model_dump_json(), ttl=CacheTTL.LIST)
    return response


async def get_chapter(
    db: AsyncSession,
    fanfic_id: uuid.UUID,
    chapter_id: uuid.UUID,
) -> Optional[FanficChapterResponse]:
    cache_key = f"fanfic_chapter:{fanfic_id}:{chapter_id}"
    cached = await redis_cache.get(cache_key)
    if cached:
        logger.info("get_chapter cache hit | key=%s", cache_key)
        return FanficChapterResponse(**json.loads(cached))

    result = await db.execute(
        select(FanficChapter).where(
            FanficChapter.id == chapter_id,
            FanficChapter.fanfic_id == fanfic_id,
            FanficChapter.deleted_at.is_(None),
        )
    )
    chapter = result.scalar_one_or_none()
    if not chapter:
        return None
    response = _chapter_to_schema(chapter, include_content=True)
    await redis_cache.set(cache_key, response.model_dump_json(), ttl=CacheTTL.CHAPTER_PAGES)
    return response


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
    await redis_cache.invalidate_fanfics(str(fanfic_id))
    return True


async def permanent_delete_fanfic(db: AsyncSession, fanfic_id: uuid.UUID) -> bool:
    """Hard-delete a fanfic and every dependent row.

    FK-safe order:
      fanfic_chapters -> fanfic_authors -> reading_progress (polymorphic)
        -> fanfics
        -> scrape_jobs (polymorphic; FK is fanfics.scrape_job_id,
           so scrape_jobs must be deleted AFTER fanfics).

    Enqueues a best-effort `fanfic_media_wipe_task` ARQ job for pipeline
    symmetry with comics (the task itself is a no-op today — fanfic has
    no per-story media dir; thumbnails come from a shared pool and must
    NOT be deleted). Idempotent: returns True even when no fanfic row
    exists (iOS retry queue safety).
    """
    logger.info("permanent_delete_fanfic called | fanfic_id=%s", fanfic_id)

    await db.execute(delete(FanficChapter).where(FanficChapter.fanfic_id == fanfic_id))
    await db.execute(delete(FanficAuthor).where(FanficAuthor.fanfic_id == fanfic_id))
    await db.execute(
        delete(ReadingProgress).where(
            and_(
                ReadingProgress.content_type == "fanfic",
                ReadingProgress.story_id == fanfic_id,
            )
        )
    )
    await db.execute(delete(Fanfic).where(Fanfic.id == fanfic_id))
    await db.execute(
        delete(ScrapeJob).where(
            and_(
                ScrapeJob.content_type == "fanfic",
                ScrapeJob.story_id == fanfic_id,
            )
        )
    )
    await db.commit()

    await redis_cache.invalidate_fanfics(str(fanfic_id))

    # Best-effort media wipe — mirrors permanent_delete_comic enqueue pattern.
    try:
        await get_arq().enqueue_job("fanfic_media_wipe_task", str(fanfic_id))
    except Exception as e:
        logger.warning(
            "permanent_delete_fanfic ARQ enqueue failed | fanfic_id=%s error=%s",
            fanfic_id,
            e,
        )

    logger.info("permanent_delete_fanfic done | fanfic_id=%s", fanfic_id)
    return True
