"""FFNet scraper — primary path uses FanFicFare, fallback uses FicHub.

This is the AST-29 rewrite. Most of the heavy lifting (Cloudflare bypass,
chapter HTML parsing, retry/backoff) is delegated to FanFicFare. When FFF
hits a hard error (CF block after retry, parser regression, network issue),
we fall through to FicHub's archive.

Set FFNET_NEW_SCRAPER_DISABLED=true to skip FanFicFare entirely and use
FicHub as the only source.
"""
from __future__ import annotations

import logging

import httpx

from app.core.config import settings
from app.core.constants import SourceKey
from app.scrapers.base import (
    BaseScraper, ChapterInfo, CookieExpiredError, PageInfo, StoryMetadata,
)
from app.scrapers.fanfic import _fanficfare_runner, _fichub

logger = logging.getLogger(__name__)

_PRIMARY_ERRORS = (_fanficfare_runner.FanFicFareError, CookieExpiredError, httpx.HTTPError)


class FanfictionNetScraper(BaseScraper):
    source_key = SourceKey.FFNET
    content_type = "fanfic"
    requires_browser = False

    # Per-instance cache of the resolved (meta, chapters) tuple so that
    # get_story_metadata, get_chapter_list, and get_chapter_text don't
    # re-fetch the same story.
    _runner_cache: tuple[StoryMetadata, list[_fichub.ChapterText]] | None = None
    _fichub_cache: tuple[StoryMetadata, list[_fichub.ChapterText]] | None = None

    async def _resolve(self, url: str) -> tuple[StoryMetadata, list[_fichub.ChapterText]]:
        """Run the primary-then-fallback resolution once per scraper instance."""
        if self._runner_cache is not None:
            return self._runner_cache
        if self._fichub_cache is not None:
            return self._fichub_cache

        primary_err: Exception | None = None
        from app.core.runtime_flags import flag_enabled
        ffnet_disabled = await flag_enabled(
            "FFNET_NEW_SCRAPER_DISABLED", default=settings.ffnet_new_scraper_disabled,
        )
        if not ffnet_disabled:
            try:
                cookies, ua = await self._get_cookies()
                meta, chapters = await _fanficfare_runner.fetch_via_fanficfare(url, cookies, ua)
                self._runner_cache = (meta, chapters)
                logger.info("ffnet primary (FanFicFare) ok | url=%s chapters=%d", url, len(chapters))
                return self._runner_cache
            except _PRIMARY_ERRORS as e:
                primary_err = e
                logger.warning("ffnet primary failed, trying FicHub | url=%s err=%s", url, e)

        try:
            fh_meta = await _fichub.fetch_story_meta(url)
            if not fh_meta.title or fh_meta.title.lower() in ("unknown title", "unknown"):
                raise _fichub.FicHubError(f"FicHub returned invalid title for {url}: {fh_meta.title!r}")
            chapters = await _fichub.download_and_split_epub(fh_meta.epub_url)
            meta = StoryMetadata(
                title=fh_meta.title,
                source_url=url,
                source_key=self.source_key,
                source_id=fh_meta.url_id,
                description=fh_meta.summary,
                authors=[fh_meta.author] if fh_meta.author else [],
                total_chapters=fh_meta.chapters,
                fandom=fh_meta.fandoms[0] if fh_meta.fandoms else None,
                word_count=fh_meta.word_count,
                completion_status=fh_meta.status,
            )
            self._fichub_cache = (meta, chapters)
            logger.info("ffnet fallback (FicHub) ok | url=%s chapters=%d", url, len(chapters))
            return self._fichub_cache
        except _fichub.FicHubError:
            if primary_err is None:
                raise
            raise primary_err

    async def get_story_metadata(self, url: str) -> StoryMetadata:
        meta, _ = await self._resolve(url)
        return meta

    async def get_chapter_list(self, story_url: str) -> list[ChapterInfo]:
        _, chapters = await self._resolve(story_url)
        return [
            ChapterInfo(
                chapter_number=float(c.number),
                source_url=f"{story_url.rstrip('/')}#chapter-{c.number}",
                title=c.title,
            )
            for c in chapters
        ]

    async def get_chapter_text(self, chapter_url: str) -> str:
        # Chapter URLs we generate are "<story_url>#chapter-<n>". Strip the
        # fragment, resolve the story once (cached), and look up by number.
        if "#chapter-" not in chapter_url:
            raise ValueError(f"Unexpected chapter URL format: {chapter_url}")
        story_url, _, frag = chapter_url.partition("#chapter-")
        try:
            chapter_num = int(frag)
        except ValueError as e:
            raise ValueError(f"Unparseable chapter number in {chapter_url}") from e

        _, chapters = await self._resolve(story_url)
        for c in chapters:
            if c.number == chapter_num:
                return c.html
        raise ValueError(f"Chapter {chapter_num} not found in resolved story")

    async def get_chapter_pages(self, chapter_url: str) -> list[PageInfo]:
        raise NotImplementedError("ffnet is a fanfic source — no pages")
