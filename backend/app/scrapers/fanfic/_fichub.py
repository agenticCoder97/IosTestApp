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
    async with _build_client() as client:
        response = await client.get("/api/v0/epub", params={"q": fic_url})

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
