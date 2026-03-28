import uuid
from datetime import datetime
from typing import Optional
from sqlalchemy import String, Integer, Float, DateTime, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column
from app.db.database import Base


class ReadingProgress(Base):
    __tablename__ = "reading_progress"
    __table_args__ = (
        UniqueConstraint("content_type", "story_id", name="uq_progress_content_story"),
    )

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    content_type: Mapped[str] = mapped_column(String(10), nullable=False)
    story_id: Mapped[uuid.UUID] = mapped_column(nullable=False)
    last_chapter_id: Mapped[Optional[uuid.UUID]] = mapped_column(nullable=True)
    last_chapter_number: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    last_page_number: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    scroll_offset_percent: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now(), onupdate=func.now())
