"""Async wrapper around FanFicFare's synchronous Python API.

FanFicFare ships a Calibre plugin that also exposes a Python API:
    from fanficfare import adapters
    from fanficfare.configurable import Configuration

    config = Configuration(['fanfiction.net'], 'EPUB')
    adapter = adapters.getAdapter(config, url)
    adapter.getStoryMetadataOnly()
    chapters = adapter.story.getChapters()       # list of [url, title, html]
    text = adapter.getChapterText(chapter_url)

We wrap the blocking calls in `asyncio.to_thread` so they don't block the
event loop, and bridge our cookie-store cookies into FFF's underlying
requests session.
"""
from __future__ import annotations

import asyncio
import http.cookiejar
import logging
from typing import Any

from app.scrapers.base import StoryMetadata
from app.scrapers.fanfic._fichub import ChapterText

logger = logging.getLogger(__name__)


class FanFicFareError(Exception):
    """Wraps any error from the FanFicFare library."""


def _build_cookie_jar(cookies: list[dict]) -> http.cookiejar.CookieJar:
    """Convert our cookie-store dicts into a CookieJar for FFF's session."""
    jar = http.cookiejar.CookieJar()
    for c in cookies:
        cookie = http.cookiejar.Cookie(
            version=0,
            name=c["name"],
            value=c["value"],
            port=None,
            port_specified=False,
            domain=c.get("domain", ""),
            domain_specified=bool(c.get("domain")),
            domain_initial_dot=c.get("domain", "").startswith("."),
            path=c.get("path", "/"),
            path_specified=True,
            secure=c.get("secure", False),
            expires=None,
            discard=False,
            comment=None,
            comment_url=None,
            rest={},
        )
        jar.set_cookie(cookie)
    return jar


def _get_adapter(url: str, cookies: list[dict], user_agent: str) -> Any:
    """Build a FanFicFare adapter with cookies + UA wired into its session.

    Pulled out as a top-level function so tests can monkeypatch it cleanly.
    """
    from fanficfare import adapters
    from fanficfare.configurable import Configuration

    config = Configuration(["fanfiction.net"], "EPUB")
    if user_agent:
        try:
            config.set("defaults", "user_agent", user_agent)
        except Exception:
            # FFF Configuration sometimes rejects sections that don't exist;
            # fall back silently — UA is best-effort.
            logger.debug("Could not set user_agent in FFF configuration", exc_info=True)

    adapter = adapters.getAdapter(config, url)
    if cookies:
        # FFF stores its requests session on the adapter; wire cookies in directly.
        try:
            adapter.opener.session.cookies = _build_cookie_jar(cookies)
        except AttributeError:
            logger.warning("Could not inject cookies into FFF adapter — session not found")
    return adapter


def _to_story_metadata(adapter: Any, source_url: str) -> StoryMetadata:
    """Map FFF Story metadata fields into our StoryMetadata dataclass."""
    g = adapter.story.getMetadata
    status_raw = (g("status") or "").lower()
    completion = "complete" if status_raw == "complete" else "ongoing"

    return StoryMetadata(
        title=g("title") or "",
        source_url=source_url,
        source_key="ffnet",
        source_id=g("storyId") or None,
        description=g("description") or None,
        language=g("language") or None,
        authors=[g("author")] if g("author") else [],
        total_chapters=int(g("numChapters", 0) or 0),
        fandom=g("category") or None,
        rating=g("rating") or None,
        word_count=int(g("numWords", 0) or 0),
        completion_status=completion,
    )


def _fetch_sync(url: str, cookies: list[dict], user_agent: str
               ) -> tuple[StoryMetadata, list[ChapterText]]:
    """Blocking implementation — invoked inside asyncio.to_thread."""
    adapter = _get_adapter(url, cookies, user_agent)
    adapter.getStoryMetadataOnly()
    meta = _to_story_metadata(adapter, url)

    chapter_texts: list[ChapterText] = []
    for i, record in enumerate(adapter.story.getChapters(), start=1):
        chap_url, chap_title = record[0], record[1]
        html = adapter.getChapterText(chap_url) or ""
        chapter_texts.append(ChapterText(number=i, title=chap_title or f"Chapter {i}", html=html))

    return meta, chapter_texts


async def fetch_via_fanficfare(url: str, cookies: list[dict], user_agent: str
                              ) -> tuple[StoryMetadata, list[ChapterText]]:
    """Public async surface. Wraps blocking FFF calls in asyncio.to_thread.
    Any exception from FFF is wrapped in FanFicFareError.
    """
    try:
        return await asyncio.to_thread(_fetch_sync, url, cookies, user_agent)
    except FanFicFareError:
        raise
    except Exception as e:
        raise FanFicFareError(str(e)) from e
