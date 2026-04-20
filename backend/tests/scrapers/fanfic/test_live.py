"""Live smoke tests — hit real external services. Run manually before each PR.

Usage:
    docker exec backend-fastapi-1 pytest tests/scrapers/fanfic/test_live.py -m live -v

These tests are excluded from CI (CI runs `pytest -m "not live"`).
"""
import pytest

from app.scrapers.fanfic import _fichub, ffnet

pytestmark = pytest.mark.live


# A long, well-known, stable FFNet fic. If FFnet itself is down at test time,
# the test fails — that's the intended signal.
_FFNET_HPMOR = "https://www.fanfiction.net/s/5782108/1/Harry-Potter-and-the-Methods-of-Rationality"


async def test_live_fichub_fetches_real_meta_and_epub():
    """FicHub direct call: confirms the REST + EPUB-split path works end-to-end."""
    meta = await _fichub.fetch_story_meta(_FFNET_HPMOR)
    assert meta.title  # any non-empty title
    assert ".epub" in meta.epub_url  # FicHub serves epubs at /cache/epub/... or /epub/...
    chapters = await _fichub.download_and_split_epub(meta.epub_url)
    assert len(chapters) > 0
    assert chapters[0].html  # non-empty HTML


async def test_live_kill_switch_routes_through_fichub(monkeypatch):
    """With kill switch on, scrape uses FicHub end-to-end (FFF never invoked)."""
    from app.core.config import settings as app_settings
    monkeypatch.setattr(app_settings, "ffnet_new_scraper_disabled", True)

    scraper = ffnet.FanfictionNetScraper()

    async def no_cookies():
        return ([], "Mozilla/5.0 (test)")

    monkeypatch.setattr(scraper, "_get_cookies", no_cookies)

    meta = await scraper.get_story_metadata(_FFNET_HPMOR)
    assert meta.title  # any non-empty title
    chapters = await scraper.get_chapter_list(_FFNET_HPMOR)
    assert len(chapters) > 0


async def test_live_default_path_returns_metadata(monkeypatch):
    """Default path (kill switch off) returns metadata for a real fic.

    Without iOS-harvested CF cookies, FFF will 403 and the fallback fires —
    that's the system working as designed. We only assert that *some* tier
    returns plausible metadata, not which tier handled it.
    """
    scraper = ffnet.FanfictionNetScraper()

    async def no_cookies():
        return ([], "Mozilla/5.0 (test)")

    monkeypatch.setattr(scraper, "_get_cookies", no_cookies)

    meta = await scraper.get_story_metadata(_FFNET_HPMOR)
    assert "Methods of Rationality" in meta.title
