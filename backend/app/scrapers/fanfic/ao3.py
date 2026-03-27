from app.scrapers.base import BaseScraper, StoryMetadata, ChapterInfo, PageInfo
from app.core.constants import SourceKey


class AO3Scraper(BaseScraper):
    source_key = SourceKey.AO3
    content_type = "fanfic"
    requires_browser = False  # AO3 has no Cloudflare
    request_delay_seconds = 2.0  # Strict AO3 rate limit
    max_retries = 3

    async def get_story_metadata(self, url: str) -> StoryMetadata:
        raise NotImplementedError

    async def get_chapter_list(self, story_url: str) -> list[ChapterInfo]:
        raise NotImplementedError

    async def get_chapter_pages(self, chapter_url: str) -> list[PageInfo]:
        raise NotImplementedError("ao3 is a fanfic source")

    async def get_chapter_text(self, chapter_url: str) -> str:
        raise NotImplementedError
