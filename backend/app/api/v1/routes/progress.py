import uuid
from fastapi import APIRouter, Depends, HTTPException, Path, Query
from sqlalchemy.ext.asyncio import AsyncSession
from app.dependencies import get_db
from app.schemas.progress import ComicProgressRequest, FanficProgressRequest, ProgressResponse
from app.services import progress_service

router = APIRouter(prefix="/progress", tags=["progress"])


@router.get("", response_model=list[ProgressResponse])
async def get_all_progress(
    content_type: str = Query(..., pattern="^(comic|fanfic)$"),
    db: AsyncSession = Depends(get_db),
):
    """Return all progress records for a content type. iOS calls this once on launch."""
    return await progress_service.get_all_progress(db, content_type)


@router.put("/comic/{story_id}", response_model=ProgressResponse)
async def update_comic_progress(
    story_id: uuid.UUID,
    body: ComicProgressRequest,
    db: AsyncSession = Depends(get_db),
):
    return await progress_service.upsert_comic_progress(db, story_id, body)


@router.put("/fanfic/{story_id}", response_model=ProgressResponse)
async def update_fanfic_progress(
    story_id: uuid.UUID,
    body: FanficProgressRequest,
    db: AsyncSession = Depends(get_db),
):
    return await progress_service.upsert_fanfic_progress(db, story_id, body)


@router.get("/{content_type}/{story_id}", response_model=ProgressResponse)
async def get_progress(
    content_type: str = Path(..., pattern="^(comic|fanfic)$"),
    story_id: uuid.UUID = Path(...),
    db: AsyncSession = Depends(get_db),
):
    progress = await progress_service.get_progress(db, content_type, story_id)
    if not progress:
        raise HTTPException(status_code=404, detail="Progress not found")
    return progress
