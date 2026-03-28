import uuid
from datetime import datetime
from typing import Optional
from pydantic import BaseModel, ConfigDict
from app.schemas.shared import AuthorResponse, TagResponse


class PageResponse(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    id: uuid.UUID
    page_number: int
    file_path: str
    source_url: Optional[str] = None
    width_px: Optional[int] = None
    height_px: Optional[int] = None


class ComicChapterResponse(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    id: uuid.UUID
    chapter_number: float
    title: Optional[str] = None
    source_url: Optional[str] = None
    total_pages: int
    scrape_status: str
    created_at: datetime


class ComicResponse(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    id: uuid.UUID
    title: str
    source_key: str
    source_url: str
    source_id: Optional[str] = None
    thumbnail_path: Optional[str] = None
    description: Optional[str] = None
    total_chapters: int
    total_pages: int
    language: Optional[str] = None
    status: str
    category: Optional[str] = None
    authors: Optional[list[AuthorResponse]] = None
    tags: Optional[list[TagResponse]] = None
    chapters: Optional[list[ComicChapterResponse]] = None
    created_at: datetime
    updated_at: datetime


class ComicUpdateRequest(BaseModel):
    title: Optional[str] = None
    thumbnail_path: Optional[str] = None
