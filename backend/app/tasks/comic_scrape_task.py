import logging
import time
import uuid
from datetime import datetime, timezone
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.database import AsyncSessionLocal
from app.models.comic import Comic, ComicChapter, Page
from app.models.scrape import ScrapeJob
from app.core.constants import ScrapeStatus, JobStatus
from app.scrapers.base import CookieExpiredError, ScraperError
from app.scrapers.comic.nhentai import NhentaiScraper
from app.scrapers.comic.toongod import ToongodScraper
from app.scrapers.comic.hentai20 import Hentai20Scraper

logger = logging.getLogger(__name__)

SCRAPER_REGISTRY = {
    "nhentai": NhentaiScraper,
    "toongod": ToongodScraper,
    "hentai20": Hentai20Scraper,
}


async def comic_scrape_task(ctx, job_id: str):
    """ARQ task: scrapes a comic per-chapter with checkpointing."""
    task_start = time.perf_counter()
    job_uuid = uuid.UUID(job_id)
    logger.info("comic_scrape_task received | job_id=%s", job_id)

    async with AsyncSessionLocal() as db:
        result = await db.execute(select(ScrapeJob).where(ScrapeJob.id == job_uuid))
        job = result.scalar_one_or_none()
        if not job:
            logger.error("comic_scrape_task job not found | job_id=%s", job_id)
            return

        job.status = JobStatus.RUNNING
        job.started_at = datetime.now(timezone.utc)
        await db.commit()
        logger.info("comic_scrape_task status=RUNNING | job_id=%s source_key=%s source_url=%s", job_id, job.source_key, job.source_url)

        scraper_class = SCRAPER_REGISTRY.get(job.source_key)
        if not scraper_class:
            logger.error("comic_scrape_task unknown source_key | job_id=%s source_key=%s", job_id, job.source_key)
            job.status = JobStatus.FAILED
            job.error_message = f"Unknown source_key: {job.source_key}"
            job.completed_at = datetime.now(timezone.utc)
            await db.commit()
            return

        scraper = scraper_class()
        logger.info("comic_scrape_task scraper instantiated | job_id=%s scraper=%s", job_id, job.source_key)

        try:
            metadata = await scraper.get_story_metadata(job.source_url)
            logger.info(
                "comic_scrape_task metadata fetched | job_id=%s title=%s total_chapters=%s",
                job_id, metadata.title, metadata.total_chapters,
            )
            result = await db.execute(select(Comic).where(Comic.id == job.story_id))
            comic = result.scalar_one_or_none()
            if comic:
                comic.title = metadata.title
                comic.description = metadata.description
                comic.language = metadata.language
                comic.source_id = metadata.source_id
                if metadata.total_chapters:
                    comic.total_chapters = metadata.total_chapters
                    job.total_chapters = metadata.total_chapters
                await db.commit()

            chapter_list = await scraper.get_chapter_list(job.source_url)
            logger.info("comic_scrape_task chapter list discovered | job_id=%s count=%d", job_id, len(chapter_list))

            # Upsert chapter stubs
            for ch_info in chapter_list:
                existing = await db.execute(
                    select(ComicChapter).where(
                        ComicChapter.comic_id == job.story_id,
                        ComicChapter.chapter_number == ch_info.chapter_number,
                        ComicChapter.deleted_at.is_(None),
                    )
                )
                chapter = existing.scalar_one_or_none()
                if not chapter:
                    chapter = ComicChapter(
                        comic_id=job.story_id,
                        chapter_number=ch_info.chapter_number,
                        title=ch_info.title,
                        source_url=ch_info.source_url,
                        scrape_status=ScrapeStatus.PENDING,
                    )
                    db.add(chapter)
            await db.commit()

            # Scrape pending/failed chapters
            pending_result = await db.execute(
                select(ComicChapter).where(
                    ComicChapter.comic_id == job.story_id,
                    ComicChapter.scrape_status.in_([ScrapeStatus.PENDING, ScrapeStatus.FAILED]),
                    ComicChapter.deleted_at.is_(None),
                ).order_by(ComicChapter.chapter_number)
            )
            chapters_to_scrape = pending_result.scalars().all()
            logger.info("comic_scrape_task chapters to scrape | job_id=%s count=%d", job_id, len(chapters_to_scrape))

            for chapter in chapters_to_scrape:
                ch_start = time.perf_counter()
                try:
                    pages = await scraper.get_chapter_pages(chapter.source_url)
                    for page_info in pages:
                        dest_path = f"comics/{job.story_id}/{chapter.id}/page_{page_info.page_number:04d}.jpg"
                        file_path = await scraper.download_image(page_info.source_url, dest_path)

                        existing_page = await db.execute(
                            select(Page).where(
                                Page.chapter_id == chapter.id,
                                Page.page_number == page_info.page_number,
                            )
                        )
                        page = existing_page.scalar_one_or_none()
                        if not page:
                            page = Page(
                                chapter_id=chapter.id,
                                page_number=page_info.page_number,
                                file_path=file_path,
                                source_url=page_info.source_url,
                                width_px=page_info.width_px,
                                height_px=page_info.height_px,
                            )
                            db.add(page)
                        else:
                            page.file_path = file_path

                    chapter.total_pages = len(pages)
                    chapter.scrape_status = ScrapeStatus.SCRAPED
                    job.chapters_scraped += 1
                    await db.commit()
                    ch_elapsed = (time.perf_counter() - ch_start) * 1000
                    logger.info(
                        "comic_scrape_task chapter scraped | job_id=%s chapter=%.1f pages=%d elapsed_ms=%.0f",
                        job_id, chapter.chapter_number, len(pages), ch_elapsed,
                    )

                except CookieExpiredError:
                    chapter.scrape_status = ScrapeStatus.FAILED
                    job.chapters_failed += 1
                    job.error_message = "Cookie expired — iOS browser refresh required"
                    await db.commit()
                    logger.error(
                        "comic_scrape_task cookie expired mid-scrape | job_id=%s chapter=%.1f",
                        job_id, chapter.chapter_number,
                    )
                    break  # Stop — iOS needs to refresh cookies
                except Exception as e:
                    chapter.scrape_status = ScrapeStatus.FAILED
                    job.chapters_failed += 1
                    job.error_message = str(e)
                    await db.commit()
                    logger.error(
                        "comic_scrape_task chapter failed | job_id=%s chapter=%.1f error=%s",
                        job_id, chapter.chapter_number, e,
                    )

        except Exception as e:
            job.status = JobStatus.FAILED
            job.error_message = str(e)
            job.completed_at = datetime.now(timezone.utc)
            await db.commit()
            total_elapsed = (time.perf_counter() - task_start) * 1000
            logger.error(
                "comic_scrape_task fatal error | job_id=%s error=%s elapsed_ms=%.0f",
                job_id, e, total_elapsed,
            )
            return

        job.status = JobStatus.COMPLETE if job.chapters_failed == 0 else JobStatus.PARTIAL
        job.completed_at = datetime.now(timezone.utc)

        # Update comic status
        result = await db.execute(select(Comic).where(Comic.id == job.story_id))
        comic = result.scalar_one_or_none()
        if comic:
            comic.status = "complete" if job.chapters_failed == 0 else "partial"
        await db.commit()

        total_elapsed = (time.perf_counter() - task_start) * 1000
        logger.info(
            "comic_scrape_task finished | job_id=%s status=%s chapters_scraped=%d chapters_failed=%d elapsed_ms=%.0f",
            job_id, job.status, job.chapters_scraped, job.chapters_failed, total_elapsed,
        )
