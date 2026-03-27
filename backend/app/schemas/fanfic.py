import uuid
from datetime import datetime
from typing import Optional
from pydantic import BaseModel, ConfigDict
from app.schemas.shared import AuthorResponse


class FanficChapterResponse(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    id: uuid.UUID
    chapter_number: float
    title: Optional[str] = None
    content: Optional[str] = None
    word_count: Optional[int] = None
    source_url: Optional[str] = None
    scrape_status: str
    created_at: datetime


class FanficResponse(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    id: uuid.UUID
    title: str
    source_key: str
    source_url: str
    source_id: Optional[str] = None
    summary: Optional[str] = None
    fandom: Optional[str] = None
    relationship: Optional[str] = None
    characters: Optional[str] = None
    rating: Optional[str] = None
    warnings: Optional[str] = None
    completion_status: str
    word_count: Optional[int] = None
    total_chapters: int
    published_at: Optional[datetime] = None
    updated_at_source: Optional[datetime] = None
    language: Optional[str] = None
    thumbnail_path: Optional[str] = None
    authors: Optional[list[AuthorResponse]] = None
    chapters: Optional[list[FanficChapterResponse]] = None
    created_at: datetime
    updated_at: datetime
