"""Tests for the FanFicFare async wrapper. FFF's sync API is mocked at the
runner's `_get_adapter` boundary so we exercise our wrapper code only.
"""
from unittest.mock import MagicMock

import pytest

from app.scrapers.fanfic import _fanficfare_runner
from app.scrapers.fanfic._fichub import ChapterText
from app.scrapers.base import StoryMetadata


def _fake_adapter(metadata: dict, chapter_texts: list[tuple[str, str]]):
    """Build a MagicMock that quacks like a FFF Adapter for our wrapper."""
    adapter = MagicMock()
    adapter.story.getMetadata.side_effect = lambda key, default=None: metadata.get(key, default)
    chapter_records = [[f"https://www.fanfiction.net/s/123/{i+1}", title, ""]
                       for i, (title, _html) in enumerate(chapter_texts)]
    adapter.story.getChapters.return_value = chapter_records
    text_by_url = {f"https://www.fanfiction.net/s/123/{i+1}": html
                   for i, (_title, html) in enumerate(chapter_texts)}
    adapter.getChapterText.side_effect = lambda url: text_by_url[url]
    return adapter


async def test_fetch_via_fanficfare_returns_metadata_and_chapters(monkeypatch):
    fake = _fake_adapter(
        metadata={
            "title": "My Story",
            "author": "Alice",
            "numChapters": 2,
            "status": "Complete",
            "numWords": 1200,
            "description": "Short description.",
            "language": "English",
            "category": "Test Fandom",
        },
        chapter_texts=[("Ch 1", "<p>One.</p>"), ("Ch 2", "<p>Two.</p>")],
    )
    monkeypatch.setattr(_fanficfare_runner, "_get_adapter", lambda url, cookies, ua: fake)

    meta, chapters = await _fanficfare_runner.fetch_via_fanficfare(
        "https://www.fanfiction.net/s/123",
        cookies=[],
        user_agent="iOS-WKWebView/1.0",
    )

    assert isinstance(meta, StoryMetadata)
    assert meta.title == "My Story"
    assert meta.authors == ["Alice"]
    assert meta.total_chapters == 2
    assert meta.completion_status == "complete"
    assert meta.word_count == 1200
    assert meta.fandom == "Test Fandom"

    assert len(chapters) == 2
    assert isinstance(chapters[0], ChapterText)
    assert chapters[0].number == 1
    assert chapters[0].title == "Ch 1"
    assert "One." in chapters[0].html


async def test_fetch_via_fanficfare_passes_cookies_into_session(monkeypatch):
    """Cookies passed in must be forwarded to _get_adapter so they reach FFF."""
    captured = {}

    def fake_get_adapter(url, cookies, ua):
        captured["cookies"] = cookies
        captured["ua"] = ua
        return _fake_adapter(metadata={"title": "X", "author": "Y", "numChapters": 1,
                                       "status": "In-Progress", "numWords": 10,
                                       "description": "", "language": "English"},
                             chapter_texts=[("c1", "<p>x</p>")])

    monkeypatch.setattr(_fanficfare_runner, "_get_adapter", fake_get_adapter)

    cookies = [{"name": "cf_clearance", "value": "abc", "domain": ".fanfiction.net"}]
    await _fanficfare_runner.fetch_via_fanficfare(
        "https://www.fanfiction.net/s/123", cookies=cookies, user_agent="iOS/1",
    )

    assert captured["cookies"] == cookies
    assert captured["ua"] == "iOS/1"


async def test_fetch_via_fanficfare_wraps_library_errors(monkeypatch):
    """Any exception raised by FFF must be wrapped in FanFicFareError."""
    def explode(url, cookies, ua):
        raise RuntimeError("FFF blew up")

    monkeypatch.setattr(_fanficfare_runner, "_get_adapter", explode)

    with pytest.raises(_fanficfare_runner.FanFicFareError, match="FFF blew up"):
        await _fanficfare_runner.fetch_via_fanficfare(
            "https://www.fanfiction.net/s/123", cookies=[], user_agent="iOS/1",
        )
