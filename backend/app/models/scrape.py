import uuid
from datetime import datetime
from typing import Optional
from sqlalchemy import String, Integer, Float, Text, DateTime, Index, func
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
    # Granular failure info — surfaced directly to iOS
    current_step: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    last_error_type: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    started_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    completed_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
    deleted_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)


class ScrapeLog(Base):
    """Per-step structured event log for a ScrapeJob. One row per scrape event."""
    __tablename__ = "scrape_logs"
    __table_args__ = (
        Index("ix_scrape_logs_job_id", "job_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    job_id: Mapped[uuid.UUID] = mapped_column(nullable=False)
    timestamp: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    level: Mapped[str] = mapped_column(String(10), nullable=False)   # info | warning | error
    step: Mapped[str] = mapped_column(String(100), nullable=False)   # metadata | chapter_list | chapter_N | done | start
    message: Mapped[str] = mapped_column(Text, nullable=False)
    error_type: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    http_status: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    duration_ms: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    chapter_number: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
