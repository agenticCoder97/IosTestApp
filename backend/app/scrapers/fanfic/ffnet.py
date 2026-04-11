import asyncio
import logging
import re
import httpx
from bs4 import BeautifulSoup
from app.scrapers.base import BaseScraper, StoryMetadata, ChapterInfo, PageInfo, ScraperError
from app.core.constants import SourceKey

logger = logging.getLogger(__name__)


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

    async def _fetch(self, url: str) -> str:
        """Override: use httpx instead of curl_cffi for FFNet.
        On 2nd 403, falls back to headless browser cookie refresh."""
        cookies_list, user_agent = await self._get_cookies()
        cookies = {c["name"]: c["value"] for c in cookies_list}

        await asyncio.sleep(self.request_delay_seconds)

        headers = {
            "User-Agent": user_agent or "Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Mobile/15E148 Safari/604.1",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.9",
            "Accept-Encoding": "gzip, deflate, br",
            "Sec-Fetch-Dest": "document",
            "Sec-Fetch-Mode": "navigate",
            "Sec-Fetch-Site": "none",
        }
        consecutive_403 = 0
        for attempt in range(self.max_retries):
            try:
                async with httpx.AsyncClient(
                    follow_redirects=True, timeout=60, http2=True, headers=headers,
                ) as client:
                    response = await client.get(url, cookies=cookies)
                if response.status_code == 200:
                    logger.debug("_fetch(httpx) ok | url=%s bytes=%d", url, len(response.content))
                    return response.text
                elif response.status_code == 403:
                    consecutive_403 += 1
                    if consecutive_403 >= 2 and not self._browser_cookie_attempted:
                        self._browser_cookie_attempted = True
                        logger.info("_fetch(httpx) 403 x%d — fetching via headless browser | url=%s", consecutive_403, url)
                        html = await self._fetch_via_browser(url)
                        if html and len(html) > 500:
                            return html
                    if consecutive_403 >= self.max_retries:
                        from app.scrapers.base import CookieExpiredError
                        raise CookieExpiredError(f"403 from {url} — FFNet blocked even after browser attempt.")
                    await asyncio.sleep((2 ** attempt) + 0.5)
                else:
                    raise ScraperError(f"HTTP {response.status_code} from {url}")
            except (ScraperError, CookieExpiredError):
                raise
            except Exception as e:
                if attempt == self.max_retries - 1:
                    raise ScraperError(f"FFNet fetch failed after {self.max_retries} attempts: {e}") from e
                await asyncio.sleep((2 ** attempt) + 0.5)
        raise ScraperError(f"FFNet fetch failed: max retries exhausted for {url}")

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

        # Parse the metadata line (pipe-separated by " - "):
        # "Rated: Fiction M - English - Adventure/Romance - Harry P., Fleur D.
        #   - Chapters: 24 - Words: 234,571 - Reviews: 5,157 - Favs: 15,287
        #   - Follows: 7,375 - Updated: May 28, 2009 - Published: Feb 9, 2007
        #   - Status: Complete - id: 3384712"
        rating = None
        language = None
        word_count = None
        characters = None
        fandom = None
        tags = []
        completion_status = "ongoing"
        published_at = None
        updated_at_source = None
        hits = None       # FFNet doesn't expose views/hits
        kudos = None      # mapped from Favs
        comments_count = None  # mapped from Reviews
        bookmarks_count = None  # mapped from Follows

        # Fandom from breadcrumb — last link for normal, first for crossovers
        breadcrumb_links = soup.select("#pre_story_links a")
        if breadcrumb_links:
            fandom = breadcrumb_links[-1].get_text(strip=True)

        # Metadata span — last xgray span in #profile_top
        meta_spans = soup.select("#profile_top span.xgray")
        meta_text = meta_spans[-1].get_text() if meta_spans else ""
        if not meta_text:
            profile = soup.select_one("#profile_top")
            meta_text = profile.get_text() if profile else ""

        # Rating: "Fiction T", "Fiction M", "Fiction K+", etc.
        m = re.search(r"Rated:\s*(?:Fiction\s+)?([TKMA][+]?)", meta_text)
        if m:
            rating = m.group(1)

        # Split the metadata line on " - " to parse structured fields
        # Format: Rated - Language - Genre - [Characters] - Chapters: N - Words: N - ...
        segments = [s.strip() for s in meta_text.split(" - ")]

        # Language is the first plain-word segment after "Rated:"
        for seg in segments:
            if re.match(r"^[A-Z][a-z]+$", seg) and seg not in ("Complete",):
                language = seg
                break

        # Genre: segment containing "/" or known genre words, after language
        genre_words = {"Adventure", "Romance", "Drama", "Humor", "Angst", "Hurt",
                       "Comfort", "Tragedy", "Mystery", "Horror", "Fantasy", "Sci-Fi",
                       "Supernatural", "Suspense", "Crime", "Family", "Friendship",
                       "Poetry", "Spiritual", "Parody", "Western", "General"}
        compound_genres = {"Hurt/Comfort"}  # single genre name containing "/"
        for seg in segments:
            if seg in compound_genres:
                tags.append({"name": seg, "tag_type": "genre"})
                break
            parts = [p.strip() for p in seg.split("/")]
            if all(p in genre_words for p in parts) and parts:
                for g in parts:
                    tags.append({"name": g, "tag_type": "genre"})
                break

        # Characters: between genre and "Chapters:" — may have [brackets] or not
        # Extract from the segment(s) that contain names but not key:value pairs
        char_parts = []
        for seg in segments:
            # Skip key:value segments and known non-character segments
            if re.match(r"^(Rated|Words|Chapters|Reviews|Favs|Follows|Updated|Published|Status|id):", seg):
                continue
            if seg == language or seg in genre_words or "/" in seg and all(p.strip() in genre_words for p in seg.split("/")):
                continue
            # Character segments contain names like "Harry P." or "[Harry P., Ginny W.]"
            cleaned = re.sub(r"[\[\]]", "", seg).strip()
            if cleaned and re.search(r"[A-Z][a-z]", cleaned) and not re.match(r"^(Rated|Fiction)", cleaned):
                # Avoid picking up the description or title
                if len(cleaned) < 200 and "," in cleaned or "." in cleaned:
                    char_parts.append(cleaned)
        if char_parts:
            characters = ", ".join(char_parts)

        # Structured key:value fields
        for seg in segments:
            km = re.match(r"^(\w+):\s*(.+)$", seg)
            if not km:
                continue
            key, val = km.group(1), km.group(2).strip()
            if key == "Words":
                try:
                    word_count = int(val.replace(",", ""))
                except ValueError:
                    pass
            elif key == "Reviews":
                try:
                    comments_count = int(val.replace(",", ""))
                except ValueError:
                    pass
            elif key == "Favs":
                try:
                    kudos = int(val.replace(",", ""))
                except ValueError:
                    pass
            elif key == "Follows":
                try:
                    bookmarks_count = int(val.replace(",", ""))
                except ValueError:
                    pass

        # Dates from <span data-xutime> (Unix epoch — reliable, no format ambiguity)
        from datetime import datetime as _dt, timezone as _tz
        meta_span_el = meta_spans[-1] if meta_spans else None
        if meta_span_el:
            date_spans = meta_span_el.select("span[data-xutime]")
            # FFNet puts Updated first, Published second
            if len(date_spans) >= 2:
                try:
                    ts = int(date_spans[0]["data-xutime"])
                    updated_at_source = _dt.fromtimestamp(ts, tz=_tz.utc).strftime("%Y-%m-%d")
                except (ValueError, KeyError):
                    pass
                try:
                    ts = int(date_spans[1]["data-xutime"])
                    published_at = _dt.fromtimestamp(ts, tz=_tz.utc).strftime("%Y-%m-%d")
                except (ValueError, KeyError):
                    pass
            elif len(date_spans) == 1:
                try:
                    ts = int(date_spans[0]["data-xutime"])
                    published_at = _dt.fromtimestamp(ts, tz=_tz.utc).strftime("%Y-%m-%d")
                except (ValueError, KeyError):
                    pass

        # Completion
        if "Status: Complete" in meta_text:
            completion_status = "complete"

        # Build freeform_tags from extracted genres so they display on iOS
        freeform_tags = ", ".join(t["name"] for t in tags) if tags else None

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
            freeform_tags=freeform_tags,
            kudos=kudos,
            comments_count=comments_count,
            bookmarks_count=bookmarks_count,
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

        paragraphs = [p.get_text(separator=" ", strip=True) for p in content_div.find_all("p")]
        return "\n\n".join(p for p in paragraphs if p)
