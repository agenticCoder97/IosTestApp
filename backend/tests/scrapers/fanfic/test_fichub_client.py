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


async def test_fetch_story_meta_raises_on_err_minus_one(monkeypatch):
    payload = json.loads((FIXTURES / "fichub_meta_err.json").read_text())

    def handler(_req):
        return httpx.Response(200, json=payload)

    monkeypatch.setattr(_fichub, "_build_client", lambda: _mock_client(handler))

    with pytest.raises(_fichub.FicHubError, match="unable to find fic"):
        await _fichub.fetch_story_meta("https://www.fanfiction.net/s/9999999/1/Bogus")


async def test_fetch_story_meta_retries_once_on_5xx(monkeypatch):
    payload = json.loads((FIXTURES / "fichub_meta_success.json").read_text())
    calls = {"n": 0}

    def handler(_req):
        calls["n"] += 1
        if calls["n"] == 1:
            return httpx.Response(502, text="bad gateway")
        return httpx.Response(200, json=payload)

    monkeypatch.setattr(_fichub, "_build_client", lambda: _mock_client(handler))

    meta = await _fichub.fetch_story_meta("https://www.fanfiction.net/s/13262338")
    assert calls["n"] == 2
    assert meta.title == "Sample Story"


async def test_fetch_story_meta_raises_on_repeated_5xx(monkeypatch):
    def handler(_req):
        return httpx.Response(503, text="service unavailable")

    monkeypatch.setattr(_fichub, "_build_client", lambda: _mock_client(handler))

    with pytest.raises(_fichub.FicHubError, match="HTTP 503"):
        await _fichub.fetch_story_meta("https://www.fanfiction.net/s/13262338")


async def test_fetch_story_meta_wraps_timeout_as_fichuberror(monkeypatch):
    def handler(_req):
        raise httpx.TimeoutException("timed out")

    monkeypatch.setattr(_fichub, "_build_client", lambda: _mock_client(handler))

    with pytest.raises(_fichub.FicHubError, match="timed out|timeout"):
        await _fichub.fetch_story_meta("https://www.fanfiction.net/s/13262338")
