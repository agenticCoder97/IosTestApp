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
