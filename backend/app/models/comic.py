import uuid
from datetime import datetime
from typing import Optional
from sqlalchemy import String, Integer, Float, Text, DateTime, ForeignKey, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.db.database import Base


class Comic(Base):
    __tablename__ = "comics"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    title: Mapped[str] = mapped_column(String(1000), nullable=False)
    source_key: Mapped[str] = mapped_column(String(50), nullable=False)
    source_url: Mapped[str] = mapped_column(String(2000), nullable=False, unique=True)
    source_id: Mapped[Optional[str]] = mapped_column(String(200), nullable=True)
    thumbnail_path: Mapped[Optional[str]] = mapped_column(String(1000), nullable=True)
    description: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    total_chapters: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    total_pages: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    language: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    status: Mapped[str] = mapped_column(String(100), nullable=False, default="pending")
    category: Mapped[Optional[str]] = mapped_column(String(200), nullable=True)
    scrape_job_id: Mapped[Optional[uuid.UUID]] = mapped_column(ForeignKey("scrape_jobs.id"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now(), onupdate=func.now())
    deleted_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    archived_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    archive_status: Mapped[str] = mapped_column(String(20), nullable=False, default="none", server_default="none")

    chapters: Mapped[list["ComicChapter"]] = relationship("ComicChapter", back_populates="comic", lazy="select")
    comic_authors: Mapped[list["ComicAuthor"]] = relationship("ComicAuthor", back_populates="comic", lazy="select")
    comic_tags: Mapped[list["ComicTag"]] = relationship("ComicTag", back_populates="comic", lazy="select")


class ComicAuthor(Base):
    __tablename__ = "comic_authors"
    __table_args__ = (
        UniqueConstraint("comic_id", "author_id", "role", name="uq_comic_author_role"),
    )

    comic_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("comics.id"), primary_key=True)
    author_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("authors.id"), primary_key=True)
    role: Mapped[Optional[str]] = mapped_column(String(50), primary_key=True, nullable=True)

    comic: Mapped["Comic"] = relationship("Comic", back_populates="comic_authors")
    author: Mapped["Author"] = relationship("Author")


class Tag(Base):
    __tablename__ = "tags"
    __table_args__ = (
        UniqueConstraint("name", "tag_type", name="uq_tag_name_type"),
    )

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    tag_type: Mapped[str] = mapped_column(String(50), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())


class ComicTag(Base):
    __tablename__ = "comic_tags"

    comic_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("comics.id"), primary_key=True)
    tag_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("tags.id"), primary_key=True)

    comic: Mapped["Comic"] = relationship("Comic", back_populates="comic_tags")
    tag: Mapped["Tag"] = relationship("Tag")


class ComicChapter(Base):
    __tablename__ = "comic_chapters"
    __table_args__ = (
        UniqueConstraint("comic_id", "chapter_number", name="uq_comic_chapter_number"),
    )

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    comic_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("comics.id"), nullable=False)
    chapter_number: Mapped[float] = mapped_column(Float, nullable=False)
    title: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
    source_url: Mapped[Optional[str]] = mapped_column(String(2000), nullable=True)
    total_pages: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    scrape_status: Mapped[str] = mapped_column(String(20), nullable=False, default="pending")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
    deleted_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)

    comic: Mapped["Comic"] = relationship("Comic", back_populates="chapters")
    pages: Mapped[list["Page"]] = relationship("Page", back_populates="chapter", lazy="select")


class Page(Base):
    __tablename__ = "pages"
    __table_args__ = (
        UniqueConstraint("chapter_id", "page_number", name="uq_page_chapter_number"),
    )

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    chapter_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("comic_chapters.id"), nullable=False)
    page_number: Mapped[int] = mapped_column(Integer, nullable=False)
    file_path: Mapped[str] = mapped_column(String(1000), nullable=False)
    source_url: Mapped[Optional[str]] = mapped_column(String(2000), nullable=True)
    width_px: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    height_px: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)

    chapter: Mapped["ComicChapter"] = relationship("ComicChapter", back_populates="pages")
