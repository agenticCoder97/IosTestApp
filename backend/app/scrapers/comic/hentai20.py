import json
import re
from bs4 import BeautifulSoup
from app.scrapers.base import BaseScraper, StoryMetadata, ChapterInfo, PageInfo, ScraperError
from app.core.constants import SourceKey


def _slug(url: str) -> str:
    """Extract series slug from a /manga/{slug}/ URL."""
    m = re.search(r"/manga/([^/?#]+)", url)
    if not m:
        raise ValueError(f"Cannot extract hentai20 series slug from URL: {url}")
    return m.group(1)


def _slug_from_chapter_url(url: str) -> str:
    """Extract series slug from a /{slug}-chapter-N/ URL."""
    m = re.search(r"hentai20\.io/([^/]+)-chapter-\d", url)
    if not m:
        raise ValueError(f"Cannot extract hentai20 slug from chapter URL: {url}")
    return m.group(1)


def _chapter_num(url: str) -> float:
    m = re.search(r"-chapter-(\d+(?:\.\d+)?)", url)
    return float(m.group(1)) if m else 0.0


class Hentai20Scraper(BaseScraper):
    source_key = SourceKey.HENTAI20
    content_type = "comic"
    # Images and chapter list are in the raw HTML — no JS engine needed
    requires_browser = False
    request_delay_seconds = 2.0
    max_retries = 3

    async def get_story_metadata(self, url: str) -> StoryMetadata:
        html = await self._fetch(url)
        soup = BeautifulSoup(html, "lxml")

        title_tag = soup.select_one(".post-title h1, h1.entry-title, h1")
        title = title_tag.get_text(strip=True) if title_tag else "Unknown Title"

        desc_tag = soup.select_one(".summary__content, .entry-content > p, .description")
        description = desc_tag.get_text(strip=True) if desc_tag else None

        thumb_tag = soup.select_one(".summary_image img, .tab-thumb img, .post-title img")
        thumbnail_url = None
        if thumb_tag:
            thumbnail_url = (thumb_tag.get("data-src") or thumb_tag.get("src") or "").strip() or None

        # Author (Madara theme — same selector as toongod)
        author_tag = soup.select_one(".author-content a")
        authors = [author_tag.get_text(strip=True)] if author_tag else []

        # Genre tags (Madara theme)
        genre_tags = soup.select(".genres-content a")
        tags = [{"name": a.get_text(strip=True), "tag_type": "genre"} for a in genre_tags]

        slug = _slug(url)
        chapter_links = soup.find_all(
            "a", href=re.compile(rf"hentai20\.io/{re.escape(slug)}-chapter-\d")
        )
        unique_links = {a["href"] for a in chapter_links if "{{" not in a["href"]}
        total_chapters = len(unique_links) or None

        return StoryMetadata(
            title=title,
            source_url=url,
            source_key=self.source_key,
            source_id=slug,
            description=description,
            authors=authors,
            tags=tags,
            thumbnail_url=thumbnail_url,
            total_chapters=total_chapters,
        )

    async def get_chapter_list(self, story_url: str) -> list[ChapterInfo]:
        html = await self._fetch(story_url)
        soup = BeautifulSoup(html, "lxml")

        # All chapter <li> items are pre-rendered in the HTML.
        # Filter out the template placeholder (href contains "{{").
        all_anchors = soup.find_all(
            "a", href=re.compile(r"hentai20\.io/[^/]+-chapter-(\d+(?:\.\d+)?)")
        )

        seen: set[str] = set()
        chapters: list[ChapterInfo] = []
        for a in all_anchors:
            href = a["href"]
            if "{{" in href or href in seen:
                continue
            seen.add(href)
            num = _chapter_num(href)
            if num == 0.0:
                continue
            # Text is "Chapter N\nDate" — keep only the chapter label
            raw_text = a.get_text(separator=" ", strip=True)
            # Strip trailing month name + date: "Chapter 5 March 20, 2026" → "Chapter 5"
            ch_title = re.sub(
                r"\s+(?:January|February|March|April|May|June|July|August|September|"
                r"October|November|December)\b.*$",
                "",
                raw_text,
                flags=re.IGNORECASE,
            ).strip()
            chapters.append(ChapterInfo(
                chapter_number=num,
                source_url=href,
                title=ch_title or f"Chapter {int(num)}",
            ))

        # Chapters may appear descending in HTML — sort ascending
        return sorted(chapters, key=lambda c: c.chapter_number)

    async def get_chapter_pages(self, chapter_url: str) -> list[PageInfo]:
        html = await self._fetch(chapter_url)

        # Image URLs live in an inline script: ts_reader.run({...})
        m = re.search(r"ts_reader\.run\(", html)
        if not m:
            raise ScraperError(f"ts_reader.run not found in page: {chapter_url}")

        try:
            data, _ = json.JSONDecoder().raw_decode(html, m.end())
        except json.JSONDecodeError as exc:
            raise ScraperError(f"Failed to parse ts_reader data: {exc}") from exc

        sources = data.get("sources", [])
        if not sources:
            raise ScraperError(f"No image sources in ts_reader data: {chapter_url}")

        images = sources[0].get("images", [])
        return [
            PageInfo(page_number=i + 1, source_url=img_url)
            for i, img_url in enumerate(images)
            if img_url
        ]

    async def get_chapter_text(self, chapter_url: str) -> str:
        raise NotImplementedError("hentai20 is a comic source — no text content")
