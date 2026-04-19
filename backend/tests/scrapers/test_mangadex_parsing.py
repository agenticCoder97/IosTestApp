"""
Fixture-based tests for MangadexScraper. No network — all _http calls are
monkeypatched to return saved JSON.
"""
import json
from pathlib import Path

import pytest

from app.scrapers.comic.mangadex import MangadexScraper

FIXTURES = Path(__file__).parent / "fixtures" / "mangadex"


def _load(name: str) -> dict:
    return json.loads((FIXTURES / name).read_text())


@pytest.fixture
def scraper(monkeypatch):
    s = MangadexScraper()

    async def fake_get(url, *, params=None, at_home=False):
        if "/manga/" in url and "/feed" not in url and "/at-home" not in url:
            return _load("manga_detail.json")
        raise AssertionError(f"unexpected URL in test: {url}")

    monkeypatch.setattr(s._http, "get_json", fake_get)
    return s


async def test_get_story_metadata_extracts_title_and_lang(scraper):
    meta = await scraper.get_story_metadata(
        "https://mangadex.org/title/32d76d19-8a05-4db0-9fc2-e0b0648fe9d0"
    )
    assert meta.title == "Solo Leveling"
    assert meta.language == "ko"
    assert meta.source_id == "32d76d19-8a05-4db0-9fc2-e0b0648fe9d0"
    assert meta.source_key == "mangadex"


async def test_get_story_metadata_extracts_authors_and_tags(scraper):
    meta = await scraper.get_story_metadata(
        "https://mangadex.org/title/32d76d19-8a05-4db0-9fc2-e0b0648fe9d0"
    )
    assert "Chugong" in meta.authors
    tag_names = {t["name"] for t in meta.tags}
    assert "Action" in tag_names
    assert "Adventure" in tag_names


async def test_get_story_metadata_builds_thumbnail_url(scraper):
    meta = await scraper.get_story_metadata(
        "https://mangadex.org/title/32d76d19-8a05-4db0-9fc2-e0b0648fe9d0"
    )
    assert meta.thumbnail_url == (
        "https://uploads.mangadex.org/covers/"
        "32d76d19-8a05-4db0-9fc2-e0b0648fe9d0/cover123.jpg.512.jpg"
    )


async def test_get_story_metadata_rejects_unparseable_url(scraper):
    with pytest.raises(ValueError):
        await scraper.get_story_metadata("https://mangadex.org/")
