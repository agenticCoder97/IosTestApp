import json
import logging
import uuid
from datetime import datetime, timezone
from typing import Optional
from math import ceil
import redis.asyncio as aioredis
from arq.connections import ArqRedis
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload
from app.models.comic import Comic, ComicChapter, Page, ComicAuthor, ComicTag
from app.models.author import Author
from app.models.scrape import ScrapeJob
from app.schemas.comic import ComicResponse, ComicChapterResponse, PageResponse, ComicUpdateRequest
from app.schemas.shared import PaginatedResponse, AuthorResponse, TagResponse
from app.core.constants import ArchiveStatus
from app.core.config import settings
from app.cache import redis_cache

logger = logging.getLogger(__name__)


def _chapter_to_schema(ch: ComicChapter) -> ComicChapterResponse:
    return ComicChapterResponse(
        id=ch.id,
        chapter_number=ch.chapter_number,
        title=ch.title,
        source_url=ch.source_url,
        total_pages=ch.total_pages,
        scrape_status=ch.scrape_status,
        created_at=ch.created_at,
    )


def _comic_to_schema(comic: Comic, include_chapters: bool = False) -> ComicResponse:
    authors = []
    for ca in (comic.comic_authors or []):
        if ca.author:
            authors.append(AuthorResponse(id=ca.author.id, name=ca.author.name))

    tags = []
    for ct in (comic.comic_tags or []):
        if ct.tag:
            tags.append(TagResponse(id=ct.tag.id, name=ct.tag.name, tag_type=ct.tag.tag_type))

    chapters = None
    if include_chapters and comic.chapters is not None:
        chapters = [_chapter_to_schema(ch) for ch in comic.chapters if ch.deleted_at is None]

    return ComicResponse(
        id=comic.id,
        title=comic.title,
        source_key=comic.source_key,
        source_url=comic.source_url,
        source_id=comic.source_id,
        thumbnail_path=comic.thumbnail_path,
        description=comic.description,
        total_chapters=comic.total_chapters,
        total_pages=comic.total_pages,
        language=comic.language,
        status=comic.status,
        category=comic.category,
        archive_status=comic.archive_status,
        archived_at=comic.archived_at,
        authors=authors if authors else None,
        tags=tags if tags else None,
        chapters=chapters,
        created_at=comic.created_at,
        updated_at=comic.updated_at,
    )


async def list_comics(
    db: AsyncSession,
    page: int,
    page_size: int,
    sort: Optional[str] = None,
) -> PaginatedResponse[ComicResponse]:
    cache_key = f"comics:list:{page}:{page_size}:{sort or 'default'}"
    cached = await redis_cache.get(cache_key)
    if cached:
        logger.info("list_comics cache hit | key=%s", cache_key)
        return PaginatedResponse[ComicResponse](**json.loads(cached))

    logger.info("list_comics called | page=%d page_size=%d sort=%s", page, page_size, sort or "default")
    base_query = select(Comic).where(Comic.deleted_at.is_(None))

    count_result = await db.execute(select(func.count()).select_from(Comic).where(Comic.deleted_at.is_(None)))
    total = count_result.scalar_one()

    if sort == "title":
        base_query = base_query.order_by(Comic.title)
    elif sort == "updated":
        base_query = base_query.order_by(Comic.updated_at.desc())
    else:
        base_query = base_query.order_by(Comic.created_at.desc())

    base_query = base_query.options(
        selectinload(Comic.comic_authors).selectinload(ComicAuthor.author),
        selectinload(Comic.comic_tags).selectinload(ComicTag.tag),
    ).offset((page - 1) * page_size).limit(page_size)

    result = await db.execute(base_query)
    comics = result.scalars().all()

    total_pages = ceil(total / page_size) if total > 0 else 1
    response = PaginatedResponse(
        items=[_comic_to_schema(c, include_chapters=False) for c in comics],
        total=total,
        page=page,
        page_size=page_size,
        total_pages=total_pages,
        has_next=page < total_pages,
    )
    await redis_cache.set(cache_key, response.model_dump_json(), ttl=300)
    logger.info("list_comics returning %d items (cached) | page=%d", len(comics), page)
    return response


async def get_comic(db: AsyncSession, comic_id: uuid.UUID) -> Optional[ComicResponse]:
    cache_key = f"comic:detail:{comic_id}"
    cached = await redis_cache.get(cache_key)
    if cached:
        logger.info("get_comic cache hit | comic_id=%s", comic_id)
        return ComicResponse(**json.loads(cached))

    logger.info("get_comic called | comic_id=%s", comic_id)
    result = await db.execute(
        select(Comic)
        .where(Comic.id == comic_id, Comic.deleted_at.is_(None))
        .options(
            selectinload(Comic.comic_authors).selectinload(ComicAuthor.author),
            selectinload(Comic.comic_tags).selectinload(ComicTag.tag),
            selectinload(Comic.chapters),
        )
    )
    comic = result.scalar_one_or_none()
    if not comic:
        return None
    response = _comic_to_schema(comic, include_chapters=True)
    await redis_cache.set(cache_key, response.model_dump_json(), ttl=300)
    return response


async def get_chapter_pages(
    db: AsyncSession,
    comic_id: uuid.UUID,
    chapter_id: uuid.UUID,
) -> list[PageResponse]:
    cache_key = f"chapter_pages:{comic_id}:{chapter_id}"
    cached = await redis_cache.get(cache_key)
    if cached:
        logger.info("get_chapter_pages cache hit | key=%s", cache_key)
        return [PageResponse(**p) for p in json.loads(cached)]

    logger.info("get_chapter_pages called | comic_id=%s chapter_id=%s", comic_id, chapter_id)
    result = await db.execute(
        select(Page)
        .join(ComicChapter, Page.chapter_id == ComicChapter.id)
        .where(
            ComicChapter.id == chapter_id,
            ComicChapter.comic_id == comic_id,
            ComicChapter.deleted_at.is_(None),
        )
        .order_by(Page.page_number)
    )
    pages = result.scalars().all()
    response = [
        PageResponse(
            id=p.id,
            page_number=p.page_number,
            file_path=p.file_path,
            source_url=p.source_url,
            width_px=p.width_px,
            height_px=p.height_px,
        )
        for p in pages
    ]
    await redis_cache.set(cache_key, json.dumps([r.model_dump(mode="json") for r in response]), ttl=86400)
    return response


async def update_comic(
    db: AsyncSession,
    comic_id: uuid.UUID,
    body: ComicUpdateRequest,
) -> Optional[ComicResponse]:
    logger.info("update_comic called | comic_id=%s", comic_id)
    result = await db.execute(
        select(Comic).where(Comic.id == comic_id, Comic.deleted_at.is_(None))
    )
    comic = result.scalar_one_or_none()
    if not comic:
        logger.warning("update_comic not found | comic_id=%s", comic_id)
        return None

    changed_fields = []
    if body.title is not None:
        comic.title = body.title
        changed_fields.append("title")
    if body.thumbnail_path is not None:
        comic.thumbnail_path = body.thumbnail_path
        changed_fields.append("thumbnail_path")

    logger.info("update_comic applying changes | comic_id=%s fields=%s", comic_id, changed_fields)
    await db.commit()
    await db.refresh(comic)
    await redis_cache.invalidate_comics(str(comic_id))
    return _comic_to_schema(comic)


async def _load_comic_with_relations(db: AsyncSession, comic_id: uuid.UUID) -> Optional[Comic]:
    result = await db.execute(
        select(Comic)
        .where(Comic.id == comic_id, Comic.deleted_at.is_(None))
        .options(
            selectinload(Comic.comic_authors).selectinload(ComicAuthor.author),
            selectinload(Comic.comic_tags).selectinload(ComicTag.tag),
            selectinload(Comic.chapters),
        )
    )
    return result.scalar_one_or_none()


async def archive_comic(db: AsyncSession, comic_id: uuid.UUID) -> Optional[ComicResponse]:
    """Set archive_status=archiving and enqueue the archive ARQ task."""
    logger.info("archive_comic called | comic_id=%s", comic_id)
    comic = await _load_comic_with_relations(db, comic_id)
    if not comic:
        return None

    if comic.archive_status not in (ArchiveStatus.NONE, "none"):
        logger.warning("archive_comic invalid state | comic_id=%s archive_status=%s", comic_id, comic.archive_status)
        return _comic_to_schema(comic)

    comic.archive_status = ArchiveStatus.ARCHIVING
    await db.commit()
    await redis_cache.invalidate_comics(str(comic_id))

    try:
        r = await aioredis.from_url(settings.redis_url)
        arq_redis = ArqRedis(r.connection_pool)
        await arq_redis.enqueue_job("comic_archive_task", str(comic_id))
        await arq_redis.aclose()
    except Exception as e:
        logger.warning("archive_comic ARQ enqueue failed | comic_id=%s error=%s", comic_id, e)

    return _comic_to_schema(comic)


async def unarchive_comic(db: AsyncSession, comic_id: uuid.UUID) -> Optional[ComicResponse]:
    """Set archive_status=unarchiving and enqueue the unarchive ARQ task."""
    logger.info("unarchive_comic called | comic_id=%s", comic_id)
    comic = await _load_comic_with_relations(db, comic_id)
    if not comic:
        return None

    if comic.archive_status != ArchiveStatus.ARCHIVED:
        logger.warning("unarchive_comic invalid state | comic_id=%s archive_status=%s", comic_id, comic.archive_status)
        return _comic_to_schema(comic)

    comic.archive_status = ArchiveStatus.UNARCHIVING
    await db.commit()
    await redis_cache.invalidate_comics(str(comic_id))

    try:
        r = await aioredis.from_url(settings.redis_url)
        arq_redis = ArqRedis(r.connection_pool)
        await arq_redis.enqueue_job("comic_unarchive_task", str(comic_id))
        await arq_redis.aclose()
    except Exception as e:
        logger.warning("unarchive_comic ARQ enqueue failed | comic_id=%s error=%s", comic_id, e)

    return _comic_to_schema(comic)


async def soft_delete_comic(db: AsyncSession, comic_id: uuid.UUID) -> bool:
    logger.info("soft_delete_comic called | comic_id=%s", comic_id)
    result = await db.execute(
        select(Comic).where(Comic.id == comic_id, Comic.deleted_at.is_(None))
    )
    comic = result.scalar_one_or_none()
    if not comic:
        logger.warning("soft_delete_comic not found | comic_id=%s", comic_id)
        return False
    comic.deleted_at = datetime.now(timezone.utc)
    await db.commit()
    await redis_cache.invalidate_comics(str(comic_id))
    return True
