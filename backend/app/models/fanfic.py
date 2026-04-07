import uuid
from datetime import datetime
from typing import Optional
from sqlalchemy import String, Integer, Float, Text, DateTime, ForeignKey, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.db.database import Base


class Fanfic(Base):
    __tablename__ = "fanfics"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    title: Mapped[str] = mapped_column(String(1000), nullable=False)
    source_key: Mapped[str] = mapped_column(String(50), nullable=False)
    source_url: Mapped[str] = mapped_column(String(2000), nullable=False, unique=True)
    source_id: Mapped[Optional[str]] = mapped_column(String(200), nullable=True)
    summary: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    fandom: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
    pairing: Mapped[Optional[str]] = mapped_column("relationship", String(500), nullable=True)
    characters: Mapped[Optional[str]] = mapped_column(String(1000), nullable=True)
    rating: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    warnings: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
    completion_status: Mapped[str] = mapped_column(String(100), nullable=False, default="ongoing")
    word_count: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    total_chapters: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    published_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    updated_at_source: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    language: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    freeform_tags: Mapped[Optional[str]] = mapped_column(String(4000), nullable=True)
    hits: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    kudos: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    comments_count: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    bookmarks_count: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    thumbnail_path: Mapped[Optional[str]] = mapped_column(String(1000), nullable=True)
    scrape_job_id: Mapped[Optional[uuid.UUID]] = mapped_column(ForeignKey("scrape_jobs.id"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now(), onupdate=func.now())
    deleted_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)

    chapters: Mapped[list["FanficChapter"]] = relationship("FanficChapter", back_populates="fanfic", lazy="select")
    fanfic_authors: Mapped[list["FanficAuthor"]] = relationship("FanficAuthor", back_populates="fanfic", lazy="select")


class FanficAuthor(Base):
    __tablename__ = "fanfic_authors"
    __table_args__ = (
        UniqueConstraint("fanfic_id", "author_id", name="uq_fanfic_author"),
    )

    fanfic_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("fanfics.id"), primary_key=True)
    author_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("authors.id"), primary_key=True)

    fanfic: Mapped["Fanfic"] = relationship("Fanfic", back_populates="fanfic_authors")
    author: Mapped["Author"] = relationship("Author")


class FanficChapter(Base):
    __tablename__ = "fanfic_chapters"
    __table_args__ = (
        UniqueConstraint("fanfic_id", "chapter_number", name="uq_fanfic_chapter_number"),
    )

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    fanfic_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("fanfics.id"), nullable=False)
    chapter_number: Mapped[float] = mapped_column(Float, nullable=False)
    title: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
    content: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    word_count: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    source_url: Mapped[Optional[str]] = mapped_column(String(2000), nullable=True)
    scrape_status: Mapped[str] = mapped_column(String(20), nullable=False, default="pending")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
    deleted_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)

    fanfic: Mapped["Fanfic"] = relationship("Fanfic", back_populates="chapters")
