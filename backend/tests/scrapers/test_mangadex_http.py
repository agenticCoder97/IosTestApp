"""
Tests for the MangaDex HTTP client wrapper — rate limiting, retry, circuit breaker.

Pure unit tests using httpx.MockTransport so no network is required.
"""
import time

import httpx
import pytest

from app.scrapers.comic._mangadex_http import (
    MangadexHTTPClient,
    MangadexCircuitOpenError,
    MangadexRateLimitError,
)


def _client_with_responses(responses: list[httpx.Response]) -> MangadexHTTPClient:
    """Build a client whose AsyncClient pulls responses from a fixed list."""
    it = iter(responses)
    transport = httpx.MockTransport(lambda req: next(it))
    client = MangadexHTTPClient()
    # Replace the real httpx.AsyncClient with one bound to the mock transport.
    client._client = httpx.AsyncClient(
        transport=transport,
        timeout=10.0,
        headers={"User-Agent": MangadexHTTPClient.USER_AGENT},
    )
    return client


def _reset_circuit():
    """Reset class-level circuit state between tests."""
    MangadexHTTPClient._circuit_429s.clear()
    MangadexHTTPClient._circuit_open_until = 0.0


@pytest.fixture(autouse=True)
def _isolate_circuit():
    _reset_circuit()
    yield
    _reset_circuit()


async def test_get_json_success():
    client = _client_with_responses([httpx.Response(200, json={"data": "ok"})])
    result = await client.get_json("https://api.mangadex.org/manga/1")
    assert result == {"data": "ok"}


async def test_429_retries_then_succeeds():
    client = _client_with_responses([
        httpx.Response(429, headers={"Retry-After": "0"}),
        httpx.Response(200, json={"data": "ok"}),
    ])
    result = await client.get_json("https://api.mangadex.org/manga/1")
    assert result == {"data": "ok"}


async def test_429_exhausts_retries_raises():
    client = _client_with_responses([
        httpx.Response(429, headers={"Retry-After": "0"}),
        httpx.Response(429, headers={"Retry-After": "0"}),
        httpx.Response(429, headers={"Retry-After": "0"}),
    ])
    with pytest.raises(MangadexRateLimitError):
        await client.get_json("https://api.mangadex.org/manga/1")


async def test_circuit_opens_after_5_429s_in_60s():
    # Drive 5 separate calls each producing one 429-then-success; pre-load
    # the circuit by hand (simpler than driving 15 mock responses).
    client = _client_with_responses([httpx.Response(200, json={"ok": True})])
    now = time.monotonic()
    for _ in range(5):
        MangadexHTTPClient._circuit_429s.append(now)
    # Trigger the bookkeeping check that opens the circuit.
    client._record_429()
    assert MangadexHTTPClient._circuit_open_until > time.monotonic()
    with pytest.raises(MangadexCircuitOpenError):
        await client.get_json("https://api.mangadex.org/manga/1")


async def test_circuit_closes_after_cooldown():
    MangadexHTTPClient._circuit_open_until = time.monotonic() - 1  # already in past
    client = _client_with_responses([httpx.Response(200, json={"ok": True})])
    result = await client.get_json("https://api.mangadex.org/manga/1")
    assert result == {"ok": True}


async def test_at_home_uses_separate_limiter():
    # Smoke: at_home=True path returns body and shouldn't raise on a single call.
    client = _client_with_responses([
        httpx.Response(200, json={"baseUrl": "https://uploads.mangadex.org",
                                   "chapter": {"hash": "abc", "data": ["1.jpg"]}})
    ])
    result = await client.get_json(
        "https://api.mangadex.org/at-home/server/xyz", at_home=True,
    )
    assert "baseUrl" in result
