import uuid
from datetime import datetime
from typing import Optional
from pydantic import BaseModel, ConfigDict
from app.schemas.shared import CookieDTO


class ScrapeRequest(BaseModel):
    url: str
    source_key: str
    cookies: list[CookieDTO]
    user_agent: str
    content_type: str = "comic"
    # AST-30 — MangaDex matcher fields. All optional, ignored for ineligible sources.
    page_title: Optional[str] = None
    skip_match: bool = False
    previous_source: Optional[str] = None
    previous_source_url: Optional[str] = None
    match_confidence: Optional[float] = None


class MangaDexMatchPayload(BaseModel):
    manga_id: str
    mangadex_url: str
    title: str
    confidence: float
    thumbnail_url: Optional[str] = None
    chapter_count: int
    source_chapter_count: int


class ScrapeMatchResponse(BaseModel):
    match: MangaDexMatchPayload


class ScrapeJobResponse(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    id: uuid.UUID
    content_type: str
    story_id: uuid.UUID
    source_url: str
    source_key: str
    job_type: str
    status: str
    total_chapters: Optional[int] = None
    chapters_scraped: int
    chapters_failed: int
    error_message: Optional[str] = None
    current_step: Optional[str] = None
    last_error_type: Optional[str] = None
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    created_at: datetime


class ScrapeLogEntry(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    id: uuid.UUID
    job_id: uuid.UUID
    timestamp: datetime
    level: str
    step: str
    message: str
    error_type: Optional[str] = None
    http_status: Optional[int] = None
    duration_ms: Optional[int] = None
    chapter_number: Optional[float] = None
