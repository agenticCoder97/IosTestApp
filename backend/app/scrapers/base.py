import asyncio
import json
import logging
import random
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Optional
import httpx
from curl_cffi.requests import AsyncSession as CurlSession
from app.cache.redis_pool import get_cache_redis
from app.core.config import settings
from app.core.constants import COOKIE_CACHE_KEY_PREFIX

# Impersonate Safari iOS 17.2 — matches the TLS fingerprint of the iOS
# WKWebView that harvests Cloudflare cookies. Using Chrome here would cause
# cf_clearance cookies (issued to Safari) to be rejected by Cloudflare.
_CF_IMPERSONATE = "safari17_2_ios"

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
    # Extended metadata (populated by some scrapers)
    category: Optional[str] = None
    fandom: Optional[str] = None
    rating: Optional[str] = None
    warnings: Optional[str] = None
    characters: Optional[str] = None
    pairing: Optional[str] = None
    word_count: Optional[int] = None
    completion_status: Optional[str] = None
    published_at: Optional[str] = None   # ISO 8601 string
    updated_at_source: Optional[str] = None  # ISO 8601 string
    freeform_tags: Optional[str] = None  # comma-separated freeform tag names
    hits: Optional[int] = None
    kudos: Optional[int] = None
    comments_count: Optional[int] = None
    bookmarks_count: Optional[int] = None


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
    _browser_cookie_attempted: bool = False  # only try headless browser once per scraper instance

    async def _get_cookies(self) -> tuple[list[dict], str]:
        """Load cookies and user_agent from Redis, cached for this scraper instance."""
        if self._cookie_cache is not None:
            logger.debug("_get_cookies cache hit | source_key=%s cookies=%d",
                         self.source_key, len(self._cookie_cache[0]))
            return self._cookie_cache

        logger.debug("_get_cookies loading from Redis | source_key=%s", self.source_key)
        r = get_cache_redis()
        # source_key is a SourceKey enum — .value gives the raw string ("nhentai")
        # that matches the key format used by the iOS app's cookie store
        key = self.source_key.value if hasattr(self.source_key, 'value') else str(self.source_key)
        raw = await r.get(f"{COOKIE_CACHE_KEY_PREFIX}{key}")
        if not raw:
            # Expected for sources that don't require cookies (e.g. nhentai public).
            # Logged at DEBUG only — this appears hundreds of times per job otherwise.
            logger.debug("_get_cookies no cached cookies | source_key=%s (proceeding without)",
                         self.source_key)
            result = ([], "Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X)")
        else:
            try:
                data = json.loads(raw)
                cookies = data.get("cookies", [])
                user_agent = data.get("user_agent", "")
            except (json.JSONDecodeError, TypeError, AttributeError) as e:
                # Corrupted Redis value — degrade to "no cookies" rather than
                # crashing the scrape job. Caller's headless browser fallback
                # will repopulate the cache on the next failed fetch.
                logger.warning("_get_cookies corrupted cache, degrading | source_key=%s error=%s",
                               self.source_key, e)
                cookies, user_agent = [], ""
            logger.info("_get_cookies loaded %d cookies | source_key=%s ua=%s",
                        len(cookies), self.source_key, user_agent[:40] if user_agent else "none")
            result = (cookies, user_agent)
        self._cookie_cache = result
        return result

    async def _fetch_via_browser(self, url: str) -> str | None:
        """
        Fetch page content using headless Chromium. Used as last resort when
        curl_cffi and httpx both get 403. Returns HTML string or None on failure.
        Also caches cookies in Redis for future image downloads.
        """
        from app.utils.playwright_client import acquire_browser

        logger.info("_fetch_via_browser starting | source_key=%s url=%s", self.source_key, url)
        try:
            async with acquire_browser() as browser:
                context = await browser.new_context(
                    user_agent="Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) "
                              "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 "
                              "Mobile/15E148 Safari/604.1",
                    viewport={"width": 390, "height": 844},
                )
                page = await context.new_page()
                await page.goto(url, wait_until="networkidle", timeout=30000)

                # Wait for Cloudflare challenge if present
                title = await page.title()
                if "just a moment" in title.lower():
                    logger.info("_fetch_via_browser waiting for Cloudflare challenge | url=%s", url)
                    await asyncio.sleep(8)
                    await page.wait_for_load_state("networkidle", timeout=15000)

                html = await page.content()

                # Cache cookies for image downloads
                browser_cookies = await context.cookies()
                await context.close()

                if browser_cookies:
                    cookie_dtos = [
                        {"name": c["name"], "value": c["value"], "domain": c.get("domain", "")}
                        for c in browser_cookies
                    ]
                    cache_data = {
                        "cookies": cookie_dtos,
                        "user_agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) AppleWebKit/605.1.15",
                    }
                    r = get_cache_redis()
                    await r.set(
                        f"{COOKIE_CACHE_KEY_PREFIX}{self.source_key.value if hasattr(self.source_key, 'value') else self.source_key}",
                        json.dumps(cache_data),
                        ex=settings.cookie_cache_ttl_secs,
                    )
                    self._cookie_cache = None

                logger.info("_fetch_via_browser success | url=%s bytes=%d cookies=%d",
                            url, len(html), len(browser_cookies))
                return html

        except Exception as e:
            logger.error("_fetch_via_browser failed | url=%s error=%s", url, e)
            return None

    async def _refresh_cookies_via_browser(self, url: str) -> bool:
        """
        Launch headless Chromium, navigate to the site, wait for Cloudflare
        challenge to resolve, extract cookies, and store them in Redis.
        Returns True if cookies were obtained, False otherwise.
        """
        from app.utils.playwright_client import acquire_browser

        # Derive the site root from the URL for the initial navigation
        from urllib.parse import urlparse
        parsed = urlparse(url)
        site_root = f"{parsed.scheme}://{parsed.netloc}/"

        logger.info("_refresh_cookies_via_browser starting | source_key=%s url=%s", self.source_key, site_root)
        try:
            async with acquire_browser() as browser:
                context = await browser.new_context(
                    user_agent="Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) "
                              "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 "
                              "Mobile/15E148 Safari/604.1",
                    viewport={"width": 390, "height": 844},
                )
                page = await context.new_page()

                # Navigate and wait for Cloudflare challenge to resolve
                await page.goto(site_root, wait_until="networkidle", timeout=30000)

                # Some Cloudflare challenges need a few seconds after networkidle
                await asyncio.sleep(3)

                # Check if we actually got past the challenge
                title = await page.title()
                if "just a moment" in title.lower() or "attention required" in title.lower():
                    # Still on challenge page — wait longer
                    logger.warning("_refresh_cookies_via_browser still on challenge page, waiting 10s | title=%s", title)
                    await asyncio.sleep(10)

                # Extract all cookies
                browser_cookies = await context.cookies()
                await context.close()

                if not browser_cookies:
                    logger.warning("_refresh_cookies_via_browser no cookies obtained | source_key=%s", self.source_key)
                    return False

                # Store in Redis with the same format as iOS cookie store
                cookie_dtos = [
                    {"name": c["name"], "value": c["value"], "domain": c.get("domain", "")}
                    for c in browser_cookies
                ]
                cache_data = {
                    "cookies": cookie_dtos,
                    "user_agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) AppleWebKit/605.1.15",
                }
                r = get_cache_redis()
                await r.set(
                    f"{COOKIE_CACHE_KEY_PREFIX}{self.source_key.value if hasattr(self.source_key, 'value') else self.source_key}",
                    json.dumps(cache_data),
                    ex=settings.cookie_cache_ttl_secs,
                )

                # Invalidate in-process cache so next _get_cookies reads fresh from Redis
                self._cookie_cache = None

                logger.info(
                    "_refresh_cookies_via_browser success | source_key=%s cookies=%d",
                    self.source_key, len(cookie_dtos),
                )
                return True

        except Exception as e:
            logger.error("_refresh_cookies_via_browser failed | source_key=%s error=%s", self.source_key, e)
            return False

    async def _fetch(self, url: str) -> str:
        """
        Rate-limited fetch with retry + exponential backoff using curl_cffi for TLS
        impersonation.

        On 403: retries up to max_retries. If all fail with 403 and browser cookies
        haven't been tried yet, launches headless Chromium to solve Cloudflare challenge,
        caches the cookies, and retries once more.
        """
        cookies_list, user_agent = await self._get_cookies()
        cookies = {c["name"]: c["value"] for c in cookies_list}

        logger.debug("_fetch starting | url=%s delay=%.1fs cookies=%d",
                     url, self.request_delay_seconds, len(cookies))
        await asyncio.sleep(self.request_delay_seconds)

        consecutive_403 = 0

        for attempt in range(self.max_retries):
            logger.debug("_fetch attempt %d/%d | url=%s", attempt + 1, self.max_retries, url)
            try:
                async with CurlSession(impersonate=_CF_IMPERSONATE) as session:
                    headers = {}
                    if user_agent:
                        headers["User-Agent"] = user_agent
                    response = await session.get(
                        url,
                        cookies=cookies,
                        headers=headers,
                        timeout=60,
                    )

                if response.status_code == 200:
                    logger.debug("_fetch ok | url=%s bytes=%d attempt=%d",
                                 url, len(response.content), attempt + 1)
                    return response.text
                elif response.status_code == 403:
                    consecutive_403 += 1
                    self._cookie_cache = None

                    # On 2nd 403: fetch the page directly via headless browser
                    if consecutive_403 >= 2 and not self._browser_cookie_attempted:
                        self._browser_cookie_attempted = True
                        logger.info("_fetch 403 x%d — fetching via headless browser | url=%s",
                                    consecutive_403, url)
                        html = await self._fetch_via_browser(url)
                        if html and len(html) > 500:
                            return html

                    if consecutive_403 >= self.max_retries:
                        logger.error("_fetch 403 blocked | url=%s — all retries exhausted", url)
                        raise CookieExpiredError(
                            f"403 from {url} — Cloudflare blocked even after headless browser attempt. "
                            "Open the site in the iOS browser to refresh cookies, then retry."
                        )

                    wait = (2 ** attempt) + random.uniform(0, 1)
                    logger.warning("_fetch 403, retrying | url=%s attempt=%d/%d wait=%.1fs",
                                   url, attempt + 1, self.max_retries, wait)
                    await asyncio.sleep(wait)

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
