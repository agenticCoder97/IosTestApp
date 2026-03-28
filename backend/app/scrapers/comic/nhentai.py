import json
import re
from bs4 import BeautifulSoup
from app.scrapers.base import BaseScraper, StoryMetadata, ChapterInfo, PageInfo, ScraperError
from app.core.constants import SourceKey

_EXT_MAP = {"j": "jpg", "p": "png", "g": "gif", "w": "webp"}


def _gallery_id(url: str) -> str:
    m = re.search(r"/g/(\d+)", url)
    if not m:
        raise ValueError(f"Cannot extract nhentai gallery ID from URL: {url}")
    return m.group(1)


def _parse_gallery(html: str) -> dict:
    """Extract and decode the window._gallery JSON embedded in the page."""
    soup = BeautifulSoup(html, "lxml")
    for script in soup.find_all("script"):
        text = script.string or ""
        if "window._gallery" not in text:
            continue
        # Capture the full JSON string literal passed to JSON.parse("...")
        m = re.search(r'window\._gallery\s*=\s*JSON\.parse\(("(?:[^"\\]|\\.)*")\)', text)
        if not m:
            continue
        # json.loads decodes the JS string literal (handles \" and \uXXXX)
        inner_json = json.loads(m.group(1))
        return json.loads(inner_json)
    raise ScraperError("window._gallery not found in nhentai page HTML")


class NhentaiScraper(BaseScraper):
    source_key = SourceKey.NHENTAI
    content_type = "comic"
    requires_browser = False
    request_delay_seconds = 1.5
    max_retries = 3

    async def get_story_metadata(self, url: str) -> StoryMetadata:
        gallery_id = _gallery_id(url)
        html = await self._fetch(f"https://nhentai.net/g/{gallery_id}/")
        gallery = _parse_gallery(html)

        titles = gallery.get("title", {})
        title = (
            titles.get("english")
            or titles.get("pretty")
            or titles.get("japanese")
            or "Unknown Title"
        )

        tags = gallery.get("tags", [])
        authors = [t["name"] for t in tags if t.get("type") == "artist"]
        language = next(
            (t["name"] for t in tags if t.get("type") == "language" and t["name"] != "translated"),
            None,
        )
        tag_list = [
            {"name": t["name"], "tag_type": t["type"]}
            for t in tags
            if t.get("type") not in ("language", "artist")
        ]

        return StoryMetadata(
            title=title,
            source_url=url,
            source_key=self.source_key,
            source_id=str(gallery_id),
            authors=authors,
            language=language,
            tags=tag_list,
            total_chapters=1,
        )

    async def get_chapter_list(self, story_url: str) -> list[ChapterInfo]:
        # nhentai galleries are single-chapter
        return [ChapterInfo(chapter_number=1.0, source_url=story_url, title="Gallery")]

    async def get_chapter_pages(self, chapter_url: str) -> list[PageInfo]:
        gallery_id = _gallery_id(chapter_url)
        html = await self._fetch(f"https://nhentai.net/g/{gallery_id}/")
        gallery = _parse_gallery(html)

        media_id = gallery["media_id"]
        raw_pages = gallery["images"]["pages"]

        pages = []
        for i, page in enumerate(raw_pages, start=1):
            ext = _EXT_MAP.get(page.get("t", "j"), "jpg")
            pages.append(PageInfo(
                page_number=i,
                source_url=f"https://i1.nhentai.net/galleries/{media_id}/{i}.{ext}",
                width_px=page.get("w"),
                height_px=page.get("h"),
            ))
        return pages

    async def get_chapter_text(self, chapter_url: str) -> str:
        raise NotImplementedError("nhentai is a comic source — no text content")
