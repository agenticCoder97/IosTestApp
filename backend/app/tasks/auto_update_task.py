import logging
import uuid
from arq.connections import ArqRedis
from sqlalchemy import select, and_
from sqlalchemy.orm import selectinload
from app.db.database import AsyncSessionLocal
from app.models.comic import Comic
from app.models.fanfic import Fanfic
from app.models.scrape import ScrapeJob
from app.core.constants import JobStatus, JobType, SourceKey
import redis.asyncio as aioredis
from app.core.config import settings

logger = logging.getLogger(__name__)

# Sources that have ongoing series with new chapters (nhentai is single galleries — skip it)
SERIES_SOURCES = {SourceKey.TOONGOD, SourceKey.HENTAI20}


async def auto_update_task(ctx):
    """
    ARQ cron: every 6 hours, queue delta jobs for all ongoing content
    that has no active (queued/running) job.
    - Fanfics: all with completion_status != 'complete'
    - Comics: all from series sources (toongod, hentai20)
    """
    logger.info("auto_update_task started")
    queued = 0
    skipped_active = 0

    async with AsyncSessionLocal() as db:
        # Fetch all story IDs with an active job to avoid double-queueing
        active_result = await db.execute(
            select(ScrapeJob.story_id).where(
                ScrapeJob.status.in_([JobStatus.QUEUED, JobStatus.RUNNING]),
                ScrapeJob.deleted_at.is_(None),
            )
        )
        active_story_ids: set[uuid.UUID] = {row[0] for row in active_result.all()}
        logger.info("auto_update_task active jobs for story_ids=%d", len(active_story_ids))

        # --- Ongoing fanfics ---
        fanfic_result = await db.execute(
            select(Fanfic).where(
                Fanfic.completion_status != "complete",
                Fanfic.deleted_at.is_(None),
                Fanfic.title != "Pending scrape...",  # skip stubs
            )
        )
        ongoing_fanfics = fanfic_result.scalars().all()
        logger.info("auto_update_task ongoing fanfics found=%d", len(ongoing_fanfics))

        # --- Series comics (toongod + hentai20) ---
        comic_result = await db.execute(
            select(Comic).where(
                Comic.source_key.in_([SourceKey.TOONGOD, SourceKey.HENTAI20]),
                Comic.deleted_at.is_(None),
                Comic.title != "Pending scrape...",  # skip stubs
            )
        )
        series_comics = comic_result.scalars().all()
        logger.info("auto_update_task series comics found=%d", len(series_comics))

        jobs_to_add = []

        for fanfic in ongoing_fanfics:
            if fanfic.id in active_story_ids:
                skipped_active += 1
                continue
            job = ScrapeJob(
                content_type="fanfic",
                story_id=fanfic.id,
                source_url=fanfic.source_url,
                source_key=fanfic.source_key,
                job_type=JobType.DELTA,
                status=JobStatus.QUEUED,
            )
            jobs_to_add.append(job)

        for comic in series_comics:
            if comic.id in active_story_ids:
                skipped_active += 1
                continue
            job = ScrapeJob(
                content_type="comic",
                story_id=comic.id,
                source_url=comic.source_url,
                source_key=comic.source_key,
                job_type=JobType.DELTA,
                status=JobStatus.QUEUED,
            )
            jobs_to_add.append(job)

        if jobs_to_add:
            db.add_all(jobs_to_add)
            await db.commit()
            for job in jobs_to_add:
                await db.refresh(job)

        logger.info(
            "auto_update_task jobs_created=%d skipped_active=%d",
            len(jobs_to_add),
            skipped_active,
        )

    # Enqueue all created jobs into ARQ outside the DB session
    if jobs_to_add:
        try:
            r = await aioredis.from_url(settings.redis_url)
            arq_redis = ArqRedis(r.connection_pool)
            for job in jobs_to_add:
                task_name = "comic_scrape_task" if job.content_type == "comic" else "fanfic_scrape_task"
                await arq_redis.enqueue_job(task_name, str(job.id))
                queued += 1
            await arq_redis.aclose()
            logger.info("auto_update_task enqueued=%d", queued)
        except Exception as e:
            logger.error("auto_update_task ARQ enqueue failed | error=%s", e)

    logger.info("auto_update_task complete | queued=%d skipped_active=%d", queued, skipped_active)
