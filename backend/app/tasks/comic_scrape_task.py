import asyncio
import logging
import time
import uuid
from datetime import datetime, timezone
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.database import AsyncSessionLocal
from app.models.comic import Comic, ComicChapter, Page, ComicAuthor, ComicTag, Tag
from app.models.author import Author
from app.models.scrape import ScrapeJob, ScrapeLog
from app.core.constants import ScrapeStatus, JobStatus
from app.core.config import settings
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


async def _scrape_chapter(
    scraper,
    chapter: ComicChapter,
    job_story_id: uuid.UUID,
    job_uuid: uuid.UUID,
    ch_idx: int,
    total_chapters: int,
    page_semaphore: asyncio.Semaphore,
) -> tuple[bool, str | None, str | None]:
    """
    Scrape a single chapter's pages in parallel.
    Returns (success, error_message, error_type).
    Uses its own DB session for safe concurrent writes.
    """
    ch_label = f"chapter_{int(chapter.chapter_number)}"
    ch_start = time.perf_counter()
    chapter_id = chapter.id
    chapter_number = chapter.chapter_number
    source_url = chapter.source_url

    logger.info(
        "comic_scrape_task chapter start | job_id=%s chapter=%.1f [%d/%d] url=%s",
        job_uuid, chapter_number, ch_idx, total_chapters, source_url,
    )

    try:
        pages = await scraper.get_chapter_pages(source_url)
        logger.info(
            "comic_scrape_task pages found | job_id=%s chapter=%.1f [%d/%d] pages=%d",
            job_uuid, chapter_number, ch_idx, total_chapters, len(pages),
        )

        # Download all pages in parallel, limited by page_semaphore
        async def download_page(page_info):
            async with page_semaphore:
                dest_path = f"comics/{job_story_id}/{chapter_id}/page_{page_info.page_number:04d}.jpg"
                file_path = await scraper.download_image(page_info.source_url, dest_path)
                return page_info, file_path

        download_results = await asyncio.gather(
            *[download_page(p) for p in pages],
            return_exceptions=True,
        )

        # Check for download failures
        failed_pages = [r for r in download_results if isinstance(r, Exception)]
        if failed_pages:
            # If any page is a CookieExpiredError, propagate it
            for f in failed_pages:
                if isinstance(f, CookieExpiredError):
                    raise f
            # Otherwise log the first error but continue
            logger.warning(
                "comic_scrape_task %d/%d page downloads failed | chapter=%.1f",
                len(failed_pages), len(pages), chapter_number,
            )

        successful = [r for r in download_results if not isinstance(r, Exception)]

        # Write all pages to DB in one session
        async with AsyncSessionLocal() as db:
            with db.no_autoflush:
                for page_info, file_path in successful:
                    existing_page = await db.execute(
                        select(Page).where(
                            Page.chapter_id == chapter_id,
                            Page.page_number == page_info.page_number,
                        )
                    )
                    page = existing_page.scalar_one_or_none()
                    if not page:
                        db.add(Page(
                            chapter_id=chapter_id,
                            page_number=page_info.page_number,
                            file_path=file_path,
                            source_url=page_info.source_url,
                            width_px=page_info.width_px,
                            height_px=page_info.height_px,
                        ))
                    else:
                        page.file_path = file_path

            # Update chapter status
            ch_result = await db.execute(
                select(ComicChapter).where(ComicChapter.id == chapter_id)
            )
            ch = ch_result.scalar_one()
            ch.total_pages = len(pages)
            ch.scrape_status = ScrapeStatus.SCRAPED

            dur = int((time.perf_counter() - ch_start) * 1000)
            _add_log(db, job_uuid, "info", ch_label,
                     f"Scraped {len(pages)} pages ({len(successful)} ok, {len(failed_pages)} failed)",
                     duration_ms=dur, chapter_number=chapter_number)
            await db.commit()

        logger.info(
            "comic_scrape_task chapter ok | job_id=%s chapter=%.1f [%d/%d] pages=%d elapsed_ms=%d",
            job_uuid, chapter_number, ch_idx, total_chapters, len(pages),
            int((time.perf_counter() - ch_start) * 1000),
        )
        return (True, None, None)

    except CookieExpiredError:
        async with AsyncSessionLocal() as db:
            ch_result = await db.execute(
                select(ComicChapter).where(ComicChapter.id == chapter_id)
            )
            ch = ch_result.scalar_one()
            ch.scrape_status = ScrapeStatus.FAILED
            dur = int((time.perf_counter() - ch_start) * 1000)
            _add_log(db, job_uuid, "error", ch_label,
                     "Cookie expired — iOS browser refresh required",
                     error_type="CookieExpiredError", duration_ms=dur,
                     chapter_number=chapter_number)
            await db.commit()
        return (False, "Cookie expired — re-open the browser on iOS to refresh", "CookieExpiredError")

    except Exception as e:
        async with AsyncSessionLocal() as db:
            ch_result = await db.execute(
                select(ComicChapter).where(ComicChapter.id == chapter_id)
            )
            ch = ch_result.scalar_one()
            ch.scrape_status = ScrapeStatus.FAILED
            dur = int((time.perf_counter() - ch_start) * 1000)
            _add_log(db, job_uuid, "error", ch_label,
                     f"Chapter failed: {e}",
                     error_type=type(e).__name__, duration_ms=dur,
                     chapter_number=chapter_number)
            await db.commit()
        logger.error(
            "comic_scrape_task chapter failed | job_id=%s chapter=%.1f error=%s",
            job_uuid, chapter_number, e, exc_info=True,
        )
        return (False, str(e), type(e).__name__)


async def comic_scrape_task(ctx, job_id: str):
    """ARQ task: scrapes a comic with parallel chapter + page downloads."""
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
            return

        scraper = scraper_class()
        source_key = job.source_key
        source_url = job.source_url
        story_id = job.story_id

        try:
            # ── Metadata ────────────────────────────────────────────────────
            job.current_step = "metadata"
            await db.commit()

            step_start = time.perf_counter()
            try:
                metadata = await scraper.get_story_metadata(source_url)
                dur = int((time.perf_counter() - step_start) * 1000)
                logger.info(
                    "comic_scrape_task metadata ok | job_id=%s title=%r authors=%d tags=%d thumbnail=%s category=%s",
                    job_id, metadata.title, len(metadata.authors), len(metadata.tags),
                    metadata.thumbnail_url[:60] if metadata.thumbnail_url else "none",
                    metadata.category,
                )
                _add_log(db, job_uuid, "info", "metadata",
                         f"Fetched metadata: {metadata.title!r} — total_chapters={metadata.total_chapters} authors={len(metadata.authors)} tags={len(metadata.tags)}",
                         duration_ms=dur)
            except Exception as e:
                dur = int((time.perf_counter() - step_start) * 1000)
                _add_log(db, job_uuid, "error", "metadata",
                         f"Failed to fetch metadata: {e}",
                         error_type=type(e).__name__, duration_ms=dur)
                raise

            result = await db.execute(select(Comic).where(Comic.id == story_id))
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
                if metadata.category:
                    comic.category = metadata.category

                # ── Thumbnail ──────────────────────────────────────────
                if metadata.thumbnail_url and not comic.thumbnail_path:
                    try:
                        dest = f"comics/{story_id}/thumbnail.jpg"
                        comic.thumbnail_path = await scraper.download_image(metadata.thumbnail_url, dest)
                        logger.info("comic_scrape_task thumbnail saved | job_id=%s path=%s", job_id, comic.thumbnail_path)
                    except Exception as e:
                        logger.warning("comic_scrape_task thumbnail failed | job_id=%s error=%s", job_id, e)

                # ── Authors ────────────────────────────────────────────
                for author_name in metadata.authors:
                    author_result = await db.execute(select(Author).where(Author.name == author_name))
                    author = author_result.scalar_one_or_none()
                    if not author:
                        author = Author(name=author_name)
                        db.add(author)
                        await db.flush()
                    existing_ca = await db.execute(
                        select(ComicAuthor).where(
                            ComicAuthor.comic_id == comic.id,
                            ComicAuthor.author_id == author.id,
                            ComicAuthor.role == "artist",
                        )
                    )
                    if not existing_ca.scalar_one_or_none():
                        db.add(ComicAuthor(comic_id=comic.id, author_id=author.id, role="artist"))

                # ── Tags ───────────────────────────────────────────────
                for tag_dict in metadata.tags:
                    tag_name = tag_dict.get("name", "").strip()
                    tag_type = tag_dict.get("tag_type", "tag").strip()
                    if not tag_name:
                        continue
                    tag_result = await db.execute(
                        select(Tag).where(Tag.name == tag_name, Tag.tag_type == tag_type)
                    )
                    tag = tag_result.scalar_one_or_none()
                    if not tag:
                        tag = Tag(name=tag_name, tag_type=tag_type)
                        db.add(tag)
                        await db.flush()
                    existing_ct = await db.execute(
                        select(ComicTag).where(
                            ComicTag.comic_id == comic.id,
                            ComicTag.tag_id == tag.id,
                        )
                    )
                    if not existing_ct.scalar_one_or_none():
                        db.add(ComicTag(comic_id=comic.id, tag_id=tag.id))

            await db.commit()

            # ── Chapter list ────────────────────────────────────────────────
            job.current_step = "chapter_list"
            await db.commit()

            step_start = time.perf_counter()
            try:
                chapter_list = await scraper.get_chapter_list(source_url)
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
                        ComicChapter.comic_id == story_id,
                        ComicChapter.chapter_number == ch_info.chapter_number,
                        ComicChapter.deleted_at.is_(None),
                    )
                )
                if not existing.scalar_one_or_none():
                    db.add(ComicChapter(
                        comic_id=story_id,
                        chapter_number=ch_info.chapter_number,
                        title=ch_info.title,
                        source_url=ch_info.source_url,
                        scrape_status=ScrapeStatus.PENDING,
                    ))
            await db.commit()

            pending_result = await db.execute(
                select(ComicChapter).where(
                    ComicChapter.comic_id == story_id,
                    ComicChapter.scrape_status.in_([ScrapeStatus.PENDING, ScrapeStatus.FAILED]),
                    ComicChapter.deleted_at.is_(None),
                ).order_by(ComicChapter.chapter_number)
            )
            chapters_to_scrape = pending_result.scalars().all()
            total_chapters = len(chapters_to_scrape)
            logger.info(
                "comic_scrape_task chapters queued | job_id=%s count=%d concurrency=%d page_concurrency=%d",
                job_id, total_chapters,
                settings.scrape_chapter_concurrency, settings.scrape_page_concurrency,
            )

            job.current_step = "scraping_chapters"
            await db.commit()

        except CookieExpiredError:
            job.status = JobStatus.FAILED
            job.error_message = (
                f"Session expired for {source_key} — open the browser tab "
                "and navigate to any page to refresh cookies, then retry."
            )
            job.last_error_type = "CookieExpiredError"
            job.current_step = "failed"
            job.completed_at = datetime.now(timezone.utc)
            _add_log(db, job_uuid, "error", "failed",
                     job.error_message, error_type="CookieExpiredError")
            await db.commit()
            return

        except Exception as e:
            job.status = JobStatus.FAILED
            job.error_message = f"{type(e).__name__}: {e}" if str(e) else type(e).__name__
            job.last_error_type = type(e).__name__
            job.current_step = "failed"
            job.completed_at = datetime.now(timezone.utc)
            await db.commit()
            logger.error("comic_scrape_task fatal error | job_id=%s error=%s",
                         job_id, job.error_message, exc_info=True)
            return

        except BaseException as e:
            job.status = JobStatus.FAILED
            job.error_message = f"Job interrupted: {type(e).__name__}"
            job.last_error_type = type(e).__name__
            job.current_step = "failed"
            job.completed_at = datetime.now(timezone.utc)
            try:
                await asyncio.shield(db.commit())
            except Exception:
                pass
            raise

    # ── Parallel chapter scraping ──────────────────────────────────────────
    # Each chapter worker gets its own DB session. Concurrency controlled by semaphore.
    chapter_sem = asyncio.Semaphore(settings.scrape_chapter_concurrency)
    page_sem = asyncio.Semaphore(settings.scrape_page_concurrency)
    cookie_expired = False

    async def scrape_with_sem(ch_idx, chapter):
        nonlocal cookie_expired
        if cookie_expired:
            return (False, "Skipped — cookie expired", "CookieExpiredError")
        async with chapter_sem:
            if cookie_expired:
                return (False, "Skipped — cookie expired", "CookieExpiredError")
            result = await _scrape_chapter(
                scraper, chapter, story_id, job_uuid,
                ch_idx, total_chapters, page_sem,
            )
            if result[2] == "CookieExpiredError":
                cookie_expired = True
            return result

    results = await asyncio.gather(
        *[scrape_with_sem(i, ch) for i, ch in enumerate(chapters_to_scrape, start=1)],
    )

    # ── Finalize job status ────────────────────────────────────────────────
    chapters_scraped = sum(1 for ok, _, _ in results if ok)
    chapters_failed = sum(1 for ok, _, _ in results if not ok)

    async with AsyncSessionLocal() as db:
        result = await db.execute(select(ScrapeJob).where(ScrapeJob.id == job_uuid))
        job = result.scalar_one()
        job.chapters_scraped = chapters_scraped
        job.chapters_failed = chapters_failed

        if cookie_expired:
            job.status = JobStatus.FAILED
            job.error_message = "Cookie expired — re-open the browser on iOS to refresh"
            job.last_error_type = "CookieExpiredError"
        elif chapters_failed == 0:
            job.status = JobStatus.COMPLETE
        else:
            job.status = JobStatus.PARTIAL
            # Set error from last failed chapter
            for ok, msg, etype in results:
                if not ok and msg:
                    job.error_message = msg
                    job.last_error_type = etype

        job.current_step = "done"
        job.completed_at = datetime.now(timezone.utc)

        comic_result = await db.execute(select(Comic).where(Comic.id == story_id))
        comic = comic_result.scalar_one_or_none()
        if comic:
            if job.status == JobStatus.COMPLETE:
                comic.status = "complete"
            elif job.status == JobStatus.PARTIAL:
                comic.status = "partial"

        total_ms = int((time.perf_counter() - task_start) * 1000)
        _add_log(db, job_uuid, "info", "done",
                 f"Finished — status={job.status} scraped={chapters_scraped} failed={chapters_failed}",
                 duration_ms=total_ms)
        await db.commit()

        logger.info(
            "comic_scrape_task finished | job_id=%s status=%s scraped=%d failed=%d elapsed_ms=%d",
            job_id, job.status, chapters_scraped, chapters_failed, total_ms,
        )
