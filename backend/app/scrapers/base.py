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

    async def _get_cookies(self) -> tuple[list[dict], str]:
        """Load cookies and user_agent from Redis for this source_key."""
        logger.debug("_get_cookies loading | source_key=%s", self.source_key)
        r = await aioredis.from_url(settings.redis_url)
        try:
            raw = await r.get(f"{COOKIE_CACHE_KEY_PREFIX}{self.source_key}")
            if not raw:
                logger.warning("_get_cookies no cached cookies found | source_key=%s", self.source_key)
                return [], "Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X)"
            data = json.loads(raw)
            cookies = data.get("cookies", [])
            logger.info("_get_cookies loaded %d cookies | source_key=%s", len(cookies), self.source_key)
            return cookies, data.get("user_agent", "")
        finally:
            await r.aclose()

    async def _fetch(self, url: str) -> str:
        """
        Rate-limited fetch with backoff using curl_cffi for TLS impersonation.
        Impersonates Safari 17.2 so Cloudflare's JA3/JA4 fingerprint checks pass
        without a real browser.  Any cached cookies from iOS (cf_clearance etc.)
        are still forwarded and act as a session-continuity boost.

        403 → CookieExpiredError (caller returns 428 to iOS).
        429/503/52x → exponential backoff with jitter.
        max_retries exhausted → ScraperError.
        """
        cookies_list, user_agent = await self._get_cookies()
        cookies = {c["name"]: c["value"] for c in cookies_list}

        logger.info("_fetch starting | url=%s delay=%.1fs cookies=%d",
                    url, self.request_delay_seconds, len(cookies))
        await asyncio.sleep(self.request_delay_seconds)

        for attempt in range(self.max_retries):
            logger.info("_fetch attempt %d/%d | url=%s", attempt + 1, self.max_retries, url)
            try:
                async with CurlSession(impersonate=_CF_IMPERSONATE) as session:
                    response = await session.get(
                        url,
                        cookies=cookies,
                        headers={"User-Agent": user_agent} if user_agent else {},
                        timeout=60,
                    )

                if response.status_code == 200:
                    logger.info("_fetch success | url=%s status=200 attempt=%d", url, attempt + 1)
                    return response.text
                elif response.status_code == 403:
                    logger.error("_fetch 403 Cloudflare/auth blocked | url=%s", url)
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
                        "_fetch %d backoff | url=%s wait=%.1fs attempt=%d/%d",
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
                    logger.error("_fetch max retries exhausted | url=%s error=%s", url, e)
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
        logger.info("download_image starting | url=%s dest_path=%s", url, dest_path)
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
            response.raise_for_status()

        full_path = Path(settings.block_volume_path) / dest_path
        full_path.parent.mkdir(parents=True, exist_ok=True)
        full_path.write_bytes(response.content)
        file_size = len(response.content)
        logger.info("download_image complete | url=%s dest_path=%s size_bytes=%d", url, dest_path, file_size)
        return dest_path

    @abstractmethod
    async def get_story_metadata(self, url: str) -> StoryMetadata: ...

    @abstractmethod
    async def get_chapter_list(self, story_url: str) -> list[ChapterInfo]: ...

    @abstractmethod
    async def get_chapter_pages(self, chapter_url: str) -> list[PageInfo]: ...

    @abstractmethod
    async def get_chapter_text(self, chapter_url: str) -> str: ...
