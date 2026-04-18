import asyncio
import logging
import uuid
from datetime import datetime, timezone
from pathlib import Path
from sqlalchemy import select
from sqlalchemy.orm import selectinload
from app.db.database import AsyncSessionLocal
from app.models.comic import Comic, ComicChapter, Page
from app.core.constants import ArchiveStatus
from app.core.config import settings
from app.utils.image_utils import convert_to_webp
from app.utils.file_storage import full_path
from app.cache import redis_cache

logger = logging.getLogger(__name__)

ARCHIVE_WEBP_QUALITY = 30
CONVERSION_SEMAPHORE = 4


async def comic_archive_task(ctx: dict, comic_id: str) -> str:
    """ARQ task: compress all comic page images to WebP and delete originals."""
    logger.info("comic_archive_task start | comic_id=%s", comic_id)
    cid = uuid.UUID(comic_id)

    async with AsyncSessionLocal() as db:
        result = await db.execute(
            select(Comic)
            .where(Comic.id == cid)
            .options(selectinload(Comic.chapters).selectinload(ComicChapter.pages))
        )
        comic = result.scalar_one_or_none()
        if not comic:
            logger.error("comic_archive_task comic not found | comic_id=%s", comic_id)
            return "not_found"

        comic.archive_status = ArchiveStatus.ARCHIVING
        await db.commit()

        total_pages = 0
        converted = 0
        failed = 0
        bytes_before = 0
        bytes_after = 0
        sem = asyncio.Semaphore(CONVERSION_SEMAPHORE)

        async def convert_page(page: Page, chapter_id: str) -> None:
            nonlocal converted, failed, bytes_before, bytes_after
            async with sem:
                src = full_path(page.file_path)

                # Already converted (idempotent retry)
                if page.file_path.endswith(".webp"):
                    converted += 1
                    return

                if not src.exists():
                    logger.warning("comic_archive_task page missing | path=%s", src)
                    failed += 1
                    return

                # Build archive destination
                dest_rel = f"archive/comics/{comic_id}/{chapter_id}/page_{page.page_number:04d}.webp"
                dest = full_path(dest_rel)

                src_size = src.stat().st_size
                ok = await asyncio.to_thread(convert_to_webp, src, dest, ARCHIVE_WEBP_QUALITY)
                if ok:
                    dest_size = dest.stat().st_size
                    bytes_before += src_size
                    bytes_after += dest_size
                    # Delete original and update DB path
                    src.unlink(missing_ok=True)
                    page.file_path = dest_rel
                    converted += 1
                else:
                    failed += 1

        # Process all chapters and pages
        for chapter in (comic.chapters or []):
            if chapter.deleted_at is not None:
                continue
            pages = chapter.pages or []
            total_pages += len(pages)
            tasks = [convert_page(p, str(chapter.id)) for p in pages]
            await asyncio.gather(*tasks)
            # Commit per chapter to checkpoint progress
            await db.commit()

        # Clean up empty original directories
        comics_dir = full_path(f"comics/{comic_id}")
        if comics_dir.exists():
            _cleanup_empty_dirs(comics_dir)

        # Finalize
        comic.archive_status = ArchiveStatus.ARCHIVED
        comic.archived_at = datetime.now(timezone.utc)
        await db.commit()
        await redis_cache.invalidate_comics(comic_id)

        saved_mb = (bytes_before - bytes_after) / 1024 / 1024
        logger.info(
            "comic_archive_task complete | comic_id=%s pages=%d converted=%d failed=%d saved=%.1fMB",
            comic_id, total_pages, converted, failed, saved_mb,
        )
        return f"archived: {converted}/{total_pages} pages, saved {saved_mb:.1f}MB"


def _cleanup_empty_dirs(path: Path) -> None:
    """Remove empty directories bottom-up."""
    for child in sorted(path.rglob("*"), reverse=True):
        if child.is_dir():
            try:
                child.rmdir()  # only succeeds if empty
            except OSError:
                pass
    try:
        path.rmdir()
    except OSError:
        pass
