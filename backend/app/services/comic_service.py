import logging
import uuid
from datetime import datetime, timezone
from typing import Optional
from math import ceil
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload
from app.models.comic import Comic, ComicChapter, Page, ComicAuthor, ComicTag
from app.models.author import Author
from app.models.scrape import ScrapeJob
from app.schemas.comic import ComicResponse, ComicChapterResponse, PageResponse, ComicUpdateRequest
from app.schemas.shared import PaginatedResponse, AuthorResponse, TagResponse

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
    logger.info("list_comics called | page=%d page_size=%d sort=%s", page, page_size, sort or "default")
    base_query = select(Comic).where(Comic.deleted_at.is_(None))

    count_result = await db.execute(select(func.count()).select_from(Comic).where(Comic.deleted_at.is_(None)))
    total = count_result.scalar_one()
    logger.info("list_comics total count=%d", total)

    if sort == "title":
        base_query = base_query.order_by(Comic.title)
    elif sort == "updated":
        base_query = base_query.order_by(Comic.updated_at.desc())
    else:
        base_query = base_query.order_by(Comic.created_at.desc())

    base_query = base_query.options(
        selectinload(Comic.comic_authors).selectinload(ComicAuthor.author),
        selectinload(Comic.comic_tags).selectinload(ComicTag.tag),
        selectinload(Comic.chapters),
    ).offset((page - 1) * page_size).limit(page_size)

    result = await db.execute(base_query)
    comics = result.scalars().all()

    logger.info("list_comics returning %d items for page %d", len(comics), page)
    total_pages = ceil(total / page_size) if total > 0 else 1
    return PaginatedResponse(
        items=[_comic_to_schema(c, include_chapters=True) for c in comics],
        total=total,
        page=page,
        page_size=page_size,
        total_pages=total_pages,
        has_next=page < total_pages,
    )


async def get_comic(db: AsyncSession, comic_id: uuid.UUID) -> Optional[ComicResponse]:
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
        logger.warning("get_comic not found | comic_id=%s", comic_id)
        return None
    logger.info("get_comic found | comic_id=%s title=%s", comic_id, comic.title)
    return _comic_to_schema(comic, include_chapters=True)


async def get_chapter_pages(
    db: AsyncSession,
    comic_id: uuid.UUID,
    chapter_id: uuid.UUID,
) -> list[PageResponse]:
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
    logger.info("get_chapter_pages returning %d pages | comic_id=%s chapter_id=%s", len(pages), comic_id, chapter_id)
    return [
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
    logger.info("update_comic committed | comic_id=%s", comic_id)
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
    logger.info("soft_delete_comic completed | comic_id=%s title=%s", comic_id, comic.title)
    return True
