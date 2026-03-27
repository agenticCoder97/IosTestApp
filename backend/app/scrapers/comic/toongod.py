from app.scrapers.base import BaseScraper, StoryMetadata, ChapterInfo, PageInfo
from app.core.constants import SourceKey


class ToongodScraper(BaseScraper):
    source_key = SourceKey.TOONGOD
    content_type = "comic"
    requires_browser = False
    request_delay_seconds = 1.0
    max_retries = 3

    async def get_story_metadata(self, url: str) -> StoryMetadata:
        raise NotImplementedError

    async def get_chapter_list(self, story_url: str) -> list[ChapterInfo]:
        raise NotImplementedError

    async def get_chapter_pages(self, chapter_url: str) -> list[PageInfo]:
        raise NotImplementedError

    async def get_chapter_text(self, chapter_url: str) -> str:
        raise NotImplementedError("toongod is a comic source")
