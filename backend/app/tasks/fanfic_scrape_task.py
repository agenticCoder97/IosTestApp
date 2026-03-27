import logging
import time
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

logger = logging.getLogger(__name__)

SCRAPER_REGISTRY = {
    "ao3": AO3Scraper,
    "ffnet": FanfictionNetScraper,
}


async def fanfic_scrape_task(ctx, job_id: str):
    """ARQ task: scrapes a fanfic per-chapter with checkpointing."""
    task_start = time.perf_counter()
    job_uuid = uuid.UUID(job_id)
    logger.info("fanfic_scrape_task received | job_id=%s", job_id)

    async with AsyncSessionLocal() as db:
        result = await db.execute(select(ScrapeJob).where(ScrapeJob.id == job_uuid))
        job = result.scalar_one_or_none()
        if not job:
            logger.error("fanfic_scrape_task job not found | job_id=%s", job_id)
            return

        job.status = JobStatus.RUNNING
        job.started_at = datetime.now(timezone.utc)
        await db.commit()
        logger.info("fanfic_scrape_task status=RUNNING | job_id=%s source_key=%s source_url=%s", job_id, job.source_key, job.source_url)

        scraper_class = SCRAPER_REGISTRY.get(job.source_key)
        if not scraper_class:
            logger.error("fanfic_scrape_task unknown source_key | job_id=%s source_key=%s", job_id, job.source_key)
            job.status = JobStatus.FAILED
            job.error_message = f"Unknown source_key: {job.source_key}"
            job.completed_at = datetime.now(timezone.utc)
            await db.commit()
            return

        scraper = scraper_class()
        logger.info("fanfic_scrape_task scraper instantiated | job_id=%s scraper=%s", job_id, job.source_key)

        try:
            metadata = await scraper.get_story_metadata(job.source_url)
            logger.info(
                "fanfic_scrape_task metadata fetched | job_id=%s title=%s total_chapters=%s",
                job_id, metadata.title, metadata.total_chapters,
            )
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
            logger.info("fanfic_scrape_task chapter list discovered | job_id=%s count=%d", job_id, len(chapter_list))

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
            logger.info("fanfic_scrape_task chapters to scrape | job_id=%s count=%d", job_id, len(chapters_to_scrape))

            for chapter in chapters_to_scrape:
                ch_start = time.perf_counter()
                try:
                    text = await scraper.get_chapter_text(chapter.source_url)
                    chapter.content = text
                    chapter.word_count = len(text.split())
                    chapter.scrape_status = ScrapeStatus.SCRAPED
                    job.chapters_scraped += 1
                    await db.commit()
                    ch_elapsed = (time.perf_counter() - ch_start) * 1000
                    logger.info(
                        "fanfic_scrape_task chapter scraped | job_id=%s chapter=%.1f word_count=%d elapsed_ms=%.0f",
                        job_id, chapter.chapter_number, chapter.word_count, ch_elapsed,
                    )

                except CookieExpiredError:
                    chapter.scrape_status = ScrapeStatus.FAILED
                    job.chapters_failed += 1
                    job.error_message = "Cookie expired — iOS browser refresh required"
                    await db.commit()
                    logger.error(
                        "fanfic_scrape_task cookie expired mid-scrape | job_id=%s chapter=%.1f",
                        job_id, chapter.chapter_number,
                    )
                    break
                except Exception as e:
                    chapter.scrape_status = ScrapeStatus.FAILED
                    job.chapters_failed += 1
                    job.error_message = str(e)
                    await db.commit()
                    logger.error(
                        "fanfic_scrape_task chapter failed | job_id=%s chapter=%.1f error=%s",
                        job_id, chapter.chapter_number, e,
                    )

        except Exception as e:
            job.status = JobStatus.FAILED
            job.error_message = str(e)
            job.completed_at = datetime.now(timezone.utc)
            await db.commit()
            total_elapsed = (time.perf_counter() - task_start) * 1000
            logger.error(
                "fanfic_scrape_task fatal error | job_id=%s error=%s elapsed_ms=%.0f",
                job_id, e, total_elapsed,
            )
            return

        job.status = JobStatus.COMPLETE if job.chapters_failed == 0 else JobStatus.PARTIAL
        job.completed_at = datetime.now(timezone.utc)

        result = await db.execute(select(Fanfic).where(Fanfic.id == job.story_id))
        fanfic = result.scalar_one_or_none()
        if fanfic:
            fanfic.completion_status = fanfic.completion_status  # preserve source value
        await db.commit()

        total_elapsed = (time.perf_counter() - task_start) * 1000
        logger.info(
            "fanfic_scrape_task finished | job_id=%s status=%s chapters_scraped=%d chapters_failed=%d elapsed_ms=%.0f",
            job_id, job.status, job.chapters_scraped, job.chapters_failed, total_elapsed,
        )
