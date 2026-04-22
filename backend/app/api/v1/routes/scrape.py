import uuid
from typing import Optional
from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession
from app.dependencies import get_db
from app.schemas.scrape import ScrapeRequest, ScrapeJobResponse, ScrapeLogEntry
from app.schemas.shared import PaginatedResponse
from app.services import scrape_service

router = APIRouter(prefix="/scrape", tags=["scrape"])


@router.post(
    "/comic",
    responses={
        202: {"description": "Scrape job created OR MangaDex match proposed (distinguished by response body shape)"},
        503: {"description": "MangaDex disabled (kill switch)"},
    },
)
async def initiate_comic_scrape(body: ScrapeRequest, db: AsyncSession = Depends(get_db)):
    from fastapi.responses import JSONResponse
    from app.core.config import settings
    from app.core.runtime_flags import flag_enabled
    from app.services.mangadex_matcher import find_mangadex_match

    body_with_type = body.model_copy(update={"content_type": "comic"})

    # Kill switch: hard-stop direct MangaDex scrapes. The Redis
    # override (managed via the monitor dashboard) wins over the
    # settings default — lets ops flip the switch without a restart.
    mangadex_disabled = await flag_enabled(
        "MANGADEX_DISABLED", default=settings.mangadex_disabled,
    )
    if body_with_type.source_key == "mangadex" and mangadex_disabled:
        return JSONResponse(
            status_code=503,
            content={"detail": "MangaDex temporarily disabled"},
        )

    # Matcher hook: only for eligible sources, only if user hasn't opted out, only if alive.
    if (
        body_with_type.source_key in ("toongod", "hentai20")
        and not body_with_type.skip_match
        and not mangadex_disabled
    ):
        # Prime the cookie cache BEFORE the matcher's source-meta fetch — without
        # this, the source scraper reads stale Redis cookies and gets 403'd by
        # Cloudflare. iOS just harvested fresh cookies in the request body.
        await scrape_service.store_cookies(
            body_with_type.source_key, body_with_type.cookies, body_with_type.user_agent,
        )
        match = await find_mangadex_match(
            source=body_with_type.source_key,
            source_url=body_with_type.url,
            source_title=body_with_type.page_title or body_with_type.url,
        )
        if match is not None:
            return JSONResponse(
                status_code=202,
                content={"match": match.to_dict()},
            )

    # Normal path: create job + enqueue.
    return await scrape_service.initiate_scrape(db, body_with_type)


@router.post("/fanfic", response_model=ScrapeJobResponse, status_code=202)
async def initiate_fanfic_scrape(body: ScrapeRequest, db: AsyncSession = Depends(get_db)):
    body_with_type = body.model_copy(update={"content_type": "fanfic"})
    return await scrape_service.initiate_scrape(db, body_with_type)


@router.get("", response_model=PaginatedResponse[ScrapeJobResponse])
async def list_scrape_jobs(
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
):
    return await scrape_service.list_jobs(db, page=page, page_size=page_size)


@router.get("/{job_id}", response_model=ScrapeJobResponse)
async def get_scrape_job(job_id: uuid.UUID, db: AsyncSession = Depends(get_db)):
    return await scrape_service.get_job(db, job_id)


@router.post("/{job_id}/retry", response_model=ScrapeJobResponse, status_code=202)
async def retry_scrape(job_id: uuid.UUID, db: AsyncSession = Depends(get_db)):
    return await scrape_service.retry_job(db, job_id)


@router.post("/{story_id}/update", response_model=ScrapeJobResponse, status_code=202)
async def delta_update(story_id: uuid.UUID, db: AsyncSession = Depends(get_db)):
    return await scrape_service.delta_update(db, story_id)


@router.get("/{job_id}/logs", response_model=list[ScrapeLogEntry])
async def get_scrape_logs(job_id: uuid.UUID, db: AsyncSession = Depends(get_db)):
    return await scrape_service.get_logs(db, job_id)
