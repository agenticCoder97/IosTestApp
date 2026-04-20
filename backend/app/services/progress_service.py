import json
import logging
import uuid
from datetime import datetime, timezone
from typing import Optional
from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession
from app.models.progress import ReadingProgress
from app.schemas.progress import ComicProgressRequest, FanficProgressRequest, ProgressResponse
from app.cache import redis_cache
from app.cache.cache_ttl import CacheTTL

logger = logging.getLogger(__name__)


def _to_schema(p: ReadingProgress) -> ProgressResponse:
    return ProgressResponse(
        id=p.id,
        content_type=p.content_type,
        story_id=p.story_id,
        last_chapter_id=p.last_chapter_id,
        last_chapter_number=p.last_chapter_number,
        last_page_number=p.last_page_number,
        scroll_offset_percent=p.scroll_offset_percent,
        updated_at=p.updated_at,
    )


async def upsert_comic_progress(
    db: AsyncSession,
    story_id: uuid.UUID,
    body: ComicProgressRequest,
) -> ProgressResponse:
    logger.info(
        "upsert_comic_progress called | story_id=%s chapter_number=%s page_number=%s",
        story_id, body.last_chapter_number, body.last_page_number,
    )
    result = await db.execute(
        select(ReadingProgress).where(
            ReadingProgress.content_type == "comic",
            ReadingProgress.story_id == story_id,
        )
    )
    progress = result.scalar_one_or_none()
    if progress:
        progress.last_chapter_number = body.last_chapter_number
        progress.last_page_number = body.last_page_number
        progress.updated_at = datetime.now(timezone.utc)
        logger.info("upsert_comic_progress updated existing | story_id=%s", story_id)
    else:
        progress = ReadingProgress(
            content_type="comic",
            story_id=story_id,
            last_chapter_number=body.last_chapter_number,
            last_page_number=body.last_page_number,
        )
        db.add(progress)
        logger.info("upsert_comic_progress inserted new | story_id=%s", story_id)
    await db.commit()
    await db.refresh(progress)
    await redis_cache.invalidate_progress("comic")
    return _to_schema(progress)


async def upsert_fanfic_progress(
    db: AsyncSession,
    story_id: uuid.UUID,
    body: FanficProgressRequest,
) -> ProgressResponse:
    logger.info(
        "upsert_fanfic_progress called | story_id=%s chapter_number=%s scroll_offset=%s",
        story_id, body.last_chapter_number, body.scroll_offset_percent,
    )
    result = await db.execute(
        select(ReadingProgress).where(
            ReadingProgress.content_type == "fanfic",
            ReadingProgress.story_id == story_id,
        )
    )
    progress = result.scalar_one_or_none()
    if progress:
        progress.last_chapter_number = body.last_chapter_number
        progress.scroll_offset_percent = body.scroll_offset_percent
        progress.updated_at = datetime.now(timezone.utc)
        logger.info("upsert_fanfic_progress updated existing | story_id=%s", story_id)
    else:
        progress = ReadingProgress(
            content_type="fanfic",
            story_id=story_id,
            last_chapter_number=body.last_chapter_number,
            scroll_offset_percent=body.scroll_offset_percent,
        )
        db.add(progress)
        logger.info("upsert_fanfic_progress inserted new | story_id=%s", story_id)
    await db.commit()
    await db.refresh(progress)
    await redis_cache.invalidate_progress("fanfic")
    return _to_schema(progress)


async def get_all_progress(
    db: AsyncSession,
    content_type: str,
) -> list[ProgressResponse]:
    """Return all progress records for a content type — lets iOS hydrate the library in one call."""
    cache_key = f"progress:{content_type}"
    cached = await redis_cache.get(cache_key)
    if cached:
        logger.info("get_all_progress cache hit | content_type=%s", content_type)
        return [ProgressResponse(**p) for p in json.loads(cached)]

    result = await db.execute(
        select(ReadingProgress).where(
            ReadingProgress.content_type == content_type,
        ).order_by(ReadingProgress.updated_at.desc())
    )
    rows = result.scalars().all()
    response = [_to_schema(p) for p in rows]
    await redis_cache.set(cache_key, json.dumps([r.model_dump(mode="json") for r in response]), ttl=CacheTTL.PROGRESS)
    logger.info("get_all_progress returning %d records (cached) | content_type=%s", len(rows), content_type)
    return response


async def get_progress(
    db: AsyncSession,
    content_type: str,
    story_id: uuid.UUID,
) -> Optional[ProgressResponse]:
    logger.info("get_progress called | content_type=%s story_id=%s", content_type, story_id)
    result = await db.execute(
        select(ReadingProgress).where(
            ReadingProgress.content_type == content_type,
            ReadingProgress.story_id == story_id,
        )
    )
    progress = result.scalar_one_or_none()
    if not progress:
        logger.info("get_progress not found | content_type=%s story_id=%s", content_type, story_id)
        return None
    logger.info("get_progress found | content_type=%s story_id=%s chapter=%s", content_type, story_id, progress.last_chapter_number)
    return _to_schema(progress)
