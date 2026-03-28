import re
from bs4 import BeautifulSoup
from app.scrapers.base import BaseScraper, StoryMetadata, ChapterInfo, PageInfo, ScraperError
from app.core.constants import SourceKey


def _slug(url: str) -> str:
    m = re.search(r"/webtoon/([^/?#]+)", url)
    if not m:
        raise ValueError(f"Cannot extract toongod slug from URL: {url}")
    return m.group(1)


class ToongodScraper(BaseScraper):
    source_key = SourceKey.TOONGOD
    content_type = "comic"
    requires_browser = False
    request_delay_seconds = 1.0
    max_retries = 3

    async def get_story_metadata(self, url: str) -> StoryMetadata:
        # Normalise to series root (strip any chapter suffix)
        series_url = re.sub(r"/chapter-[^/]+/?$", "/", url)
        html = await self._fetch(series_url)
        soup = BeautifulSoup(html, "lxml")

        title_tag = soup.select_one(".post-title h1")
        title = title_tag.get_text(strip=True) if title_tag else "Unknown Title"

        author_tag = soup.select_one(".author-content a")
        authors = [author_tag.get_text(strip=True)] if author_tag else []

        desc_tag = soup.select_one(".summary__content p, .summary__content")
        description = desc_tag.get_text(strip=True) if desc_tag else None

        chapter_items = soup.select(".wp-manga-chapter")
        total_chapters = len(chapter_items) or None

        return StoryMetadata(
            title=title,
            source_url=url,
            source_key=self.source_key,
            source_id=_slug(url),
            description=description,
            authors=authors,
            total_chapters=total_chapters,
        )

    async def get_chapter_list(self, story_url: str) -> list[ChapterInfo]:
        series_url = re.sub(r"/chapter-[^/]+/?$", "/", story_url)
        html = await self._fetch(series_url)
        soup = BeautifulSoup(html, "lxml")

        # Chapters are in descending order in the HTML — reverse to ascending
        items = list(reversed(soup.select(".wp-manga-chapter")))
        chapters = []
        for item in items:
            a = item.select_one("a")
            if not a:
                continue
            href = (a.get("href") or "").strip()
            text = a.get_text(strip=True)
            # Extract number from "Chapter 145 - Fixed" → 145.0
            m = re.search(r"(?:Chapter|Ch\.?)\s+(\d+(?:\.\d+)?)", text, re.IGNORECASE)
            if not m:
                continue
            num = float(m.group(1))
            # Keep the full text as title but normalise whitespace
            ch_title = re.sub(r"\s+", " ", text).strip()
            chapters.append(ChapterInfo(
                chapter_number=num,
                source_url=href,
                title=ch_title,
            ))
        return chapters

    async def get_chapter_pages(self, chapter_url: str) -> list[PageInfo]:
        html = await self._fetch(chapter_url)
        soup = BeautifulSoup(html, "lxml")

        imgs = soup.select(".reading-content img, .page-break img")
        if not imgs:
            raise ScraperError(f"No images found in toongod chapter: {chapter_url}")

        pages = []
        for i, img in enumerate(imgs, start=1):
            # Madara theme may use data-src for lazy loading; fall back to src
            src = (
                img.get("data-src")
                or img.get("data-lazy-src")
                or img.get("src")
                or ""
            ).strip()
            if not src or src.startswith("data:"):
                continue
            pages.append(PageInfo(page_number=i, source_url=src))
        return pages

    async def get_chapter_text(self, chapter_url: str) -> str:
        raise NotImplementedError("toongod is a comic source — no text content")
