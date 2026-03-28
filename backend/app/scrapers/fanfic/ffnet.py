import re
from bs4 import BeautifulSoup
from app.scrapers.base import BaseScraper, StoryMetadata, ChapterInfo, PageInfo
from app.core.constants import SourceKey


def _story_id(url: str) -> str:
    """Extract numeric story ID from any FFNet /s/ URL."""
    m = re.search(r"/s/(\d+)", url)
    if not m:
        raise ValueError(f"Cannot extract FFNet story ID from URL: {url}")
    return m.group(1)


def _normalize_url(url: str) -> str:
    """Normalize m.fanfiction.net → www.fanfiction.net so cookies and selectors work."""
    return re.sub(r"https?://m\.fanfiction\.net", "https://www.fanfiction.net", url)


def _chapter_url(story_id: str, chapter_num: int) -> str:
    return f"https://www.fanfiction.net/s/{story_id}/{chapter_num}/"


class FanfictionNetScraper(BaseScraper):
    source_key = SourceKey.FFNET
    content_type = "fanfic"
    requires_browser = False
    request_delay_seconds = 1.5
    max_retries = 3

    async def get_story_metadata(self, url: str) -> StoryMetadata:
        url = _normalize_url(url)
        sid = _story_id(url)
        html = await self._fetch(_chapter_url(sid, 1))
        soup = BeautifulSoup(html, "lxml")

        title_tag = soup.select_one("#profile_top b.xcontrast_txt")
        title = title_tag.get_text(strip=True) if title_tag else "Unknown Title"

        author_tag = soup.select_one("#profile_top a.xcontrast_txt")
        authors = [author_tag.get_text(strip=True)] if author_tag else []

        summary_tag = soup.select_one("#profile_top div.xcontrast_txt")
        description = summary_tag.get_text(strip=True) if summary_tag else None

        # Chapter count comes from the chapter select dropdown
        total_chapters = None
        chap_select = soup.select_one("#chap_select")
        if chap_select:
            options = chap_select.find_all("option")
            total_chapters = len(options) if options else 1
        else:
            total_chapters = 1

        # Parse the metadata line:
        # "Rated: Fiction T - English - Adventure/Romance - Harry P., ... - Words: 184,603 ..."
        rating = None
        language = None
        word_count = None
        characters = None
        fandom = None
        tags = []
        completion_status = "ongoing"
        published_at = None
        updated_at_source = None

        # Fandom from breadcrumb (e.g. "Harry Potter")
        breadcrumb_links = soup.select("#pre_story_links a")
        if len(breadcrumb_links) >= 2:
            fandom = breadcrumb_links[-1].get_text(strip=True)

        # Metadata span — last span in #profile_top
        meta_spans = soup.select("#profile_top span.xgray")
        meta_text = meta_spans[-1].get_text() if meta_spans else ""
        if not meta_text:
            # Fallback: grab the full text of the container
            profile = soup.select_one("#profile_top")
            meta_text = profile.get_text() if profile else ""

        # Rating: "Fiction T", "Fiction M", "Fiction K+", etc.
        m = re.search(r"Rated:\s*(?:Fiction\s+)?([TKMA][+]?)", meta_text)
        if m:
            rating = m.group(1)

        # Language
        m = re.search(r"Fiction\s+\S+\s+-\s+(\w+)\s+-", meta_text)
        if m:
            language = m.group(1)

        # Genre (between language and characters/chapters marker)
        m = re.search(r"Fiction\s+\S+\s+-\s+\w+\s+-\s+([^-]+?)\s+-", meta_text)
        if m:
            genre_text = m.group(1).strip()
            # Genres like "Adventure/Romance" or "Drama"
            for g in genre_text.split("/"):
                g = g.strip()
                if g and not re.match(r"^(Chapters|Words|Reviews)", g):
                    tags.append({"name": g, "tag_type": "genre"})

        # Characters — text segment that contains character names before " - Chapters:"
        m = re.search(r"-\s+([A-Z][\w. ]+(?:,\s*[A-Z][\w. ]+)*)\s+-\s*Chapters:", meta_text)
        if m:
            characters = m.group(1).strip()

        # Words
        m = re.search(r"Words:\s*([\d,]+)", meta_text)
        if m:
            try:
                word_count = int(m.group(1).replace(",", ""))
            except ValueError:
                pass

        # Published
        m = re.search(r"Published:\s*([A-Za-z]+ \d+,? \d{4})", meta_text)
        if m:
            published_at = m.group(1)

        # Updated
        m = re.search(r"Updated:\s*([A-Za-z]+ \d+,? \d{4})", meta_text)
        if m:
            updated_at_source = m.group(1)

        # Completion — FFNet shows "Status: Complete" in metadata
        if "Status: Complete" in meta_text or "Complete" in meta_text:
            completion_status = "complete"

        return StoryMetadata(
            title=title,
            source_url=url,
            source_key=self.source_key,
            source_id=sid,
            description=description,
            authors=authors,
            total_chapters=total_chapters,
            language=language,
            fandom=fandom,
            rating=rating,
            characters=characters,
            word_count=word_count,
            completion_status=completion_status,
            published_at=published_at,
            updated_at_source=updated_at_source,
            tags=tags,
        )

    async def get_chapter_list(self, story_url: str) -> list[ChapterInfo]:
        story_url = _normalize_url(story_url)
        sid = _story_id(story_url)
        html = await self._fetch(_chapter_url(sid, 1))
        soup = BeautifulSoup(html, "lxml")

        chap_select = soup.select_one("#chap_select")
        if chap_select:
            chapters = []
            for opt in chap_select.find_all("option"):
                num = int(opt.get("value", 0))
                if num == 0:
                    continue
                title = opt.get_text(strip=True)
                # Strip leading "N. " prefix FFNet adds
                title = re.sub(r"^\d+\.\s*", "", title)
                chapters.append(ChapterInfo(
                    chapter_number=float(num),
                    source_url=_chapter_url(sid, num),
                    title=title or f"Chapter {num}",
                ))
            return chapters

        # Single-chapter story
        return [ChapterInfo(
            chapter_number=1.0,
            source_url=_chapter_url(sid, 1),
            title="Chapter 1",
        )]

    async def get_chapter_pages(self, chapter_url: str) -> list[PageInfo]:
        raise NotImplementedError("ffnet is a fanfic source — no pages")

    async def get_chapter_text(self, chapter_url: str) -> str:
        chapter_url = _normalize_url(chapter_url)
        html = await self._fetch(chapter_url)
        soup = BeautifulSoup(html, "lxml")

        content_div = soup.select_one("#storytext")
        if not content_div:
            return ""

        paragraphs = [p.get_text(separator="\n", strip=True) for p in content_div.find_all("p")]
        return "\n\n".join(p for p in paragraphs if p)
