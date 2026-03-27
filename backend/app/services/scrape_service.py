import uuid
import json
from datetime import datetime, timezone
from math import ceil
from typing import Optional
from fastapi import HTTPException
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession
from app.models.scrape import ScrapeJob
from app.models.comic import Comic
from app.models.fanfic import Fanfic
from app.schemas.scrape import ScrapeRequest, ScrapeJobResponse
from app.schemas.shared import PaginatedResponse
from app.core.config import settings
from app.core.constants import JobStatus, JobType
import redis.asyncio as aioredis


def _job_to_schema(job: ScrapeJob) -> ScrapeJobResponse:
    return ScrapeJobResponse(
        id=job.id,
        content_type=job.content_type,
        story_id=job.story_id,
        source_url=job.source_url,
        source_key=job.source_key,
        job_type=job.job_type,
        status=job.status,
        total_chapters=job.total_chapters,
        chapters_scraped=job.chapters_scraped,
        chapters_failed=job.chapters_failed,
        error_message=job.error_message,
        started_at=job.started_at,
        completed_at=job.completed_at,
        created_at=job.created_at,
    )


async def _store_cookies(source_key: str, cookies: list, user_agent: str) -> None:
    r = await aioredis.from_url(settings.redis_url)
    try:
        cache_data = {
            "cookies": [c.model_dump() for c in cookies],
            "user_agent": user_agent,
        }
        await r.set(
            f"cookies:{source_key}",
            json.dumps(cache_data),
            ex=settings.cookie_cache_ttl_secs,
        )
    finally:
        await r.aclose()


async def initiate_scrape(db: AsyncSession, body: ScrapeRequest) -> ScrapeJobResponse:
    await _store_cookies(body.source_key, body.cookies, body.user_agent)

    # Create a placeholder story record if it doesn't exist
    story_id = uuid.uuid4()
    if body.content_type == "comic":
        result = await db.execute(
            select(Comic).where(Comic.source_url == body.url, Comic.deleted_at.is_(None))
        )
        existing = result.scalar_one_or_none()
        if existing:
            story_id = existing.id
        else:
            comic = Comic(
                id=story_id,
                title="Pending scrape...",
                source_key=body.source_key,
                source_url=body.url,
            )
            db.add(comic)
    else:
        result = await db.execute(
            select(Fanfic).where(Fanfic.source_url == body.url, Fanfic.deleted_at.is_(None))
        )
        existing = result.scalar_one_or_none()
        if existing:
            story_id = existing.id
        else:
            fanfic = Fanfic(
                id=story_id,
                title="Pending scrape...",
                source_key=body.source_key,
                source_url=body.url,
            )
            db.add(fanfic)

    job = ScrapeJob(
        content_type=body.content_type,
        story_id=story_id,
        source_url=body.url,
        source_key=body.source_key,
        job_type=JobType.INITIAL,
        status=JobStatus.QUEUED,
    )
    db.add(job)
    await db.commit()
    await db.refresh(job)

    # Enqueue ARQ task
    try:
        r = await aioredis.from_url(settings.redis_url)
        from arq.connections import ArqRedis
        arq_redis = ArqRedis(r.connection_pool)
        task_name = "comic_scrape_task" if body.content_type == "comic" else "fanfic_scrape_task"
        await arq_redis.enqueue_job(task_name, str(job.id))
        await arq_redis.aclose()
    except Exception:
        pass  # Worker may not be running in local dev without worker stack

    return _job_to_schema(job)


async def get_job(db: AsyncSession, job_id: uuid.UUID) -> ScrapeJobResponse:
    result = await db.execute(
        select(ScrapeJob).where(ScrapeJob.id == job_id, ScrapeJob.deleted_at.is_(None))
    )
    job = result.scalar_one_or_none()
    if not job:
        raise HTTPException(status_code=404, detail="Scrape job not found")
    return _job_to_schema(job)


async def list_jobs(
    db: AsyncSession,
    page: int,
    page_size: int,
) -> PaginatedResponse[ScrapeJobResponse]:
    count_result = await db.execute(
        select(func.count()).select_from(ScrapeJob).where(ScrapeJob.deleted_at.is_(None))
    )
    total = count_result.scalar_one()

    result = await db.execute(
        select(ScrapeJob)
        .where(ScrapeJob.deleted_at.is_(None))
        .order_by(ScrapeJob.created_at.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
    )
    jobs = result.scalars().all()

    total_pages = ceil(total / page_size) if total > 0 else 1
    return PaginatedResponse(
        items=[_job_to_schema(j) for j in jobs],
        total=total,
        page=page,
        page_size=page_size,
        total_pages=total_pages,
        has_next=page < total_pages,
    )


async def retry_job(db: AsyncSession, job_id: uuid.UUID) -> ScrapeJobResponse:
    result = await db.execute(
        select(ScrapeJob).where(ScrapeJob.id == job_id, ScrapeJob.deleted_at.is_(None))
    )
    job = result.scalar_one_or_none()
    if not job:
        raise HTTPException(status_code=404, detail="Scrape job not found")

    retry_job = ScrapeJob(
        content_type=job.content_type,
        story_id=job.story_id,
        source_url=job.source_url,
        source_key=job.source_key,
        job_type=JobType.RETRY,
        status=JobStatus.QUEUED,
    )
    db.add(retry_job)
    await db.commit()
    await db.refresh(retry_job)

    try:
        import redis.asyncio as aioredis
        from arq.connections import ArqRedis
        r = await aioredis.from_url(settings.redis_url)
        arq_redis = ArqRedis(r.connection_pool)
        task_name = "comic_scrape_task" if job.content_type == "comic" else "fanfic_scrape_task"
        await arq_redis.enqueue_job(task_name, str(retry_job.id))
        await arq_redis.aclose()
    except Exception:
        pass

    return _job_to_schema(retry_job)


async def delta_update(db: AsyncSession, story_id: uuid.UUID) -> ScrapeJobResponse:
    # Try comic first, then fanfic
    result = await db.execute(
        select(Comic).where(Comic.id == story_id, Comic.deleted_at.is_(None))
    )
    comic = result.scalar_one_or_none()

    if comic:
        content_type = "comic"
        source_url = comic.source_url
        source_key = comic.source_key
    else:
        result = await db.execute(
            select(Fanfic).where(Fanfic.id == story_id, Fanfic.deleted_at.is_(None))
        )
        fanfic = result.scalar_one_or_none()
        if not fanfic:
            raise HTTPException(status_code=404, detail="Story not found")
        content_type = "fanfic"
        source_url = fanfic.source_url
        source_key = fanfic.source_key

    job = ScrapeJob(
        content_type=content_type,
        story_id=story_id,
        source_url=source_url,
        source_key=source_key,
        job_type=JobType.DELTA,
        status=JobStatus.QUEUED,
    )
    db.add(job)
    await db.commit()
    await db.refresh(job)

    try:
        import redis.asyncio as aioredis
        from arq.connections import ArqRedis
        r = await aioredis.from_url(settings.redis_url)
        arq_redis = ArqRedis(r.connection_pool)
        task_name = "comic_scrape_task" if content_type == "comic" else "fanfic_scrape_task"
        await arq_redis.enqueue_job(task_name, str(job.id))
        await arq_redis.aclose()
    except Exception:
        pass

    return _job_to_schema(job)
