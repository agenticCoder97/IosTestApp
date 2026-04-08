import uuid
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from app.dependencies import get_db
from app.schemas.comic import ComicResponse, ComicChapterResponse, PageResponse, ComicUpdateRequest
from app.schemas.shared import PaginatedResponse
from app.services import comic_service

router = APIRouter(prefix="/comics", tags=["comics"])


@router.get("", response_model=PaginatedResponse[ComicResponse])
async def list_comics(
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=200),
    sort: Optional[str] = Query(None),
    db: AsyncSession = Depends(get_db),
):
    return await comic_service.list_comics(db, page=page, page_size=page_size, sort=sort)


@router.get("/{comic_id}", response_model=ComicResponse)
async def get_comic(comic_id: uuid.UUID, db: AsyncSession = Depends(get_db)):
    comic = await comic_service.get_comic(db, comic_id)
    if not comic:
        raise HTTPException(status_code=404, detail="Comic not found")
    return comic


@router.get("/{comic_id}/chapters/{chapter_id}/pages", response_model=list[PageResponse])
async def get_chapter_pages(
    comic_id: uuid.UUID,
    chapter_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
):
    return await comic_service.get_chapter_pages(db, comic_id, chapter_id)


@router.patch("/{comic_id}", response_model=ComicResponse)
async def update_comic(
    comic_id: uuid.UUID,
    body: ComicUpdateRequest,
    db: AsyncSession = Depends(get_db),
):
    comic = await comic_service.update_comic(db, comic_id, body)
    if not comic:
        raise HTTPException(status_code=404, detail="Comic not found")
    return comic


@router.post("/{comic_id}/archive", response_model=ComicResponse, status_code=202)
async def archive_comic(comic_id: uuid.UUID, db: AsyncSession = Depends(get_db)):
    result = await comic_service.archive_comic(db, comic_id)
    if not result:
        raise HTTPException(status_code=404, detail="Comic not found")
    return result


@router.post("/{comic_id}/unarchive", response_model=ComicResponse, status_code=202)
async def unarchive_comic(comic_id: uuid.UUID, db: AsyncSession = Depends(get_db)):
    result = await comic_service.unarchive_comic(db, comic_id)
    if not result:
        raise HTTPException(status_code=404, detail="Comic not found")
    return result


@router.delete("/{comic_id}", status_code=204)
async def delete_comic(comic_id: uuid.UUID, db: AsyncSession = Depends(get_db)):
    deleted = await comic_service.soft_delete_comic(db, comic_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Comic not found")
