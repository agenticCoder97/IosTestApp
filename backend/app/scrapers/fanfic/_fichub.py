"""FicHub REST client — fallback fanfic source.

FicHub (https://fichub.net) is a community archive that maintains EPUBs of
public fanfiction. We use it as a tier-2 fallback when the primary scraper
(FanFicFare for FFNet, ao3_api for AO3) fails on a hard error like Cloudflare
or a parser regression.

Public API surface:
- `fetch_story_meta(url)` -> FicHubMeta (raises FicHubError on err:-1, 5xx, timeout)
- `download_and_split_epub(epub_url)` -> list[ChapterText] (parses EPUB, drops
  cover and nav, returns chapters in spine order)

No cookies, no auth; FicHub is fully anonymous.
"""
from __future__ import annotations

import logging
from dataclasses import dataclass

import httpx

from app.scrapers.fanfic._html_to_text import html_to_paragraphs

logger = logging.getLogger(__name__)

_BASE_URL = "https://fichub.net"
_TIMEOUT_SECONDS = 30.0


class FicHubError(Exception):
    """Raised when FicHub returns err:-1, repeated 5xx, or times out."""


@dataclass
class FicHubMeta:
    title: str
    author: str
    chapters: int
    status: str          # "complete" | "ongoing"
    word_count: int
    summary: str
    fandoms: list[str]
    epub_url: str        # relative — join with https://fichub.net
    url_id: str          # cache key — bumps when new chapters land


@dataclass
class ChapterText:
    number: int          # 1-based
    title: str
    html: str            # raw chapter HTML


def _build_client() -> httpx.AsyncClient:
    """Factory for the httpx client. Overridable in tests via monkeypatch."""
    return httpx.AsyncClient(base_url=_BASE_URL, timeout=_TIMEOUT_SECONDS)


async def fetch_story_meta(fic_url: str) -> FicHubMeta:
    """Resolve a fanfic URL through FicHub. Raises FicHubError on failure."""
    response: httpx.Response | None = None
    try:
        async with _build_client() as client:
            for attempt in range(2):  # original + one 5xx retry
                response = await client.get("/api/v0/epub", params={"q": fic_url})
                if 500 <= response.status_code < 600 and attempt == 0:
                    logger.warning("FicHub 5xx (%d), retrying once | url=%s", response.status_code, fic_url)
                    continue
                break
    except httpx.TimeoutException as e:
        raise FicHubError(f"FicHub timed out for {fic_url}") from e
    except httpx.HTTPError as e:
        raise FicHubError(f"FicHub network error for {fic_url}: {e}") from e

    assert response is not None  # loop always executes at least once
    if response.status_code != 200:
        raise FicHubError(f"FicHub HTTP {response.status_code} for {fic_url}")

    body = response.json()
    if body.get("err", 0) != 0:
        raise FicHubError(f"FicHub err {body.get('err')} for {fic_url}: {body.get('msg', 'unknown')}")

    meta = body.get("meta") or {}
    fandoms = (meta.get("rawExtendedMeta") or {}).get("fandoms") or []

    return FicHubMeta(
        title=meta.get("title", ""),
        author=meta.get("author", ""),
        chapters=int(meta.get("chapters", 0)),
        status=meta.get("status", "ongoing"),
        word_count=int(meta.get("words", 0)),
        summary=meta.get("description", ""),
        fandoms=list(fandoms),
        epub_url=body.get("epub_url", ""),
        url_id=body.get("urlId", ""),
    )


async def download_and_split_epub(epub_url: str) -> list[ChapterText]:
    """Download an EPUB from FicHub, parse with ebooklib, return chapters in
    spine order. Strips cover.xhtml, nav.xhtml, and any item flagged as the
    EPUB nav or cover document.
    """
    try:
        async with _build_client() as client:
            response = await client.get(epub_url)
    except httpx.HTTPError as e:
        raise FicHubError(f"EPUB download failed for {epub_url}: {e}") from e

    if response.status_code != 200:
        raise FicHubError(f"EPUB download HTTP {response.status_code} for {epub_url}")

    return _split_epub_bytes(response.content)


def _split_epub_bytes(epub_bytes: bytes) -> list[ChapterText]:
    """Synchronous EPUB → list[ChapterText]. Pulled out for unit testability.

    `ebooklib.epub.read_epub` only accepts a filesystem path, so we round-trip
    through a NamedTemporaryFile rather than a BytesIO.
    """
    import tempfile
    from ebooklib import epub, ITEM_DOCUMENT

    with tempfile.NamedTemporaryFile(suffix=".epub", delete=True) as tf:
        tf.write(epub_bytes)
        tf.flush()
        book = epub.read_epub(tf.name)

    chapters: list[ChapterText] = []
    chapter_num = 0
    for item in book.get_items_of_type(ITEM_DOCUMENT):
        name = (item.get_name() or "").lower()
        if "nav" in name or "cover" in name or "title" in name:
            continue
        chapter_num += 1
        html = html_to_paragraphs(item.get_content().decode("utf-8", errors="replace"))
        title = item.title or f"Chapter {chapter_num}"
        chapters.append(ChapterText(number=chapter_num, title=title, html=html))

    return chapters
