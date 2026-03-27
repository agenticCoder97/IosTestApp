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

SCRAPER_REGISTRY = {
    "nhentai": NhentaiScraper,
    "toongod": ToongodScraper,
    "hentai20": Hentai20Scraper,
}


async def comic_scrape_task(ctx, job_id: str):
    """ARQ task: scrapes a comic per-chapter with checkpointing."""
    job_uuid = uuid.UUID(job_id)

    async with AsyncSessionLocal() as db:
        result = await db.execute(select(ScrapeJob).where(ScrapeJob.id == job_uuid))
        job = result.scalar_one_or_none()
        if not job:
            return

        job.status = JobStatus.RUNNING
        job.started_at = datetime.now(timezone.utc)
        await db.commit()

        scraper_class = SCRAPER_REGISTRY.get(job.source_key)
        if not scraper_class:
            job.status = JobStatus.FAILED
            job.error_message = f"Unknown source_key: {job.source_key}"
            job.completed_at = datetime.now(timezone.utc)
            await db.commit()
            return

        scraper = scraper_class()

        try:
            metadata = await scraper.get_story_metadata(job.source_url)
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

            for chapter in chapters_to_scrape:
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

                except CookieExpiredError:
                    chapter.scrape_status = ScrapeStatus.FAILED
                    job.chapters_failed += 1
                    job.error_message = "Cookie expired — iOS browser refresh required"
                    await db.commit()
                    break  # Stop — iOS needs to refresh cookies
                except Exception as e:
                    chapter.scrape_status = ScrapeStatus.FAILED
                    job.chapters_failed += 1
                    job.error_message = str(e)
                    await db.commit()

        except Exception as e:
            job.status = JobStatus.FAILED
            job.error_message = str(e)
            job.completed_at = datetime.now(timezone.utc)
            await db.commit()
            return

        job.status = JobStatus.COMPLETE if job.chapters_failed == 0 else JobStatus.PARTIAL
        job.completed_at = datetime.now(timezone.utc)

        # Update comic status
        result = await db.execute(select(Comic).where(Comic.id == job.story_id))
        comic = result.scalar_one_or_none()
        if comic:
            comic.status = "complete" if job.chapters_failed == 0 else "partial"
        await db.commit()
