import uuid
from typing import Optional
from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession
from app.dependencies import get_db
from app.schemas.scrape import ScrapeRequest, ScrapeJobResponse, ScrapeLogEntry
from app.schemas.shared import PaginatedResponse
from app.services import scrape_service

router = APIRouter(prefix="/scrape", tags=["scrape"])


@router.post("/comic", response_model=ScrapeJobResponse, status_code=202)
async def initiate_comic_scrape(body: ScrapeRequest, db: AsyncSession = Depends(get_db)):
    body_with_type = body.model_copy(update={"content_type": "comic"})
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
