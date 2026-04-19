"""
MangaDex comic source adapter (AST-30).

# MangaDex API ToS (https://api.mangadex.org/docs/):
# - Honor takedown requests (kill-switch via MANGADEX_DISABLED env)
# - Real User-Agent required; no Via header; TLS 1.2+
# - POST success/failure to api.mangadex.network/report on every page fetch
# - Astral is a private single-user app on a local device — public attribution
#   clause does not apply, but report POSTs are still mandatory.
"""
import logging
import re
from typing import Optional
from urllib.parse import urlparse

from app.core.constants import SourceKey
from app.scrapers.base import (
    BaseScraper,
    ChapterInfo,
    PageInfo,
    StoryMetadata,
)
from app.scrapers.comic._mangadex_http import MangadexHTTPClient

logger = logging.getLogger(__name__)

_TITLE_URL_RE = re.compile(r"/title/([0-9a-f-]+)", re.I)
_API = "https://api.mangadex.org"


def _extract_manga_id(url: str) -> str:
    m = _TITLE_URL_RE.search(urlparse(url).path)
    if not m:
        raise ValueError(f"Cannot extract MangaDex manga id from URL: {url}")
    return m.group(1)


def _english_title(title_obj: dict) -> str:
    return (
        title_obj.get("en")
        or next(iter(title_obj.values()), "Unknown Title")
    )


class MangadexScraper(BaseScraper):
    source_key = SourceKey.MANGADEX
    content_type = "comic"
    requires_browser = False
    request_delay_seconds = 0.0  # rate limiter handles pacing
    max_retries = 3

    def __init__(self):
        super().__init__()
        self._http = MangadexHTTPClient()

    async def get_story_metadata(self, url: str) -> StoryMetadata:
        manga_id = _extract_manga_id(url)
        body = await self._http.get_json(
            f"{_API}/manga/{manga_id}",
            params={"includes[]": ["cover_art", "author"]},
        )
        data = body["data"]
        attrs = data["attributes"]
        title = _english_title(attrs.get("title", {}))
        authors: list[str] = []
        cover_filename: Optional[str] = None
        for rel in data.get("relationships", []):
            rtype = rel.get("type")
            rattrs = rel.get("attributes") or {}
            if rtype == "author":
                name = rattrs.get("name")
                if name:
                    authors.append(name)
            elif rtype == "cover_art":
                fn = rattrs.get("fileName")
                if fn:
                    cover_filename = fn
        thumbnail_url: Optional[str] = None
        if cover_filename:
            thumbnail_url = (
                f"https://uploads.mangadex.org/covers/{manga_id}/{cover_filename}.512.jpg"
            )
        tags = [
            {
                "name": _english_title(t["attributes"].get("name", {})),
                "tag_type": t["attributes"].get("group", "tag"),
            }
            for t in attrs.get("tags", [])
        ]
        last_chapter = attrs.get("lastChapter")
        try:
            total_chapters = int(float(last_chapter)) if last_chapter else None
        except (TypeError, ValueError):
            total_chapters = None
        return StoryMetadata(
            title=title,
            source_url=f"https://mangadex.org/title/{manga_id}",
            source_key=self.source_key,
            source_id=manga_id,
            description=_english_title(attrs.get("description", {})) or None,
            language=attrs.get("originalLanguage"),
            authors=authors,
            tags=tags,
            thumbnail_url=thumbnail_url,
            total_chapters=total_chapters,
            category=attrs.get("contentRating"),
        )

    async def get_chapter_list(self, story_url: str) -> list[ChapterInfo]:
        manga_id = _extract_manga_id(story_url)
        chapters: list[ChapterInfo] = []
        offset = 0
        limit = 500
        while True:
            body = await self._http.get_json(
                f"{_API}/manga/{manga_id}/feed",
                params={
                    "translatedLanguage[]": ["en"],
                    "order[chapter]": "asc",
                    "limit": limit,
                    "offset": offset,
                },
            )
            page = body.get("data", [])
            for ch in page:
                attrs = ch.get("attributes", {})
                # Skip chapters hosted on external readers (MangaPlus etc.).
                if attrs.get("externalUrl"):
                    continue
                num_str = attrs.get("chapter")
                try:
                    chapter_number = float(num_str) if num_str is not None else None
                except (TypeError, ValueError):
                    chapter_number = None
                if chapter_number is None:
                    continue
                chapters.append(ChapterInfo(
                    chapter_number=chapter_number,
                    title=attrs.get("title") or None,
                    source_url=f"https://mangadex.org/chapter/{ch['id']}",
                ))
            total = body.get("total", 0)
            offset += body.get("limit", limit)
            if offset >= total:
                break
        return chapters

    async def get_chapter_pages(self, chapter_url: str) -> list[PageInfo]:
        raise NotImplementedError("filled in Task 6")

    async def get_chapter_text(self, chapter_url: str) -> str:
        raise NotImplementedError("MangaDex is a comic source — no text content")

    async def search(
        self, *, title: str, content_ratings: list[str], limit: int = 10,
    ) -> list[dict]:
        raise NotImplementedError("filled in Task 9")
