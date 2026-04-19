"""
Unit tests for the MangaDex matcher's scoring + decision logic.
"""
import pytest

from app.scrapers.base import StoryMetadata
from app.services.mangadex_matcher import (
    _normalize,
    _score,
    find_mangadex_match,
)


def test_normalize_strips_diacritics_and_volume_markers():
    assert _normalize("Solo Leveling Vol. 1 Chapter 5") == "solo leveling"
    assert _normalize("Café Naïve!") == "cafe naive"
    assert _normalize("") == ""


def test_score_strong_match_passes_threshold():
    candidate = {
        "id": "x",
        "title": "Solo Leveling",
        "original_language": "ko",
        "last_chapter": 179,
        "tags": ["Action", "Adventure"],
    }
    s = _score(
        candidate,
        source_title="Solo Leveling",
        expected_lang="ko",
        source_tags={"Action", "Adventure"},
        source_chapter_count=180,
    )
    assert s >= 0.85


def test_score_title_alone_below_threshold():
    candidate = {
        "id": "x",
        "title": "Solo Leveling",
        "original_language": "en",       # wrong lang
        "last_chapter": 0,                # no chapter info
        "tags": [],
    }
    s = _score(
        candidate,
        source_title="Solo Leveling",
        expected_lang="ko",
        source_tags=set(),
        source_chapter_count=0,
    )
    # Title sim = 1.0, weight 0.55 → at most 0.55. Below threshold.
    assert s < 0.85


def test_score_chapter_delta_outside_20pct_loses_chapter_signal():
    candidate = {
        "id": "x",
        "title": "Different Title",
        "original_language": "ko",
        "last_chapter": 100,
        "tags": [],
    }
    s = _score(
        candidate,
        source_title="Different Title",
        expected_lang="ko",
        source_tags=set(),
        source_chapter_count=200,  # 100/200 → 50% delta → no chapter signal
    )
    # title 0.55 + lang 0.15 + tags 0 + chapter 0 → 0.70
    assert 0.69 < s < 0.71


@pytest.fixture
def patch_settings(monkeypatch):
    from app.core.config import settings
    monkeypatch.setattr(settings, "mangadex_disabled", False)
    monkeypatch.setattr(settings, "mangadex_auto_switch_source", True)
    monkeypatch.setattr(settings, "mangadex_title_match_threshold", 0.85)


@pytest.fixture
def patch_search(monkeypatch):
    """Replace MangadexScraper.search with a fake that returns canned candidates."""
    canned: list[dict] = []
    async def fake_search(self, *, title, content_ratings, limit=10):
        return canned
    from app.scrapers.comic.mangadex import MangadexScraper
    monkeypatch.setattr(MangadexScraper, "search", fake_search)
    return canned


@pytest.fixture
def patch_source_scraper(monkeypatch):
    """Replace the toongod scraper's get_story_metadata with a stub."""
    async def fake_meta(self, url):
        return StoryMetadata(
            title="Solo Leveling",
            source_url=url,
            source_key="toongod",
            tags=[{"name": "Action", "tag_type": "genre"}],
            total_chapters=180,
        )
    from app.scrapers.comic.toongod import ToongodScraper
    monkeypatch.setattr(ToongodScraper, "get_story_metadata", fake_meta)


async def test_find_match_returns_match_when_threshold_met(
    patch_settings, patch_search, patch_source_scraper,
):
    patch_search.append({
        "id": "abc",
        "title": "Solo Leveling",
        "original_language": "ko",
        "last_chapter": 179,
        "tags": ["Action", "Adventure"],
        "thumbnail_url": "https://uploads.mangadex.org/covers/abc/c.jpg.512.jpg",
    })
    match = await find_mangadex_match(
        source="toongod",
        source_url="https://toongod.org/manga/x/",
        source_title="Solo Leveling",
    )
    assert match is not None
    assert match.manga_id == "abc"
    assert match.confidence >= 0.85
    assert match.mangadex_url == "https://mangadex.org/title/abc"


async def test_find_match_returns_none_below_threshold(
    patch_settings, patch_search, patch_source_scraper,
):
    patch_search.append({
        "id": "abc",
        "title": "Completely Different Series",
        "original_language": "en",
        "last_chapter": 5,
        "tags": [],
        "thumbnail_url": None,
    })
    match = await find_mangadex_match(
        source="toongod",
        source_url="https://toongod.org/manga/x/",
        source_title="Solo Leveling",
    )
    assert match is None


async def test_find_match_skipped_when_kill_switch_on(monkeypatch, patch_search):
    from app.core.config import settings
    monkeypatch.setattr(settings, "mangadex_disabled", True)
    match = await find_mangadex_match(
        source="toongod",
        source_url="https://toongod.org/manga/x/",
        source_title="Anything",
    )
    assert match is None


async def test_find_match_skipped_for_ineligible_source(patch_settings, patch_search):
    match = await find_mangadex_match(
        source="nhentai",
        source_url="https://nhentai.net/g/1",
        source_title="Anything",
    )
    assert match is None
