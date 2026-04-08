import asyncio
import logging
import shutil
import uuid
from datetime import datetime, timezone
from sqlalchemy import select
from sqlalchemy.orm import selectinload
from app.db.database import AsyncSessionLocal
from app.models.comic import Comic, ComicChapter, Page
from app.models.scrape import ScrapeJob
from app.core.constants import ArchiveStatus, JobStatus, JobType, ScrapeStatus
from app.core.config import settings
from app.utils.file_storage import full_path, comic_page_path
from app.scrapers.comic.nhentai import NhentaiScraper
from app.scrapers.comic.toongod import ToongodScraper
from app.scrapers.comic.hentai20 import Hentai20Scraper

logger = logging.getLogger(__name__)

SCRAPER_REGISTRY = {
    "nhentai": NhentaiScraper,
    "toongod": ToongodScraper,
    "hentai20": Hentai20Scraper,
}

PAGE_CONCURRENCY = 8


async def comic_unarchive_task(ctx: dict, comic_id: str) -> str:
    """ARQ task: re-scrape comic pages from source to restore full-quality originals."""
    logger.info("comic_unarchive_task start | comic_id=%s", comic_id)
    cid = uuid.UUID(comic_id)

    async with AsyncSessionLocal() as db:
        result = await db.execute(
            select(Comic)
            .where(Comic.id == cid)
            .options(selectinload(Comic.chapters).selectinload(ComicChapter.pages))
        )
        comic = result.scalar_one_or_none()
        if not comic:
            logger.error("comic_unarchive_task comic not found | comic_id=%s", comic_id)
            return "not_found"

        comic.archive_status = ArchiveStatus.UNARCHIVING
        await db.commit()

        scraper_class = SCRAPER_REGISTRY.get(comic.source_key)
        if not scraper_class:
            logger.error("comic_unarchive_task unknown source | source_key=%s", comic.source_key)
            comic.archive_status = ArchiveStatus.ARCHIVED
            await db.commit()
            return f"unknown_source: {comic.source_key}"

        scraper = scraper_class()
        sem = asyncio.Semaphore(PAGE_CONCURRENCY)
        total_restored = 0
        total_failed = 0

        for chapter in (comic.chapters or []):
            if chapter.deleted_at is not None:
                continue

            # Get page list from source
            try:
                pages_info = await scraper.get_chapter_pages(chapter.source_url)
            except Exception as e:
                logger.error(
                    "comic_unarchive_task chapter_pages failed | chapter=%s error=%s",
                    chapter.chapter_number, e,
                )
                total_failed += len(chapter.pages or [])
                continue

            async def download_page(page_info, chapter_obj):
                nonlocal total_restored, total_failed
                async with sem:
                    try:
                        dest_rel = comic_page_path(
                            comic_id, str(chapter_obj.id), page_info.page_number
                        )
                        file_path = await scraper.download_image(
                            page_info.source_url, dest_rel
                        )
                        # Update page record in DB
                        existing = [p for p in (chapter_obj.pages or []) if p.page_number == page_info.page_number]
                        if existing:
                            existing[0].file_path = file_path
                        total_restored += 1
                    except Exception as e:
                        logger.warning(
                            "comic_unarchive_task page download failed | page=%d error=%s",
                            page_info.page_number, e,
                        )
                        total_failed += 1

            tasks = [download_page(pi, chapter) for pi in pages_info]
            await asyncio.gather(*tasks)
            await db.commit()

            logger.info(
                "comic_unarchive_task chapter done | chapter=%.1f restored=%d",
                chapter.chapter_number, len(pages_info),
            )

        # Clean up archive directory
        archive_dir = full_path(f"archive/comics/{comic_id}")
        if archive_dir.exists():
            shutil.rmtree(archive_dir, ignore_errors=True)
            logger.info("comic_unarchive_task cleaned archive dir | path=%s", archive_dir)

        # Finalize
        comic.archive_status = ArchiveStatus.NONE
        comic.archived_at = None
        await db.commit()

        logger.info(
            "comic_unarchive_task complete | comic_id=%s restored=%d failed=%d",
            comic_id, total_restored, total_failed,
        )
        return f"unarchived: {total_restored} pages restored, {total_failed} failed"
