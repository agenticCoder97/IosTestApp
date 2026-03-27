import uuid
from datetime import datetime
from typing import Optional
from sqlalchemy import String, Integer, Text, DateTime, func
from sqlalchemy.orm import Mapped, mapped_column
from app.db.database import Base


class ScrapeJob(Base):
    __tablename__ = "scrape_jobs"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    content_type: Mapped[str] = mapped_column(String(10), nullable=False)
    story_id: Mapped[uuid.UUID] = mapped_column(nullable=False)
    source_url: Mapped[str] = mapped_column(String(2000), nullable=False)
    source_key: Mapped[str] = mapped_column(String(50), nullable=False)
    job_type: Mapped[str] = mapped_column(String(20), nullable=False, default="initial")
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="queued")
    total_chapters: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    chapters_scraped: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    chapters_failed: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    error_message: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    started_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    completed_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, server_default=func.now())
    deleted_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
