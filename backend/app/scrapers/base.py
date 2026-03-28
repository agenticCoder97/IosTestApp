import asyncio
import json
import logging
import random
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Optional
import httpx
import redis.asyncio as aioredis
from curl_cffi.requests import AsyncSession as CurlSession
from app.core.config import settings
from app.core.constants import COOKIE_CACHE_KEY_PREFIX

# Impersonate Chrome 120 — well-supported by curl_cffi 0.7.x and passes
# Cloudflare's TLS/JA3 fingerprint checks without a real browser.
_CF_IMPERSONATE = "chrome120"

logger = logging.getLogger(__name__)


class CookieExpiredError(Exception):
    """Raised when source returns 403 — caller should return HTTP 428 to iOS."""


class ScraperError(Exception):
    """Raised when max retries exhausted."""


@dataclass
class StoryMetadata:
    title: str
    source_url: str
    source_key: str
    source_id: Optional[str] = None
    description: Optional[str] = None
    language: Optional[str] = None
    authors: list[str] = field(default_factory=list)
    tags: list[dict] = field(default_factory=list)  # {"name": str, "tag_type": str}
    thumbnail_url: Optional[str] = None
    total_chapters: Optional[int] = None


@dataclass
class ChapterInfo:
    chapter_number: float
    source_url: str
    title: Optional[str] = None


@dataclass
class PageInfo:
    page_number: int
    source_url: str
    width_px: Optional[int] = None
    height_px: Optional[int] = None


class BaseScraper(ABC):
    source_key: str
    content_type: str
    requires_browser: bool = False
    request_delay_seconds: float = 1.0
    max_retries: int = 3

    # In-process cookie cache — populated on first call, lives for the scraper
    # instance lifetime (one task run). Invalidated on 403 so a fresh Redis
    # read is forced after the iOS browser refreshes the session.
    _cookie_cache: tuple[list[dict], str] | None = None

    async def _get_cookies(self) -> tuple[list[dict], str]:
        """Load cookies and user_agent from Redis, cached for this scraper instance."""
        if self._cookie_cache is not None:
            logger.debug("_get_cookies cache hit | source_key=%s cookies=%d",
                         self.source_key, len(self._cookie_cache[0]))
            return self._cookie_cache

        logger.debug("_get_cookies loading from Redis | source_key=%s", self.source_key)
        r = await aioredis.from_url(settings.redis_url)
        try:
            raw = await r.get(f"{COOKIE_CACHE_KEY_PREFIX}{self.source_key}")
            if not raw:
                # Expected for sources that don't require cookies (e.g. nhentai public).
                # Logged at DEBUG only — this appears hundreds of times per job otherwise.
                logger.debug("_get_cookies no cached cookies | source_key=%s (proceeding without)",
                             self.source_key)
                result = ([], "Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X)")
            else:
                data = json.loads(raw)
                cookies = data.get("cookies", [])
                user_agent = data.get("user_agent", "")
                logger.info("_get_cookies loaded %d cookies | source_key=%s ua=%s",
                            len(cookies), self.source_key, user_agent[:40] if user_agent else "none")
                result = (cookies, user_agent)
            self._cookie_cache = result
            return result
        finally:
            await r.aclose()

    async def _fetch(self, url: str) -> str:
        """
        Rate-limited fetch with retry + exponential backoff using curl_cffi for TLS
        impersonation.

        403 → CookieExpiredError (invalidates cookie cache; caller returns 428 to iOS).
        429/503/52x → exponential backoff with jitter.
        max_retries exhausted → ScraperError.
        """
        cookies_list, user_agent = await self._get_cookies()
        cookies = {c["name"]: c["value"] for c in cookies_list}

        logger.debug("_fetch starting | url=%s delay=%.1fs cookies=%d",
                     url, self.request_delay_seconds, len(cookies))
        await asyncio.sleep(self.request_delay_seconds)

        for attempt in range(self.max_retries):
            logger.debug("_fetch attempt %d/%d | url=%s", attempt + 1, self.max_retries, url)
            try:
                async with CurlSession(impersonate=_CF_IMPERSONATE) as session:
                    response = await session.get(
                        url,
                        cookies=cookies,
                        headers={"User-Agent": user_agent} if user_agent else {},
                        timeout=60,
                    )

                if response.status_code == 200:
                    logger.debug("_fetch ok | url=%s bytes=%d attempt=%d",
                                 url, len(response.content), attempt + 1)
                    return response.text
                elif response.status_code == 403:
                    self._cookie_cache = None  # force re-read from Redis on next call
                    logger.error("_fetch 403 blocked | url=%s — cookies invalidated", url)
                    raise CookieExpiredError(
                        f"403 from {url} — Cloudflare blocked or session expired. "
                        "Open the site in the iOS browser to refresh cookies, then retry."
                    )
                elif response.status_code in (429, 503, 525, 520, 521, 522, 523, 524):
                    retry_after = response.headers.get("Retry-After")
                    try:
                        wait = float(retry_after) if retry_after else (2 ** attempt) + random.uniform(0, 1)
                    except ValueError:
                        wait = (2 ** attempt) + random.uniform(0, 1)
                    logger.warning(
                        "_fetch %d rate-limited | url=%s wait=%.1fs attempt=%d/%d",
                        response.status_code, url, wait, attempt + 1, self.max_retries,
                    )
                    await asyncio.sleep(wait)
                else:
                    logger.error("_fetch unexpected status %d | url=%s", response.status_code, url)
                    raise ScraperError(f"HTTP {response.status_code} from {url}")
            except CookieExpiredError:
                raise
            except ScraperError:
                raise
            except Exception as e:
                if attempt == self.max_retries - 1:
                    logger.error("_fetch max retries exhausted | url=%s error=%s", url, e, exc_info=True)
                    err_msg = str(e) if str(e) else type(e).__name__
                    raise ScraperError(f"Failed after {self.max_retries} attempts: {err_msg}") from e
                wait = (2 ** attempt) + random.uniform(0, 1)
                logger.warning(
                    "_fetch error, retrying | url=%s attempt=%d/%d wait=%.1fs error=%s",
                    url, attempt + 1, self.max_retries, wait, repr(e),
                )
                await asyncio.sleep(wait)

        logger.error("_fetch max retries exhausted (loop end) | url=%s retries=%d", url, self.max_retries)
        raise ScraperError(f"Max retries ({self.max_retries}) exhausted for {url}")

    async def download_image(self, url: str, dest_path: str) -> str:
        """Download image to dest_path. Returns file_path (relative to block volume)."""
        from pathlib import Path
        logger.debug("download_image | url=%s -> %s", url, dest_path)
        cookies_list, user_agent = await self._get_cookies()
        cookies = {c["name"]: c["value"] for c in cookies_list}

        await asyncio.sleep(self.request_delay_seconds)

        async with CurlSession(impersonate=_CF_IMPERSONATE) as session:
            response = await session.get(
                url,
                cookies=cookies,
                headers={"User-Agent": user_agent} if user_agent else {},
                timeout=90,
            )

        if response.status_code == 403:
            self._cookie_cache = None
            logger.error("download_image 403 blocked | url=%s — cookies invalidated", url)
            raise CookieExpiredError(f"403 downloading image from {url}")

        if response.status_code != 200:
            logger.error("download_image failed | url=%s status=%d", url, response.status_code)
            raise ScraperError(f"HTTP {response.status_code} downloading image from {url}")

        full_path = Path(settings.block_volume_path) / dest_path
        full_path.parent.mkdir(parents=True, exist_ok=True)
        full_path.write_bytes(response.content)
        file_size = len(response.content)
        logger.debug("download_image saved | dest=%s size_bytes=%d", dest_path, file_size)
        return dest_path

    @abstractmethod
    async def get_story_metadata(self, url: str) -> StoryMetadata: ...

    @abstractmethod
    async def get_chapter_list(self, story_url: str) -> list[ChapterInfo]: ...

    @abstractmethod
    async def get_chapter_pages(self, chapter_url: str) -> list[PageInfo]: ...

    @abstractmethod
    async def get_chapter_text(self, chapter_url: str) -> str: ...
