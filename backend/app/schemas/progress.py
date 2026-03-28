import uuid
from datetime import datetime
from typing import Optional
from pydantic import BaseModel, ConfigDict


class ComicProgressRequest(BaseModel):
    last_chapter_number: int
    last_page_number: Optional[int] = None


class FanficProgressRequest(BaseModel):
    last_chapter_number: int
    scroll_offset_percent: Optional[float] = None


class ProgressResponse(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    id: uuid.UUID
    content_type: str
    story_id: uuid.UUID
    last_chapter_id: Optional[uuid.UUID] = None
    last_chapter_number: int
    last_page_number: Optional[int] = None
    scroll_offset_percent: Optional[float] = None
    updated_at: datetime
