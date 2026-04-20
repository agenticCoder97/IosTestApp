"""Tests for the rewritten FFNet scraper. Mocks at the runner + FicHub
boundaries — never calls the real libraries.
"""
import pytest

from app.scrapers.base import StoryMetadata
from app.scrapers.fanfic import ffnet, _fanficfare_runner, _fichub


def _fake_meta(title="Hello") -> StoryMetadata:
    return StoryMetadata(
        title=title,
        source_url="https://www.fanfiction.net/s/123",
        source_key="ffnet",
        source_id="123",
        total_chapters=1,
        completion_status="ongoing",
    )


async def _async_value(value):
    return value


async def test_get_story_metadata_happy_path_uses_fanficfare(monkeypatch):
    called = {"runner": False, "fichub": False}

    async def fake_runner(url, cookies, ua):
        called["runner"] = True
        return _fake_meta("From FFF"), []

    async def fake_fichub(url):
        called["fichub"] = True
        raise AssertionError("FicHub should not be called on happy path")

    monkeypatch.setattr(_fanficfare_runner, "fetch_via_fanficfare", fake_runner)
    monkeypatch.setattr(_fichub, "fetch_story_meta", fake_fichub)

    scraper = ffnet.FanfictionNetScraper()
    monkeypatch.setattr(scraper, "_get_cookies",
                        lambda: _async_value(([], "iOS/1")))

    meta = await scraper.get_story_metadata("https://www.fanfiction.net/s/123")

    assert meta.title == "From FFF"
    assert called["runner"] is True
    assert called["fichub"] is False


async def test_falls_back_to_fichub_on_fanficfare_error(monkeypatch):
    """FanFicFareError → FicHub used → returned to caller."""
    async def runner_fails(url, cookies, ua):
        raise _fanficfare_runner.FanFicFareError("FFF couldn't parse")

    async def fake_fichub_meta(url):
        return _fichub.FicHubMeta(
            title="From FicHub", author="A", chapters=2, status="complete",
            word_count=500, summary="s", fandoms=["F"],
            epub_url="/epub/x/y.epub", url_id="x",
        )

    async def fake_fichub_split(epub_url):
        return [_fichub.ChapterText(1, "Ch 1", "<p>1</p>"),
                _fichub.ChapterText(2, "Ch 2", "<p>2</p>")]

    monkeypatch.setattr(_fanficfare_runner, "fetch_via_fanficfare", runner_fails)
    monkeypatch.setattr(_fichub, "fetch_story_meta", fake_fichub_meta)
    monkeypatch.setattr(_fichub, "download_and_split_epub", fake_fichub_split)

    scraper = ffnet.FanfictionNetScraper()
    monkeypatch.setattr(scraper, "_get_cookies",
                        lambda: _async_value(([], "iOS/1")))

    meta = await scraper.get_story_metadata("https://www.fanfiction.net/s/123")
    assert meta.title == "From FicHub"
    assert meta.total_chapters == 2

    chapters = await scraper.get_chapter_list("https://www.fanfiction.net/s/123")
    assert len(chapters) == 2
    assert chapters[0].title == "Ch 1"


async def test_falls_back_to_fichub_on_cookie_expired(monkeypatch):
    """CookieExpiredError from runner triggers fallback (not surfaced)."""
    from app.scrapers.base import CookieExpiredError

    async def runner_fails(url, cookies, ua):
        raise CookieExpiredError("403 from FFNet")

    async def fake_fichub_meta(url):
        return _fichub.FicHubMeta("T", "A", 1, "complete", 100, "s", [], "/e/x.epub", "x")

    async def fake_fichub_split(epub_url):
        return [_fichub.ChapterText(1, "C1", "<p>x</p>")]

    monkeypatch.setattr(_fanficfare_runner, "fetch_via_fanficfare", runner_fails)
    monkeypatch.setattr(_fichub, "fetch_story_meta", fake_fichub_meta)
    monkeypatch.setattr(_fichub, "download_and_split_epub", fake_fichub_split)

    scraper = ffnet.FanfictionNetScraper()
    monkeypatch.setattr(scraper, "_get_cookies",
                        lambda: _async_value(([], "iOS/1")))

    meta = await scraper.get_story_metadata("https://www.fanfiction.net/s/123")
    assert meta.title == "T"


async def test_kill_switch_skips_fanficfare(monkeypatch):
    """When FFNET_NEW_SCRAPER_DISABLED=true the runner is never called."""
    from app.core.config import settings as app_settings

    async def runner_should_not_run(url, cookies, ua):
        raise AssertionError("runner should not be called when kill switch is on")

    async def fake_fichub_meta(url):
        return _fichub.FicHubMeta("KillSwitchPath", "A", 1, "ongoing", 1, "", [], "/e/x.epub", "x")

    async def fake_fichub_split(epub_url):
        return [_fichub.ChapterText(1, "c", "<p>x</p>")]

    monkeypatch.setattr(_fanficfare_runner, "fetch_via_fanficfare", runner_should_not_run)
    monkeypatch.setattr(_fichub, "fetch_story_meta", fake_fichub_meta)
    monkeypatch.setattr(_fichub, "download_and_split_epub", fake_fichub_split)
    monkeypatch.setattr(app_settings, "ffnet_new_scraper_disabled", True)

    scraper = ffnet.FanfictionNetScraper()
    monkeypatch.setattr(scraper, "_get_cookies",
                        lambda: _async_value(([], "iOS/1")))

    meta = await scraper.get_story_metadata("https://www.fanfiction.net/s/123")
    assert meta.title == "KillSwitchPath"


async def test_propagates_original_error_when_both_fail(monkeypatch):
    """Primary fails AND FicHub fails → original primary error re-raised."""
    primary_exc = _fanficfare_runner.FanFicFareError("FFF specific failure")

    async def runner_fails(url, cookies, ua):
        raise primary_exc

    async def fichub_fails(url):
        raise _fichub.FicHubError("FicHub also down")

    monkeypatch.setattr(_fanficfare_runner, "fetch_via_fanficfare", runner_fails)
    monkeypatch.setattr(_fichub, "fetch_story_meta", fichub_fails)

    scraper = ffnet.FanfictionNetScraper()
    monkeypatch.setattr(scraper, "_get_cookies",
                        lambda: _async_value(([], "iOS/1")))

    with pytest.raises(_fanficfare_runner.FanFicFareError, match="FFF specific failure"):
        await scraper.get_story_metadata("https://www.fanfiction.net/s/123")


async def test_kill_switch_on_and_fichub_fails_surfaces_fichub_error(monkeypatch):
    """Kill switch on (primary_err is None) → FicHub error propagates directly."""
    from app.core.config import settings as app_settings

    async def fichub_fails(url):
        raise _fichub.FicHubError("FicHub down")

    monkeypatch.setattr(_fichub, "fetch_story_meta", fichub_fails)
    monkeypatch.setattr(app_settings, "ffnet_new_scraper_disabled", True)

    scraper = ffnet.FanfictionNetScraper()
    monkeypatch.setattr(scraper, "_get_cookies",
                        lambda: _async_value(([], "iOS/1")))

    with pytest.raises(_fichub.FicHubError, match="FicHub down"):
        await scraper.get_story_metadata("https://www.fanfiction.net/s/123")
