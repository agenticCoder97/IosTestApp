"""
API-level tests for the matcher hook on POST /scrape/comic.

Uses the existing fastapi TestClient setup if present in tests/conftest.py;
otherwise falls back to constructing the app directly.
"""
import pytest
from unittest.mock import patch, AsyncMock, MagicMock

from app.services.mangadex_matcher import MangaDexMatch


@pytest.fixture
def base_payload():
    return {
        "url": "https://toongod.org/manga/x/",
        "source_key": "toongod",
        "cookies": [],
        "user_agent": "ua",
        "content_type": "comic",
        "page_title": "Solo Leveling",
    }


def _mock_redis_and_arq():
    """Patch out Redis + ARQ so scrape initiation doesn't need real infra."""
    # scrape_service uses `r = await aioredis.from_url(...)` so from_url must
    # be an AsyncMock. The returned connection object needs async set/aclose.
    mock_redis_conn = MagicMock()
    mock_redis_conn.set = AsyncMock()
    mock_redis_conn.aclose = AsyncMock()
    mock_from_url = AsyncMock(return_value=mock_redis_conn)
    mock_arq = AsyncMock()
    mock_arq.enqueue_job = AsyncMock()
    mock_arq.aclose = AsyncMock()
    return [
        patch("app.services.scrape_service.get_cache_redis", mock_from_url),
        patch("app.services.scrape_service.get_arq", return_value=mock_arq),
    ]


async def test_match_response_when_matcher_returns_hit(monkeypatch, client, base_payload):
    async def fake_match(*, source, source_url, source_title):
        return MangaDexMatch(
            manga_id="abc",
            mangadex_url="https://mangadex.org/title/abc",
            title="Solo Leveling",
            confidence=0.91,
            thumbnail_url=None,
            chapter_count=179,
            source_chapter_count=180,
        )
    monkeypatch.setattr(
        "app.services.mangadex_matcher.find_mangadex_match", fake_match,
    )
    r = await client.post("/scrape/comic", json=base_payload)
    assert r.status_code == 202
    assert r.json()["match"]["manga_id"] == "abc"


async def test_skip_match_bypasses_matcher(monkeypatch, client, base_payload):
    called = {"n": 0}

    async def fake_match(**_):
        called["n"] += 1
        return None

    monkeypatch.setattr(
        "app.services.mangadex_matcher.find_mangadex_match", fake_match,
    )
    patches = _mock_redis_and_arq()
    with patches[0], patches[1]:
        base_payload["skip_match"] = True
        r = await client.post("/scrape/comic", json=base_payload)

    # Not a match response — falls through to initiate_scrape (202 with job).
    assert r.status_code in (200, 202)
    assert "match" not in r.json()
    assert called["n"] == 0


async def test_ineligible_source_skips_matcher(monkeypatch, client, base_payload):
    called = {"n": 0}

    async def fake_match(**_):
        called["n"] += 1
        return None

    monkeypatch.setattr(
        "app.services.mangadex_matcher.find_mangadex_match", fake_match,
    )
    patches = _mock_redis_and_arq()
    with patches[0], patches[1]:
        base_payload["source_key"] = "nhentai"
        base_payload["url"] = "https://nhentai.net/g/123/"
        r = await client.post("/scrape/comic", json=base_payload)

    assert r.status_code in (200, 202)
    assert called["n"] == 0


async def test_kill_switch_returns_503_for_direct_mangadex_post(monkeypatch, client, base_payload):
    from app.core.config import settings
    monkeypatch.setattr(settings, "mangadex_disabled", True)
    base_payload["source_key"] = "mangadex"
    base_payload["url"] = "https://mangadex.org/title/abc"
    r = await client.post("/scrape/comic", json=base_payload)
    assert r.status_code == 503
    assert "disabled" in r.json()["detail"].lower()
