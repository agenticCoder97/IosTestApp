"""
Unit tests for BaseScraper._fetch logic.

All HTTP calls are mocked — no network needed. Tests verify:
- Successful 200 responses pass through correctly
- 403 raises CookieExpiredError (→ iOS 428)
- 429/503 trigger exponential back-off then succeed
- Max retries exhausted → ScraperError
- Retry-After header is respected on 429
"""

import asyncio
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.scrapers.base import BaseScraper, CookieExpiredError, ScraperError, ChapterInfo, PageInfo, StoryMetadata


# ---------------------------------------------------------------------------
# Concrete subclass for testing (implements abstract methods minimally)
# ---------------------------------------------------------------------------

class _TestScraper(BaseScraper):
    source_key = "nhentai"
    content_type = "comic"
    requires_browser = False
    request_delay_seconds = 0.0  # no sleep in tests
    max_retries = 3

    async def get_story_metadata(self, url): raise NotImplementedError
    async def get_chapter_list(self, story_url): raise NotImplementedError
    async def get_chapter_pages(self, chapter_url): raise NotImplementedError
    async def get_chapter_text(self, chapter_url): raise NotImplementedError


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_response(status_code: int, text: str = "", headers: dict | None = None):
    resp = MagicMock()
    resp.status_code = status_code
    resp.text = text
    resp.headers = headers or {}
    resp.raise_for_status = MagicMock()
    return resp


def _mock_cookies_and_client(response_sequence):
    """
    Returns context managers that:
    1. Patch _get_cookies to return empty cookies / default UA
    2. Patch httpx.AsyncClient to return responses in sequence
    """
    async def _fake_get_cookies(self):
        return [], "Mozilla/5.0"

    call_count = {"n": 0}

    class _FakeAsyncClient:
        def __init__(self, **kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *args):
            pass

        async def get(self, url):
            resp = response_sequence[call_count["n"]]
            call_count["n"] += 1
            return resp

    return (
        patch.object(_TestScraper, "_get_cookies", _fake_get_cookies),
        patch("app.scrapers.base.httpx.AsyncClient", _FakeAsyncClient),
        patch("app.scrapers.base.asyncio.sleep", new_callable=lambda: lambda: AsyncMock()),
    )


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_fetch_success_on_first_attempt():
    scraper = _TestScraper()
    responses = [_make_response(200, text="<html>content</html>")]

    async def _fake_get_cookies(self):
        return [], "Mozilla/5.0"

    class _FakeClient:
        def __init__(self, **kwargs): pass
        async def __aenter__(self): return self
        async def __aexit__(self, *args): pass
        async def get(self, url): return responses[0]

    with patch.object(_TestScraper, "_get_cookies", _fake_get_cookies), \
         patch("app.scrapers.base.httpx.AsyncClient", _FakeClient), \
         patch("app.scrapers.base.asyncio.sleep", new=AsyncMock()):
        result = await scraper._fetch("https://nhentai.net/g/1/")

    assert result == "<html>content</html>"


@pytest.mark.asyncio
async def test_fetch_403_raises_cookie_expired():
    scraper = _TestScraper()

    async def _fake_get_cookies(self):
        return [], "Mozilla/5.0"

    class _FakeClient:
        def __init__(self, **kwargs): pass
        async def __aenter__(self): return self
        async def __aexit__(self, *args): pass
        async def get(self, url): return _make_response(403)

    with patch.object(_TestScraper, "_get_cookies", _fake_get_cookies), \
         patch("app.scrapers.base.httpx.AsyncClient", _FakeClient), \
         patch("app.scrapers.base.asyncio.sleep", new=AsyncMock()):
        with pytest.raises(CookieExpiredError):
            await scraper._fetch("https://nhentai.net/g/1/")


@pytest.mark.asyncio
async def test_fetch_429_then_success():
    """First attempt gets 429, second attempt gets 200 — should succeed."""
    scraper = _TestScraper()
    call_count = {"n": 0}

    async def _fake_get_cookies(self):
        return [], "Mozilla/5.0"

    class _FakeClient:
        def __init__(self, **kwargs): pass
        async def __aenter__(self): return self
        async def __aexit__(self, *args): pass
        async def get(self, url):
            call_count["n"] += 1
            if call_count["n"] == 1:
                return _make_response(429, headers={"Retry-After": "0"})
            return _make_response(200, text="ok")

    with patch.object(_TestScraper, "_get_cookies", _fake_get_cookies), \
         patch("app.scrapers.base.httpx.AsyncClient", _FakeClient), \
         patch("app.scrapers.base.asyncio.sleep", new=AsyncMock()):
        result = await scraper._fetch("https://example.com/")

    assert result == "ok"
    assert call_count["n"] == 2


@pytest.mark.asyncio
async def test_fetch_503_retries_then_success():
    scraper = _TestScraper()
    call_count = {"n": 0}

    async def _fake_get_cookies(self):
        return [], "Mozilla/5.0"

    class _FakeClient:
        def __init__(self, **kwargs): pass
        async def __aenter__(self): return self
        async def __aexit__(self, *args): pass
        async def get(self, url):
            call_count["n"] += 1
            return _make_response(503) if call_count["n"] < 3 else _make_response(200, text="data")

    with patch.object(_TestScraper, "_get_cookies", _fake_get_cookies), \
         patch("app.scrapers.base.httpx.AsyncClient", _FakeClient), \
         patch("app.scrapers.base.asyncio.sleep", new=AsyncMock()):
        result = await scraper._fetch("https://example.com/")

    assert result == "data"
    assert call_count["n"] == 3


@pytest.mark.asyncio
async def test_fetch_max_retries_exhausted_raises_scraper_error():
    """All 3 attempts return 503 — ScraperError should be raised."""
    scraper = _TestScraper()

    async def _fake_get_cookies(self):
        return [], "Mozilla/5.0"

    class _FakeClient:
        def __init__(self, **kwargs): pass
        async def __aenter__(self): return self
        async def __aexit__(self, *args): pass
        async def get(self, url): return _make_response(503)

    with patch.object(_TestScraper, "_get_cookies", _fake_get_cookies), \
         patch("app.scrapers.base.httpx.AsyncClient", _FakeClient), \
         patch("app.scrapers.base.asyncio.sleep", new=AsyncMock()):
        with pytest.raises(ScraperError):
            await scraper._fetch("https://example.com/")


@pytest.mark.asyncio
async def test_fetch_unexpected_status_raises_scraper_error():
    """A 500 should eventually raise ScraperError after retries."""
    scraper = _TestScraper()

    async def _fake_get_cookies(self):
        return [], "Mozilla/5.0"

    class _FakeClient:
        def __init__(self, **kwargs): pass
        async def __aenter__(self): return self
        async def __aexit__(self, *args): pass
        async def get(self, url):
            resp = _make_response(500)
            resp.raise_for_status.side_effect = Exception("500 Server Error")
            return resp

    with patch.object(_TestScraper, "_get_cookies", _fake_get_cookies), \
         patch("app.scrapers.base.httpx.AsyncClient", _FakeClient), \
         patch("app.scrapers.base.asyncio.sleep", new=AsyncMock()):
        with pytest.raises(ScraperError):
            await scraper._fetch("https://example.com/")


@pytest.mark.asyncio
async def test_fetch_uses_retry_after_header():
    """When 429 includes Retry-After, sleep should be called with that value."""
    scraper = _TestScraper()
    sleep_calls = []

    async def _fake_sleep(seconds):
        sleep_calls.append(seconds)

    async def _fake_get_cookies(self):
        return [], "Mozilla/5.0"

    call_count = {"n": 0}

    class _FakeClient:
        def __init__(self, **kwargs): pass
        async def __aenter__(self): return self
        async def __aexit__(self, *args): pass
        async def get(self, url):
            call_count["n"] += 1
            if call_count["n"] == 1:
                return _make_response(429, headers={"Retry-After": "5"})
            return _make_response(200, text="ok")

    with patch.object(_TestScraper, "_get_cookies", _fake_get_cookies), \
         patch("app.scrapers.base.httpx.AsyncClient", _FakeClient), \
         patch("app.scrapers.base.asyncio.sleep", side_effect=_fake_sleep):
        await scraper._fetch("https://example.com/")

    # First sleep is request_delay (0.0), second is the Retry-After value (5.0)
    assert 5.0 in sleep_calls


# ---------------------------------------------------------------------------
# Dataclass smoke tests
# ---------------------------------------------------------------------------

def test_story_metadata_defaults():
    meta = StoryMetadata(
        title="Test",
        source_url="https://example.com",
        source_key="nhentai",
    )
    assert meta.authors == []
    assert meta.tags == []
    assert meta.total_chapters is None


def test_chapter_info_fields():
    ch = ChapterInfo(chapter_number=1.5, source_url="https://example.com/ch1")
    assert ch.chapter_number == 1.5
    assert ch.title is None


def test_page_info_fields():
    page = PageInfo(page_number=3, source_url="https://cdn.example.com/p3.jpg")
    assert page.page_number == 3
    assert page.width_px is None
