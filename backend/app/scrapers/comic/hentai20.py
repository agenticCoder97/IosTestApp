from app.scrapers.base import BaseScraper, StoryMetadata, ChapterInfo, PageInfo
from app.core.constants import SourceKey


class Hentai20Scraper(BaseScraper):
    source_key = SourceKey.HENTAI20
    content_type = "comic"
    requires_browser = True
    request_delay_seconds = 2.0
    max_retries = 3

    async def get_story_metadata(self, url: str) -> StoryMetadata:
        raise NotImplementedError

    async def get_chapter_list(self, story_url: str) -> list[ChapterInfo]:
        raise NotImplementedError

    async def get_chapter_pages(self, chapter_url: str) -> list[PageInfo]:
        # Uses Playwright pool — JS rendering required for image URL extraction
        raise NotImplementedError

    async def get_chapter_text(self, chapter_url: str) -> str:
        raise NotImplementedError("hentai20 is a comic source")
