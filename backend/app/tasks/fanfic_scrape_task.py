import uuid
from datetime import datetime, timezone
from sqlalchemy import select
from app.db.database import AsyncSessionLocal
from app.models.fanfic import Fanfic, FanficChapter
from app.models.scrape import ScrapeJob
from app.core.constants import ScrapeStatus, JobStatus
from app.scrapers.base import CookieExpiredError
from app.scrapers.fanfic.ao3 import AO3Scraper
from app.scrapers.fanfic.ffnet import FanfictionNetScraper

SCRAPER_REGISTRY = {
    "ao3": AO3Scraper,
    "ffnet": FanfictionNetScraper,
}


async def fanfic_scrape_task(ctx, job_id: str):
    """ARQ task: scrapes a fanfic per-chapter with checkpointing."""
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
            result = await db.execute(select(Fanfic).where(Fanfic.id == job.story_id))
            fanfic = result.scalar_one_or_none()
            if fanfic:
                fanfic.title = metadata.title
                fanfic.description = metadata.description
                fanfic.language = metadata.language
                fanfic.source_id = metadata.source_id
                if metadata.total_chapters:
                    fanfic.total_chapters = metadata.total_chapters
                    job.total_chapters = metadata.total_chapters
                await db.commit()

            chapter_list = await scraper.get_chapter_list(job.source_url)

            for ch_info in chapter_list:
                existing = await db.execute(
                    select(FanficChapter).where(
                        FanficChapter.fanfic_id == job.story_id,
                        FanficChapter.chapter_number == ch_info.chapter_number,
                        FanficChapter.deleted_at.is_(None),
                    )
                )
                chapter = existing.scalar_one_or_none()
                if not chapter:
                    chapter = FanficChapter(
                        fanfic_id=job.story_id,
                        chapter_number=ch_info.chapter_number,
                        title=ch_info.title,
                        source_url=ch_info.source_url,
                        scrape_status=ScrapeStatus.PENDING,
                    )
                    db.add(chapter)
            await db.commit()

            pending_result = await db.execute(
                select(FanficChapter).where(
                    FanficChapter.fanfic_id == job.story_id,
                    FanficChapter.scrape_status.in_([ScrapeStatus.PENDING, ScrapeStatus.FAILED]),
                    FanficChapter.deleted_at.is_(None),
                ).order_by(FanficChapter.chapter_number)
            )
            chapters_to_scrape = pending_result.scalars().all()

            for chapter in chapters_to_scrape:
                try:
                    text = await scraper.get_chapter_text(chapter.source_url)
                    chapter.content = text
                    chapter.word_count = len(text.split())
                    chapter.scrape_status = ScrapeStatus.SCRAPED
                    job.chapters_scraped += 1
                    await db.commit()

                except CookieExpiredError:
                    chapter.scrape_status = ScrapeStatus.FAILED
                    job.chapters_failed += 1
                    job.error_message = "Cookie expired — iOS browser refresh required"
                    await db.commit()
                    break
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

        result = await db.execute(select(Fanfic).where(Fanfic.id == job.story_id))
        fanfic = result.scalar_one_or_none()
        if fanfic:
            fanfic.completion_status = fanfic.completion_status  # preserve source value
        await db.commit()
