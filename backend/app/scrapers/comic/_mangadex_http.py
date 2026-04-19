"""
HTTP client for MangaDex API + MD@Home CDN.

One source of truth for rate limiters, retries, and the circuit breaker so
both MangadexScraper and the matcher service hit the same limits.

Limits (https://api.mangadex.org/docs/2-limitations/):
- Global: 5 req/s/IP across all endpoints.
- /at-home/server/{id}: 40 req/min in addition to the global limit.
- 5 × 429 in 60 s opens a 5-minute circuit breaker (defensive — MangaDex
  has been known to ban IPs that ignore Retry-After).
"""
import asyncio
import logging
import random
import time
from collections import deque
from pathlib import Path
from typing import Any

import aiolimiter
import httpx

from app.core.config import settings

logger = logging.getLogger(__name__)


class MangadexAPIError(Exception):
    """Generic non-retryable MangaDex API error."""


class MangadexRateLimitError(MangadexAPIError):
    """Raised after 429 retries are exhausted."""


class MangadexCircuitOpenError(MangadexAPIError):
    """Raised when the circuit breaker is open. Caller should treat as 'try later'."""


class MangadexHTTPClient:
    """Shared HTTP client with rate limiting, retries, and a circuit breaker."""

    USER_AGENT = "Astral/1.0 (+contact: nikhil_netra@hotmail.com)"
    REPORT_URL = "https://api.mangadex.network/report"

    # Class-level so all instances in a worker process share limiter + circuit state.
    _global_limiter = aiolimiter.AsyncLimiter(5, 1)
    _at_home_limiter = aiolimiter.AsyncLimiter(40, 60)
    _circuit_429s: deque = deque(maxlen=5)
    _circuit_open_until: float = 0.0

    def __init__(self):
        self._client = httpx.AsyncClient(
            timeout=httpx.Timeout(30.0, connect=10.0),
            headers={
                "User-Agent": self.USER_AGENT,
                "Accept": "application/json",
            },
            follow_redirects=True,
            http2=False,  # Avoid Via header injection — ToS forbids.
        )

    async def aclose(self) -> None:
        await self._client.aclose()

    async def get_json(
        self, url: str, *, params: dict | None = None, at_home: bool = False,
    ) -> dict[str, Any]:
        """GET with rate limiting + retry. `at_home=True` adds the 40/min limiter."""
        self._guard_circuit()
        limiter = self._at_home_limiter if at_home else self._global_limiter
        async with limiter:
            return await self._do("GET", url, params=params, json_body=None)

    async def post_json(self, url: str, *, json: dict) -> None:
        """Fire-and-forget POST (used for MD@Home report). No retry — best-effort."""
        async with self._global_limiter:
            try:
                await self._client.post(url, json=json)
            except Exception as e:
                logger.warning("post_json failed | url=%s err=%s", url, e)

    async def fetch_image_to_disk(self, url: str, dest_path: str) -> tuple[str, int]:
        """
        Stream a CDN image to disk. Returns (relative_path, byte_count).
        Does NOT use rate limiters — CDN traffic is unmetered per ToS.
        """
        self._guard_circuit()
        full = Path(settings.block_volume_path) / dest_path
        full.parent.mkdir(parents=True, exist_ok=True)

        async with self._client.stream("GET", url) as r:
            if r.status_code != 200:
                raise MangadexAPIError(f"image fetch HTTP {r.status_code} for {url}")
            byte_count = 0
            with full.open("wb") as f:
                async for chunk in r.aiter_bytes(chunk_size=65536):
                    f.write(chunk)
                    byte_count += len(chunk)
        return dest_path, byte_count

    async def _do(
        self, method: str, url: str, *, params: dict | None, json_body: dict | None,
    ) -> dict[str, Any]:
        for attempt in range(3):
            r = await self._client.request(method, url, params=params, json=json_body)
            if r.status_code == 429:
                self._record_429()
                self._guard_circuit()
                wait = self._parse_retry_after(r) or (2 ** attempt)
                logger.warning(
                    "mangadex 429 | url=%s attempt=%d wait=%.1fs",
                    url, attempt, wait,
                )
                await asyncio.sleep(wait + random.uniform(0, 0.5))
                continue
            if 500 <= r.status_code < 600:
                wait = (2 ** attempt) + random.uniform(0, 0.5)
                logger.warning(
                    "mangadex 5xx | url=%s status=%d attempt=%d wait=%.1fs",
                    url, r.status_code, attempt, wait,
                )
                await asyncio.sleep(wait)
                continue
            r.raise_for_status()
            return r.json() if r.content else {}
        raise MangadexRateLimitError(f"max retries exhausted for {method} {url}")

    @staticmethod
    def _parse_retry_after(r: httpx.Response) -> float | None:
        v = r.headers.get("Retry-After")
        if v is None:
            return None
        try:
            return float(v)
        except ValueError:
            return None

    def _record_429(self) -> None:
        now = time.monotonic()
        type(self)._circuit_429s.append(now)
        if (
            len(type(self)._circuit_429s) == 5
            and (now - type(self)._circuit_429s[0]) <= 60
        ):
            type(self)._circuit_open_until = now + 300
            logger.error(
                "mangadex circuit breaker opened | until_monotonic=%.0f",
                type(self)._circuit_open_until,
            )

    def _guard_circuit(self) -> None:
        now = time.monotonic()
        if now < type(self)._circuit_open_until:
            remain = type(self)._circuit_open_until - now
            raise MangadexCircuitOpenError(
                f"circuit open for {remain:.0f}s more"
            )
