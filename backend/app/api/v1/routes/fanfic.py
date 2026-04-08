import uuid
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from app.dependencies import get_db
from app.schemas.fanfic import FanficResponse, FanficChapterResponse
from app.schemas.shared import PaginatedResponse
from app.services import fanfic_service

router = APIRouter(prefix="/fanfic", tags=["fanfic"])


@router.get("", response_model=PaginatedResponse[FanficResponse])
async def list_fanfics(
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=200),
    fandom: Optional[str] = Query(None),
    rating: Optional[str] = Query(None),
    completion_status: Optional[str] = Query(None),
    sort: Optional[str] = Query(None),
    db: AsyncSession = Depends(get_db),
):
    return await fanfic_service.list_fanfics(
        db, page=page, page_size=page_size,
        fandom=fandom, rating=rating, completion_status=completion_status, sort=sort,
    )


@router.get("/{fanfic_id}", response_model=FanficResponse)
async def get_fanfic(fanfic_id: uuid.UUID, db: AsyncSession = Depends(get_db)):
    fanfic = await fanfic_service.get_fanfic(db, fanfic_id)
    if not fanfic:
        raise HTTPException(status_code=404, detail="Fanfic not found")
    return fanfic


@router.get("/{fanfic_id}/chapters/{chapter_id}", response_model=FanficChapterResponse)
async def get_fanfic_chapter(
    fanfic_id: uuid.UUID,
    chapter_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
):
    chapter = await fanfic_service.get_chapter(db, fanfic_id, chapter_id)
    if not chapter:
        raise HTTPException(status_code=404, detail="Chapter not found")
    return chapter


@router.delete("/{fanfic_id}", status_code=204)
async def delete_fanfic(fanfic_id: uuid.UUID, db: AsyncSession = Depends(get_db)):
    deleted = await fanfic_service.soft_delete_fanfic(db, fanfic_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Fanfic not found")
