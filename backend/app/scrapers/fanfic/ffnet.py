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


def _chapter_url(story_id: str, chapter_num: int) -> str:
    return f"https://www.fanfiction.net/s/{story_id}/{chapter_num}/"


class FanfictionNetScraper(BaseScraper):
    source_key = SourceKey.FFNET
    content_type = "fanfic"
    requires_browser = False
    request_delay_seconds = 1.5
    max_retries = 3

    async def get_story_metadata(self, url: str) -> StoryMetadata:
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
            # No dropdown means single-chapter story
            total_chapters = 1

        return StoryMetadata(
            title=title,
            source_url=url,
            source_key=self.source_key,
            source_id=sid,
            description=description,
            authors=authors,
            total_chapters=total_chapters,
        )

    async def get_chapter_list(self, story_url: str) -> list[ChapterInfo]:
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
        html = await self._fetch(chapter_url)
        soup = BeautifulSoup(html, "lxml")

        content_div = soup.select_one("#storytext")
        if not content_div:
            return ""

        paragraphs = [p.get_text(separator="\n", strip=True) for p in content_div.find_all("p")]
        return "\n\n".join(p for p in paragraphs if p)
