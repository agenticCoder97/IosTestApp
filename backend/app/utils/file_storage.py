from pathlib import Path
from app.core.config import settings


def comic_page_path(comic_id: str, chapter_id: str, page_number: int, ext: str = "jpg") -> str:
    """Returns relative path (from block volume root) for a comic page image."""
    return f"comics/{comic_id}/{chapter_id}/page_{page_number:04d}.{ext}"


def thumbnail_path(content_type: str, story_id: str, ext: str = "jpg") -> str:
    return f"thumbnails/{content_type}/{story_id}.{ext}"


def full_path(relative: str) -> Path:
    return Path(settings.block_volume_path) / relative


def archive_page_path(comic_id: str, chapter_id: str, page_number: int) -> str:
    """Returns relative path for an archived WebP page."""
    return f"archive/comics/{comic_id}/{chapter_id}/page_{page_number:04d}.webp"


def static_url(relative: str) -> str:
    return f"{settings.static_base_url}/{relative}"
