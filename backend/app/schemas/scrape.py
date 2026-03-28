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
    content_type: str


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
