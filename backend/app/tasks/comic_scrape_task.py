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
                if metadata.category:
                    comic.category = metadata.category

                # ── Thumbnail ──────────────────────────────────────────
                if metadata.thumbnail_url and not comic.thumbnail_path:
                    try:
                        dest = f"comics/{job.story_id}/thumbnail.jpg"
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
            total_chapters = len(chapters_to_scrape)
            logger.info("comic_scrape_task chapters queued | job_id=%s count=%d", job_id, total_chapters)

            # ── Per-chapter scrape ──────────────────────────────────────────
            for ch_idx, chapter in enumerate(chapters_to_scrape, start=1):
                ch_label = f"chapter_{int(chapter.chapter_number)}"
                job.current_step = ch_label
                ch_start = time.perf_counter()
                logger.info(
                    "comic_scrape_task chapter start | job_id=%s chapter=%.1f [%d/%d] url=%s",
                    job_id, chapter.chapter_number, ch_idx, total_chapters, chapter.source_url,
                )

                try:
                    pages = await scraper.get_chapter_pages(chapter.source_url)
                    logger.info(
                        "comic_scrape_task pages found | job_id=%s chapter=%.1f [%d/%d] pages=%d",
                        job_id, chapter.chapter_number, ch_idx, total_chapters, len(pages),
                    )

                    with db.no_autoflush():
                        for pg_idx, page_info in enumerate(pages, start=1):
                            dest_path = f"comics/{job.story_id}/{chapter.id}/page_{page_info.page_number:04d}.jpg"
                            logger.debug(
                                "comic_scrape_task downloading | job_id=%s chapter=%.1f page=%d/%d url=%s",
                                job_id, chapter.chapter_number, pg_idx, len(pages), page_info.source_url,
                            )
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
                    logger.info(
                        "comic_scrape_task chapter ok | job_id=%s chapter=%.1f [%d/%d] pages=%d elapsed_ms=%d",
                        job_id, chapter.chapter_number, ch_idx, total_chapters, len(pages), dur,
                    )

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
                    logger.error(
                        "comic_scrape_task cookie expired | job_id=%s chapter=%.1f [%d/%d] — stopping",
                        job_id, chapter.chapter_number, ch_idx, total_chapters,
                    )
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
                    logger.error(
                        "comic_scrape_task chapter failed | job_id=%s chapter=%.1f [%d/%d] "
                        "error=%s elapsed_ms=%d",
                        job_id, chapter.chapter_number, ch_idx, total_chapters, e, dur,
                        exc_info=True,
                    )

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

        except BaseException as e:
            # CancelledError from ARQ timeout — BaseException is not caught by except Exception
            job.status = JobStatus.FAILED
            job.error_message = f"Job interrupted: {type(e).__name__}"
            job.last_error_type = type(e).__name__
            job.current_step = "failed"
            job.completed_at = datetime.now(timezone.utc)
            try:
                import asyncio
                await asyncio.shield(db.commit())
            except Exception:
                pass
            logger.error("comic_scrape_task cancelled/interrupted | job_id=%s type=%s",
                         job_id, type(e).__name__)
            raise

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
