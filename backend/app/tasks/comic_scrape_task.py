import logging
import time
import uuid
from datetime import datetime, timezone
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.database import AsyncSessionLocal
from app.models.comic import Comic, ComicChapter, Page
from app.models.scrape import ScrapeJob, ScrapeLog
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


def _add_log(
    db: AsyncSession,
    job_id: uuid.UUID,
    level: str,
    step: str,
    message: str,
    error_type: str | None = None,
    http_status: int | None = None,
    duration_ms: int | None = None,
    chapter_number: float | None = None,
) -> None:
    """Stage a ScrapeLog row — caller is responsible for committing."""
    db.add(ScrapeLog(
        job_id=job_id,
        level=level,
        step=step,
        message=message,
        error_type=error_type,
        http_status=http_status,
        duration_ms=duration_ms,
        chapter_number=chapter_number,
    ))


async def comic_scrape_task(ctx, job_id: str):
    """ARQ task: scrapes a comic per-chapter with per-step structured logging."""
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
        job.current_step = "starting"
        await db.commit()
        logger.info("comic_scrape_task status=RUNNING | job_id=%s source_key=%s", job_id, job.source_key)

        scraper_class = SCRAPER_REGISTRY.get(job.source_key)
        if not scraper_class:
            job.status = JobStatus.FAILED
            job.error_message = f"Unknown source_key: {job.source_key}"
            job.last_error_type = "UnknownSource"
            job.current_step = "failed"
            job.completed_at = datetime.now(timezone.utc)
            _add_log(db, job_uuid, "error", "start",
                     f"Unknown source_key '{job.source_key}' — no scraper registered",
                     error_type="UnknownSource")
            await db.commit()
            logger.error("comic_scrape_task unknown source_key | job_id=%s source_key=%s", job_id, job.source_key)
            return

        scraper = scraper_class()

        try:
            # ── Metadata ────────────────────────────────────────────────────
            job.current_step = "metadata"
            await db.commit()

            step_start = time.perf_counter()
            try:
                metadata = await scraper.get_story_metadata(job.source_url)
                dur = int((time.perf_counter() - step_start) * 1000)
                logger.info("comic_scrape_task metadata ok | job_id=%s title=%r", job_id, metadata.title)
                _add_log(db, job_uuid, "info", "metadata",
                         f"Fetched metadata: {metadata.title!r} — total_chapters={metadata.total_chapters}",
                         duration_ms=dur)
            except Exception as e:
                dur = int((time.perf_counter() - step_start) * 1000)
                _add_log(db, job_uuid, "error", "metadata",
                         f"Failed to fetch metadata: {e}",
                         error_type=type(e).__name__, duration_ms=dur)
                raise

            result = await db.execute(select(Comic).where(Comic.id == job.story_id))
            comic = result.scalar_one_or_none()
            if comic:
                comic.title = metadata.title
                if metadata.description is not None:
                    comic.description = metadata.description
                if metadata.language is not None:
                    comic.language = metadata.language
                if metadata.source_id is not None:
                    comic.source_id = metadata.source_id
                if metadata.total_chapters:
                    comic.total_chapters = metadata.total_chapters
                    job.total_chapters = metadata.total_chapters
            await db.commit()

            # ── Chapter list ────────────────────────────────────────────────
            job.current_step = "chapter_list"
            await db.commit()

            step_start = time.perf_counter()
            try:
                chapter_list = await scraper.get_chapter_list(job.source_url)
                dur = int((time.perf_counter() - step_start) * 1000)
                logger.info("comic_scrape_task chapter list | job_id=%s count=%d", job_id, len(chapter_list))
                _add_log(db, job_uuid, "info", "chapter_list",
                         f"Discovered {len(chapter_list)} chapters", duration_ms=dur)
            except Exception as e:
                dur = int((time.perf_counter() - step_start) * 1000)
                _add_log(db, job_uuid, "error", "chapter_list",
                         f"Failed to fetch chapter list: {e}",
                         error_type=type(e).__name__, duration_ms=dur)
                raise

            for ch_info in chapter_list:
                existing = await db.execute(
                    select(ComicChapter).where(
                        ComicChapter.comic_id == job.story_id,
                        ComicChapter.chapter_number == ch_info.chapter_number,
                        ComicChapter.deleted_at.is_(None),
                    )
                )
                if not existing.scalar_one_or_none():
                    db.add(ComicChapter(
                        comic_id=job.story_id,
                        chapter_number=ch_info.chapter_number,
                        title=ch_info.title,
                        source_url=ch_info.source_url,
                        scrape_status=ScrapeStatus.PENDING,
                    ))
            await db.commit()

            pending_result = await db.execute(
                select(ComicChapter).where(
                    ComicChapter.comic_id == job.story_id,
                    ComicChapter.scrape_status.in_([ScrapeStatus.PENDING, ScrapeStatus.FAILED]),
                    ComicChapter.deleted_at.is_(None),
                ).order_by(ComicChapter.chapter_number)
            )
            chapters_to_scrape = pending_result.scalars().all()
            logger.info("comic_scrape_task chapters to scrape | job_id=%s count=%d", job_id, len(chapters_to_scrape))

            # ── Per-chapter scrape ──────────────────────────────────────────
            for chapter in chapters_to_scrape:
                ch_label = f"chapter_{int(chapter.chapter_number)}"
                job.current_step = ch_label
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
                            db.add(Page(
                                chapter_id=chapter.id,
                                page_number=page_info.page_number,
                                file_path=file_path,
                                source_url=page_info.source_url,
                                width_px=page_info.width_px,
                                height_px=page_info.height_px,
                            ))
                        else:
                            page.file_path = file_path

                    chapter.total_pages = len(pages)
                    chapter.scrape_status = ScrapeStatus.SCRAPED
                    job.chapters_scraped += 1
                    dur = int((time.perf_counter() - ch_start) * 1000)
                    _add_log(db, job_uuid, "info", ch_label,
                             f"Scraped {len(pages)} pages",
                             duration_ms=dur, chapter_number=chapter.chapter_number)
                    await db.commit()
                    logger.info("comic_scrape_task chapter ok | job_id=%s chapter=%.1f pages=%d",
                                job_id, chapter.chapter_number, len(pages))

                except CookieExpiredError:
                    chapter.scrape_status = ScrapeStatus.FAILED
                    job.chapters_failed += 1
                    job.error_message = "Cookie expired — re-open the browser on iOS to refresh"
                    job.last_error_type = "CookieExpiredError"
                    dur = int((time.perf_counter() - ch_start) * 1000)
                    _add_log(db, job_uuid, "error", ch_label,
                             "Cookie expired — iOS browser refresh required to continue",
                             error_type="CookieExpiredError", duration_ms=dur,
                             chapter_number=chapter.chapter_number)
                    await db.commit()
                    logger.error("comic_scrape_task cookie expired | job_id=%s chapter=%.1f",
                                 job_id, chapter.chapter_number)
                    break

                except Exception as e:
                    chapter.scrape_status = ScrapeStatus.FAILED
                    job.chapters_failed += 1
                    job.error_message = str(e)
                    job.last_error_type = type(e).__name__
                    dur = int((time.perf_counter() - ch_start) * 1000)
                    _add_log(db, job_uuid, "error", ch_label,
                             f"Chapter failed: {e}",
                             error_type=type(e).__name__, duration_ms=dur,
                             chapter_number=chapter.chapter_number)
                    await db.commit()
                    logger.error("comic_scrape_task chapter failed | job_id=%s chapter=%.1f error=%s",
                                 job_id, chapter.chapter_number, e)

        except CookieExpiredError:
            job.status = JobStatus.FAILED
            job.error_message = (
                f"Session expired for {job.source_key} — open the browser tab "
                "and navigate to any page to refresh cookies, then retry."
            )
            job.last_error_type = "CookieExpiredError"
            job.current_step = "failed"
            job.completed_at = datetime.now(timezone.utc)
            _add_log(db, job_uuid, "error", "failed",
                     job.error_message, error_type="CookieExpiredError")
            await db.commit()
            total_elapsed = (time.perf_counter() - task_start) * 1000
            logger.error("comic_scrape_task cookie expired | job_id=%s source=%s elapsed_ms=%.0f",
                         job_id, job.source_key, total_elapsed)
            return

        except Exception as e:
            job.status = JobStatus.FAILED
            job.error_message = f"{type(e).__name__}: {e}" if str(e) else type(e).__name__
            job.last_error_type = type(e).__name__
            job.current_step = "failed"
            job.completed_at = datetime.now(timezone.utc)
            await db.commit()
            total_elapsed = (time.perf_counter() - task_start) * 1000
            logger.error("comic_scrape_task fatal error | job_id=%s error=%s elapsed_ms=%.0f",
                         job_id, job.error_message, total_elapsed, exc_info=True)
            return

        job.status = JobStatus.COMPLETE if job.chapters_failed == 0 else JobStatus.PARTIAL
        job.current_step = "done"
        job.completed_at = datetime.now(timezone.utc)

        result = await db.execute(select(Comic).where(Comic.id == job.story_id))
        comic = result.scalar_one_or_none()
        if comic:
            comic.status = "complete" if job.chapters_failed == 0 else "partial"

        total_ms = int((time.perf_counter() - task_start) * 1000)
        _add_log(db, job_uuid, "info", "done",
                 f"Finished — status={job.status} scraped={job.chapters_scraped} failed={job.chapters_failed}",
                 duration_ms=total_ms)
        await db.commit()

        logger.info("comic_scrape_task finished | job_id=%s status=%s scraped=%d failed=%d elapsed_ms=%d",
                    job_id, job.status, job.chapters_scraped, job.chapters_failed, total_ms)
