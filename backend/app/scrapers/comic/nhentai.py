from app.scrapers.base import BaseScraper, StoryMetadata, ChapterInfo, PageInfo
from app.core.constants import SourceKey


class NhentaiScraper(BaseScraper):
    source_key = SourceKey.NHENTAI
    content_type = "comic"
    requires_browser = False
    request_delay_seconds = 1.5
    max_retries = 3

    async def get_story_metadata(self, url: str) -> StoryMetadata:
        # TODO: implement nhentai gallery metadata parsing
        raise NotImplementedError

    async def get_chapter_list(self, story_url: str) -> list[ChapterInfo]:
        # nhentai galleries are single-chapter
        return [ChapterInfo(chapter_number=1.0, source_url=story_url)]

    async def get_chapter_pages(self, chapter_url: str) -> list[PageInfo]:
        # TODO: parse image URLs from nhentai gallery page
        raise NotImplementedError

    async def get_chapter_text(self, chapter_url: str) -> str:
        raise NotImplementedError("nhentai is a comic source — no text content")
