"""Tests for the FicHub client wrapper used as fanfic-scraper fallback."""
import json
from pathlib import Path

import httpx
import pytest

from app.scrapers.fanfic import _fichub

FIXTURES = Path(__file__).parent / "fixtures"


def _mock_client(handler) -> httpx.AsyncClient:
    return httpx.AsyncClient(
        transport=httpx.MockTransport(handler),
        base_url="https://fichub.net",
        timeout=5.0,
    )


async def test_fetch_story_meta_success(monkeypatch):
    payload = json.loads((FIXTURES / "fichub_meta_success.json").read_text())

    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/api/v0/epub"
        assert request.url.params["q"] == "https://www.fanfiction.net/s/13262338"
        return httpx.Response(200, json=payload)

    monkeypatch.setattr(_fichub, "_build_client", lambda: _mock_client(handler))

    meta = await _fichub.fetch_story_meta("https://www.fanfiction.net/s/13262338")

    assert meta.title == "Sample Story"
    assert meta.author == "Test Author"
    assert meta.chapters == 5
    assert meta.status == "complete"
    assert meta.word_count == 12500
    assert meta.summary == "A short test summary."
    assert meta.fandoms == ["Test Fandom"]
    assert meta.epub_url == "/epub/abc123XYZ/Sample-Story.epub"
    assert meta.url_id == "abc123XYZ"
