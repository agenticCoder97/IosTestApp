# AST-30 — MangaDex Source Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add MangaDex as a first-class comic source with rate-limited HTTP, MD@Home reporting, a synchronous title-match hook on `POST /scrape/comic` that pops a confirm dialog in iOS before swapping a toongod/hentai20 add to MangaDex.

**Architecture:** New `MangadexScraper(BaseScraper)` + shared `MangadexHTTPClient` (aiolimiter 5/s + 40/min `/at-home/server/` + 5×429-in-60s circuit breaker) + pure `mangadex_matcher` scoring service. Matcher runs synchronously in the FastAPI request thread; on a ≥0.85 hit, returns `202 { match }` and iOS shows a dialog. On accept, iOS POSTs back with `source: mangadex` plus three new optional fields (`previous_source`, `previous_source_url`, `match_confidence`) that get persisted on the `comics` row. Image pre-fetch + ToS report POST is inline in `BaseScraper.download_image` (overridden in `MangadexScraper`).

**Tech Stack:** Python 3.11, FastAPI, SQLAlchemy 2.x async, Alembic, ARQ, `httpx`, `aiolimiter`, `rapidfuzz`, pytest + `httpx.MockTransport`. SwiftUI + SwiftData on iOS 17.2.

**Spec:** [docs/superpowers/specs/2026-04-19-ast30-mangadex-source-design.md](../specs/2026-04-19-ast30-mangadex-source-design.md)

**Branch:** `feature/ast-30-mangadex-source` (already created off `development`).

**Linear:** `Closes AST-30` magic-word in the PR body so the issue auto-transitions on merge.

---

## File Map

**Backend — new:**
- `backend/app/scrapers/comic/_mangadex_http.py` — HTTP client, limiters, circuit breaker, errors
- `backend/app/scrapers/comic/mangadex.py` — `MangadexScraper(BaseScraper)`
- `backend/app/services/mangadex_matcher.py` — `find_mangadex_match` + scoring
- `backend/alembic/versions/f2a3b4c5d6e7_add_comic_mangadex_swap_columns.py` — migration
- `backend/tests/scrapers/fixtures/mangadex/manga_detail.json` — saved API response
- `backend/tests/scrapers/fixtures/mangadex/feed_page1.json` — first page of chapter feed
- `backend/tests/scrapers/fixtures/mangadex/feed_page2.json` — second page (pagination test)
- `backend/tests/scrapers/fixtures/mangadex/at_home_server.json` — at-home response
- `backend/tests/scrapers/fixtures/mangadex/search_results.json` — search response
- `backend/tests/scrapers/test_mangadex_http.py` — limiter/retry/circuit-breaker tests
- `backend/tests/scrapers/test_mangadex_parsing.py` — fixture-based parsing tests
- `backend/tests/scrapers/test_mangadex_tos_audit.py` — AST audit ensuring report POST is wired
- `backend/tests/services/test_mangadex_matcher.py` — scoring tests
- `backend/tests/api/test_scrape_router_mangadex.py` — API endpoint behavior

**Backend — modified:**
- `backend/app/core/constants.py` — add `SourceKey.MANGADEX` + rate-config row
- `backend/app/core/config.py` — three new settings fields
- `backend/app/models/comic.py` — three new ORM columns on `Comic`
- `backend/app/schemas/scrape.py` — extend `ScrapeRequest` with five new optional fields + `MangaDexMatchPayload` + `ScrapeMatchResponse`
- `backend/app/services/scrape_service.py` — accept new optional kwargs in `initiate_scrape`
- `backend/app/api/v1/routes/scrape.py` — matcher hook + 202/503 branches in `initiate_comic_scrape`
- `backend/app/tasks/comic_scrape_task.py:22-26` — register `MangadexScraper` in `SCRAPER_REGISTRY`
- `backend/requirements.txt` — `aiolimiter`, `rapidfuzz`
- `backend/.env.example` — three new commented vars
- `CLAUDE.md` — short MangaDex env-var section

**iOS — new:**
- `ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/MangaDexMatchDialog.swift`

**iOS — modified:**
- `ios/Astral/Packages/Core/Sources/Core/Utilities/ContentType.swift:35-39` — add `.mangadex`
- `ios/Astral/Packages/Core/Sources/Core/Models/LocalComic.swift` — three optional properties
- `ios/Astral/Packages/Networking/Sources/Networking/CookieStore.swift:13-19` — domain mapping
- `ios/Astral/Packages/Networking/Sources/Networking/DTOs/ScrapeDTOs.swift` — extend `ScrapeRequest`, add `MangaDexMatchPayload`, `ScrapeOutcome` enum
- `ios/Astral/Packages/Networking/Sources/Networking/APIClient.swift` — add `submitScrape(_:) -> ScrapeOutcome`
- `ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/ComicBrowserView.swift` — add MangaDex case to dropdown / `allowedDomains` / `sourceURL` / `evaluateCanScrape`; wire match flow
- `ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicCardView.swift:20-27` — add MangaDex icon

---

## Tasks

Each task is self-contained: one concept, one commit. Run tests inside the local docker stack with `docker compose -f backend/docker-compose.local.yml exec fastapi pytest <path>`.

---

### Task 1: Verify branch + add new Python deps

**Files:**
- Modify: `backend/requirements.txt`

- [ ] **Step 1: Confirm branch is `feature/ast-30-mangadex-source` from `origin/development`**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp"
git branch --show-current
git log --oneline -1
```

Expected current branch: `feature/ast-30-mangadex-source`. Most recent commit: `[docs] AST-30 add MangaDex comic source design spec`.

- [ ] **Step 2: Check whether `aiolimiter` and `rapidfuzz` are already present**

```bash
grep -E "^(aiolimiter|rapidfuzz)" backend/requirements.txt || echo "missing"
```

- [ ] **Step 3: Append missing entries**

If either prints `missing`, append to `backend/requirements.txt`:

```
aiolimiter==1.1.0
rapidfuzz==3.6.1
```

- [ ] **Step 4: Rebuild fastapi and arq_worker images so the new deps are installed**

```bash
docker compose -f backend/docker-compose.local.yml build fastapi arq_worker
```

Expected: builds succeed. New deps appear in `pip install` output.

- [ ] **Step 5: Commit**

```bash
git add backend/requirements.txt
git commit -m "[backend] AST-30 add aiolimiter and rapidfuzz deps for MangaDex"
```

---

### Task 2: Add `SourceKey.MANGADEX`, rate config, and settings env vars

**Files:**
- Modify: `backend/app/core/constants.py`
- Modify: `backend/app/core/config.py`
- Modify: `backend/.env.example`

- [ ] **Step 1: Add the enum value and rate-config row to `constants.py`**

In `backend/app/core/constants.py`, add `MANGADEX = "mangadex"` to `SourceKey` (after `FFNET`):

```python
class SourceKey(str, Enum):
    NHENTAI = "nhentai"
    TOONGOD = "toongod"
    HENTAI20 = "hentai20"
    AO3 = "ao3"
    FFNET = "ffnet"
    MANGADEX = "mangadex"
```

Add to `SOURCE_RATE_CONFIG`:

```python
SOURCE_RATE_CONFIG: dict[str, dict] = {
    SourceKey.NHENTAI:  {"delay": 1.5, "max_retries": 3, "requires_browser": False},
    SourceKey.TOONGOD:  {"delay": 1.0, "max_retries": 3, "requires_browser": False},
    SourceKey.HENTAI20: {"delay": 2.0, "max_retries": 3, "requires_browser": True},
    SourceKey.AO3:      {"delay": 2.0, "max_retries": 3, "requires_browser": False},
    SourceKey.FFNET:    {"delay": 1.5, "max_retries": 3, "requires_browser": False},
    SourceKey.MANGADEX: {"delay": 0.0, "max_retries": 3, "requires_browser": False},
}
```

- [ ] **Step 2: Add three settings fields to `config.py`**

In `backend/app/core/config.py` — append inside the `Settings` class, just before the `@property` decorators:

```python
    # MangaDex (AST-30) — kill switch + matcher tuning
    mangadex_disabled: bool = False
    mangadex_title_match_threshold: float = 0.85
    mangadex_auto_switch_source: bool = True
```

- [ ] **Step 3: Add the same vars to `.env.example` (commented)**

Append to `backend/.env.example`:

```
# MangaDex (AST-30)
# MANGADEX_DISABLED=false
# MANGADEX_TITLE_MATCH_THRESHOLD=0.85
# MANGADEX_AUTO_SWITCH_SOURCE=true
```

- [ ] **Step 4: Verify settings load**

```bash
docker compose -f backend/docker-compose.local.yml exec fastapi \
  python -c "from app.core.config import settings; \
             print(settings.mangadex_disabled, \
                   settings.mangadex_title_match_threshold, \
                   settings.mangadex_auto_switch_source)"
```

Expected: `False 0.85 True`.

- [ ] **Step 5: Commit**

```bash
git add backend/app/core/constants.py backend/app/core/config.py backend/.env.example
git commit -m "[backend] AST-30 add MangaDex source key + rate-config + settings"
```

---

### Task 3: HTTP client wrapper + limiters + circuit breaker

**Files:**
- Create: `backend/app/scrapers/comic/_mangadex_http.py`
- Create: `backend/tests/scrapers/__init__.py` (if missing — empty file)
- Create: `backend/tests/scrapers/test_mangadex_http.py`

- [ ] **Step 1: Confirm tests dir layout**

```bash
ls backend/tests/scrapers/ 2>/dev/null
```

If `__init__.py` is missing in `backend/tests/scrapers/`, create it:

```bash
touch backend/tests/scrapers/__init__.py
```

- [ ] **Step 2: Write the failing test file**

Create `backend/tests/scrapers/test_mangadex_http.py`:

```python
"""
Tests for the MangaDex HTTP client wrapper — rate limiting, retry, circuit breaker.

Pure unit tests using httpx.MockTransport so no network is required.
"""
import asyncio
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
```

- [ ] **Step 3: Run tests to confirm they fail (no module)**

```bash
docker compose -f backend/docker-compose.local.yml exec fastapi \
  pytest tests/scrapers/test_mangadex_http.py -v
```

Expected: import error — `app.scrapers.comic._mangadex_http` does not exist.

- [ ] **Step 4: Implement the HTTP client**

Create `backend/app/scrapers/comic/_mangadex_http.py`:

```python
"""
HTTP client for MangaDex API + MD@Home CDN.

One source of truth for rate limiters, retries, and the circuit breaker so
both MangadexScraper and the matcher hit the same limits.

Limits (https://api.mangadex.org/docs/2-limitations/):
- Global: 5 req/s/IP across all endpoints.
- /at-home/server/{id}: 40 req/min in addition to the global limit.
- 5 × 429 in 60 s opens a 5-minute circuit breaker (defensive — MangaDex
  has been known to ban IPs that ignore Retry-After).
"""
import asyncio
import logging
import os
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
```

- [ ] **Step 5: Re-run tests — should pass**

```bash
docker compose -f backend/docker-compose.local.yml exec fastapi \
  pytest tests/scrapers/test_mangadex_http.py -v
```

Expected: 6 passed.

- [ ] **Step 6: Commit**

```bash
git add backend/app/scrapers/comic/_mangadex_http.py \
        backend/tests/scrapers/test_mangadex_http.py \
        backend/tests/scrapers/__init__.py
git commit -m "[backend] AST-30 add MangaDex HTTP client with limiters and circuit breaker"
```

---

### Task 4: Save MangaDex API fixtures + parsing tests for `get_story_metadata`

**Files:**
- Create: `backend/tests/scrapers/fixtures/__init__.py` (empty)
- Create: `backend/tests/scrapers/fixtures/mangadex/__init__.py` (empty)
- Create: `backend/tests/scrapers/fixtures/mangadex/manga_detail.json`
- Create: `backend/tests/scrapers/test_mangadex_parsing.py`
- Create: `backend/app/scrapers/comic/mangadex.py`

- [ ] **Step 1: Save the manga-detail fixture**

Create `backend/tests/scrapers/fixtures/mangadex/manga_detail.json`:

```json
{
  "result": "ok",
  "response": "entity",
  "data": {
    "id": "32d76d19-8a05-4db0-9fc2-e0b0648fe9d0",
    "type": "manga",
    "attributes": {
      "title": {"en": "Solo Leveling"},
      "altTitles": [{"ko": "나 혼자만 레벨업"}],
      "description": {"en": "10 years ago, after 'the Gate' that connected..."},
      "originalLanguage": "ko",
      "lastVolume": "14",
      "lastChapter": "179",
      "status": "completed",
      "year": 2018,
      "contentRating": "safe",
      "tags": [
        {"id": "t1", "type": "tag", "attributes": {"name": {"en": "Action"}, "group": "genre"}},
        {"id": "t2", "type": "tag", "attributes": {"name": {"en": "Adventure"}, "group": "genre"}}
      ]
    },
    "relationships": [
      {
        "id": "a1",
        "type": "author",
        "attributes": {"name": "Chugong"}
      },
      {
        "id": "c1",
        "type": "cover_art",
        "attributes": {"fileName": "cover123.jpg"}
      }
    ]
  }
}
```

- [ ] **Step 2: Write the failing parsing test**

Create `backend/tests/scrapers/test_mangadex_parsing.py`:

```python
"""
Fixture-based tests for MangadexScraper. No network — all _http calls are
monkeypatched to return saved JSON.
"""
import json
from pathlib import Path

import pytest

from app.scrapers.comic.mangadex import MangadexScraper

FIXTURES = Path(__file__).parent / "fixtures" / "mangadex"


def _load(name: str) -> dict:
    return json.loads((FIXTURES / name).read_text())


@pytest.fixture
def scraper(monkeypatch):
    s = MangadexScraper()

    async def fake_get(url, *, params=None, at_home=False):
        if "/manga/" in url and "/feed" not in url and "/at-home" not in url:
            return _load("manga_detail.json")
        raise AssertionError(f"unexpected URL in test: {url}")

    monkeypatch.setattr(s._http, "get_json", fake_get)
    return s


async def test_get_story_metadata_extracts_title_and_lang(scraper):
    meta = await scraper.get_story_metadata(
        "https://mangadex.org/title/32d76d19-8a05-4db0-9fc2-e0b0648fe9d0"
    )
    assert meta.title == "Solo Leveling"
    assert meta.language == "ko"
    assert meta.source_id == "32d76d19-8a05-4db0-9fc2-e0b0648fe9d0"
    assert meta.source_key == "mangadex"


async def test_get_story_metadata_extracts_authors_and_tags(scraper):
    meta = await scraper.get_story_metadata(
        "https://mangadex.org/title/32d76d19-8a05-4db0-9fc2-e0b0648fe9d0"
    )
    assert "Chugong" in meta.authors
    tag_names = {t["name"] for t in meta.tags}
    assert "Action" in tag_names
    assert "Adventure" in tag_names


async def test_get_story_metadata_builds_thumbnail_url(scraper):
    meta = await scraper.get_story_metadata(
        "https://mangadex.org/title/32d76d19-8a05-4db0-9fc2-e0b0648fe9d0"
    )
    assert meta.thumbnail_url == (
        "https://uploads.mangadex.org/covers/"
        "32d76d19-8a05-4db0-9fc2-e0b0648fe9d0/cover123.jpg.512.jpg"
    )


async def test_get_story_metadata_rejects_unparseable_url(scraper):
    with pytest.raises(ValueError):
        await scraper.get_story_metadata("https://mangadex.org/")
```

- [ ] **Step 3: Run tests — confirm failure (no module)**

```bash
docker compose -f backend/docker-compose.local.yml exec fastapi \
  pytest tests/scrapers/test_mangadex_parsing.py -v
```

Expected: import error — `app.scrapers.comic.mangadex` does not exist.

- [ ] **Step 4: Create the scraper file with `get_story_metadata`**

Create `backend/app/scrapers/comic/mangadex.py`:

```python
"""
MangaDex comic source adapter (AST-30).

# MangaDex API ToS (https://api.mangadex.org/docs/):
# - Honor takedown requests (kill-switch via MANGADEX_DISABLED env)
# - Real User-Agent required; no Via header; TLS 1.2+
# - POST success/failure to api.mangadex.network/report on every page fetch
# - Astral is a private single-user app on a local device — public attribution
#   clause does not apply, but report POSTs are still mandatory.
"""
import logging
import re
import time
from typing import Optional
from urllib.parse import urlparse

from app.core.constants import SourceKey
from app.scrapers.base import (
    BaseScraper,
    ChapterInfo,
    PageInfo,
    StoryMetadata,
)
from app.scrapers.comic._mangadex_http import (
    MangadexAPIError,
    MangadexHTTPClient,
)

logger = logging.getLogger(__name__)

_TITLE_URL_RE = re.compile(r"/title/([0-9a-f-]+)", re.I)
_CHAPTER_URL_RE = re.compile(r"/chapter/([0-9a-f-]+)", re.I)
_API = "https://api.mangadex.org"


def _extract_manga_id(url: str) -> str:
    m = _TITLE_URL_RE.search(urlparse(url).path)
    if not m:
        raise ValueError(f"Cannot extract MangaDex manga id from URL: {url}")
    return m.group(1)


def _extract_chapter_id(url: str) -> str:
    m = _CHAPTER_URL_RE.search(urlparse(url).path)
    if not m:
        raise ValueError(f"Cannot extract MangaDex chapter id from URL: {url}")
    return m.group(1)


def _english_title(title_obj: dict) -> str:
    return (
        title_obj.get("en")
        or next(iter(title_obj.values()), "Unknown Title")
    )


class MangadexScraper(BaseScraper):
    source_key = SourceKey.MANGADEX
    content_type = "comic"
    requires_browser = False
    request_delay_seconds = 0.0  # rate limiter handles pacing
    max_retries = 3

    def __init__(self):
        super().__init__()
        self._http = MangadexHTTPClient()

    async def get_story_metadata(self, url: str) -> StoryMetadata:
        manga_id = _extract_manga_id(url)
        body = await self._http.get_json(
            f"{_API}/manga/{manga_id}",
            params={"includes[]": ["cover_art", "author"]},
        )
        data = body["data"]
        attrs = data["attributes"]
        title = _english_title(attrs.get("title", {}))
        authors: list[str] = []
        cover_filename: Optional[str] = None
        for rel in data.get("relationships", []):
            rtype = rel.get("type")
            rattrs = rel.get("attributes") or {}
            if rtype == "author":
                name = rattrs.get("name")
                if name:
                    authors.append(name)
            elif rtype == "cover_art":
                fn = rattrs.get("fileName")
                if fn:
                    cover_filename = fn
        thumbnail_url: Optional[str] = None
        if cover_filename:
            thumbnail_url = (
                f"https://uploads.mangadex.org/covers/{manga_id}/{cover_filename}.512.jpg"
            )
        tags = [
            {
                "name": _english_title(t["attributes"].get("name", {})),
                "tag_type": t["attributes"].get("group", "tag"),
            }
            for t in attrs.get("tags", [])
        ]
        last_chapter = attrs.get("lastChapter")
        try:
            total_chapters = int(float(last_chapter)) if last_chapter else None
        except (TypeError, ValueError):
            total_chapters = None
        return StoryMetadata(
            title=title,
            source_url=f"https://mangadex.org/title/{manga_id}",
            source_key=self.source_key,
            source_id=manga_id,
            description=_english_title(attrs.get("description", {})) or None,
            language=attrs.get("originalLanguage"),
            authors=authors,
            tags=tags,
            thumbnail_url=thumbnail_url,
            total_chapters=total_chapters,
            category=attrs.get("contentRating"),
        )

    async def get_chapter_list(self, story_url: str) -> list[ChapterInfo]:
        raise NotImplementedError("filled in Task 5")

    async def get_chapter_pages(self, chapter_url: str) -> list[PageInfo]:
        raise NotImplementedError("filled in Task 6")

    async def get_chapter_text(self, chapter_url: str) -> str:
        raise NotImplementedError("MangaDex is a comic source — no text content")

    async def search(
        self, *, title: str, content_ratings: list[str], limit: int = 10,
    ) -> list[dict]:
        raise NotImplementedError("filled in Task 9")
```

- [ ] **Step 5: Re-run parsing tests**

```bash
docker compose -f backend/docker-compose.local.yml exec fastapi \
  pytest tests/scrapers/test_mangadex_parsing.py -v
```

Expected: 4 passed.

- [ ] **Step 6: Commit**

```bash
git add backend/app/scrapers/comic/mangadex.py \
        backend/tests/scrapers/test_mangadex_parsing.py \
        backend/tests/scrapers/fixtures/mangadex/manga_detail.json \
        backend/tests/scrapers/fixtures/__init__.py \
        backend/tests/scrapers/fixtures/mangadex/__init__.py
git commit -m "[backend] AST-30 MangadexScraper.get_story_metadata + fixtures"
```

---

### Task 5: `get_chapter_list` with pagination + `externalUrl` filter

**Files:**
- Create: `backend/tests/scrapers/fixtures/mangadex/feed_page1.json`
- Create: `backend/tests/scrapers/fixtures/mangadex/feed_page2.json`
- Modify: `backend/tests/scrapers/test_mangadex_parsing.py`
- Modify: `backend/app/scrapers/comic/mangadex.py`

- [ ] **Step 1: Save two fixture pages**

`backend/tests/scrapers/fixtures/mangadex/feed_page1.json`:

```json
{
  "result": "ok",
  "data": [
    {
      "id": "ch-1",
      "type": "chapter",
      "attributes": {
        "chapter": "1",
        "title": "Prologue",
        "translatedLanguage": "en",
        "externalUrl": null
      }
    },
    {
      "id": "ch-2",
      "type": "chapter",
      "attributes": {
        "chapter": "2",
        "title": "First Steps",
        "translatedLanguage": "en",
        "externalUrl": null
      }
    },
    {
      "id": "ch-skip",
      "type": "chapter",
      "attributes": {
        "chapter": "3",
        "title": "Hosted on MangaPlus",
        "translatedLanguage": "en",
        "externalUrl": "https://mangaplus.shueisha.co.jp/viewer/..."
      }
    }
  ],
  "limit": 3,
  "offset": 0,
  "total": 5
}
```

`backend/tests/scrapers/fixtures/mangadex/feed_page2.json`:

```json
{
  "result": "ok",
  "data": [
    {
      "id": "ch-4",
      "type": "chapter",
      "attributes": {
        "chapter": "4",
        "title": "Onward",
        "translatedLanguage": "en",
        "externalUrl": null
      }
    },
    {
      "id": "ch-5",
      "type": "chapter",
      "attributes": {
        "chapter": "5",
        "title": null,
        "translatedLanguage": "en",
        "externalUrl": null
      }
    }
  ],
  "limit": 3,
  "offset": 3,
  "total": 5
}
```

(`limit: 3` in fixtures simulates pagination boundary; production limit is `500`.)

- [ ] **Step 2: Add tests for `get_chapter_list` to the parsing test file**

Append to `backend/tests/scrapers/test_mangadex_parsing.py`:

```python
@pytest.fixture
def scraper_feed(monkeypatch):
    s = MangadexScraper()
    feed_calls = {"n": 0}

    async def fake_get(url, *, params=None, at_home=False):
        if "/feed" in url:
            feed_calls["n"] += 1
            return _load(f"feed_page{feed_calls['n']}.json")
        raise AssertionError(f"unexpected URL: {url}")

    monkeypatch.setattr(s._http, "get_json", fake_get)
    return s


async def test_get_chapter_list_paginates_and_filters_external(scraper_feed):
    chapters = await scraper_feed.get_chapter_list(
        "https://mangadex.org/title/32d76d19-8a05-4db0-9fc2-e0b0648fe9d0"
    )
    # 5 chapters in fixtures, but ch-skip has externalUrl → filtered out → 4 returned.
    assert len(chapters) == 4
    numbers = [c.chapter_number for c in chapters]
    assert numbers == [1.0, 2.0, 4.0, 5.0]
    assert chapters[0].title == "Prologue"
    assert chapters[3].title is None
    # source_url is the canonical chapter URL.
    assert chapters[0].source_url == "https://mangadex.org/chapter/ch-1"
```

- [ ] **Step 3: Run tests — confirm failure (NotImplementedError)**

```bash
docker compose -f backend/docker-compose.local.yml exec fastapi \
  pytest tests/scrapers/test_mangadex_parsing.py::test_get_chapter_list_paginates_and_filters_external -v
```

Expected: `NotImplementedError: filled in Task 5`.

- [ ] **Step 4: Implement `get_chapter_list`**

Replace the `get_chapter_list` body in `backend/app/scrapers/comic/mangadex.py`:

```python
    async def get_chapter_list(self, story_url: str) -> list[ChapterInfo]:
        manga_id = _extract_manga_id(story_url)
        chapters: list[ChapterInfo] = []
        offset = 0
        limit = 500
        while True:
            body = await self._http.get_json(
                f"{_API}/manga/{manga_id}/feed",
                params={
                    "translatedLanguage[]": ["en"],
                    "order[chapter]": "asc",
                    "limit": limit,
                    "offset": offset,
                },
            )
            page = body.get("data", [])
            for ch in page:
                attrs = ch.get("attributes", {})
                # Skip chapters hosted on external readers (MangaPlus etc.).
                if attrs.get("externalUrl"):
                    continue
                num_str = attrs.get("chapter")
                try:
                    chapter_number = float(num_str) if num_str is not None else None
                except (TypeError, ValueError):
                    chapter_number = None
                if chapter_number is None:
                    continue
                chapters.append(ChapterInfo(
                    chapter_number=chapter_number,
                    title=attrs.get("title") or None,
                    source_url=f"https://mangadex.org/chapter/{ch['id']}",
                ))
            total = body.get("total", 0)
            offset += body.get("limit", limit)
            if offset >= total:
                break
        return chapters
```

- [ ] **Step 5: Re-run tests**

```bash
docker compose -f backend/docker-compose.local.yml exec fastapi \
  pytest tests/scrapers/test_mangadex_parsing.py -v
```

Expected: 5 passed (4 prior + 1 new).

- [ ] **Step 6: Commit**

```bash
git add backend/app/scrapers/comic/mangadex.py \
        backend/tests/scrapers/test_mangadex_parsing.py \
        backend/tests/scrapers/fixtures/mangadex/feed_page1.json \
        backend/tests/scrapers/fixtures/mangadex/feed_page2.json
git commit -m "[backend] AST-30 MangadexScraper.get_chapter_list with pagination + externalUrl filter"
```

---

### Task 6: `get_chapter_pages` via `/at-home/server/`

**Files:**
- Create: `backend/tests/scrapers/fixtures/mangadex/at_home_server.json`
- Modify: `backend/tests/scrapers/test_mangadex_parsing.py`
- Modify: `backend/app/scrapers/comic/mangadex.py`

- [ ] **Step 1: Save the fixture**

Create `backend/tests/scrapers/fixtures/mangadex/at_home_server.json`:

```json
{
  "result": "ok",
  "baseUrl": "https://uploads.mangadex.org",
  "chapter": {
    "hash": "abc123def",
    "data": [
      "1-page-hash.jpg",
      "2-page-hash.jpg",
      "3-page-hash.jpg"
    ],
    "dataSaver": [
      "1-saver.jpg",
      "2-saver.jpg",
      "3-saver.jpg"
    ]
  }
}
```

- [ ] **Step 2: Add the failing test**

Append to `backend/tests/scrapers/test_mangadex_parsing.py`:

```python
@pytest.fixture
def scraper_at_home(monkeypatch):
    s = MangadexScraper()

    async def fake_get(url, *, params=None, at_home=False):
        if "/at-home/server/" in url:
            assert at_home is True, "must use the at_home limiter"
            return _load("at_home_server.json")
        raise AssertionError(f"unexpected URL: {url}")

    monkeypatch.setattr(s._http, "get_json", fake_get)
    return s


async def test_get_chapter_pages_builds_full_image_urls(scraper_at_home):
    pages = await scraper_at_home.get_chapter_pages(
        "https://mangadex.org/chapter/ch-1"
    )
    assert len(pages) == 3
    assert pages[0].page_number == 1
    assert pages[0].source_url == (
        "https://uploads.mangadex.org/data/abc123def/1-page-hash.jpg"
    )
    assert pages[2].source_url == (
        "https://uploads.mangadex.org/data/abc123def/3-page-hash.jpg"
    )
```

- [ ] **Step 3: Run — confirm failure**

```bash
docker compose -f backend/docker-compose.local.yml exec fastapi \
  pytest tests/scrapers/test_mangadex_parsing.py::test_get_chapter_pages_builds_full_image_urls -v
```

Expected: `NotImplementedError: filled in Task 6`.

- [ ] **Step 4: Implement `get_chapter_pages`**

Replace the body in `backend/app/scrapers/comic/mangadex.py`:

```python
    async def get_chapter_pages(self, chapter_url: str) -> list[PageInfo]:
        chapter_id = _extract_chapter_id(chapter_url)
        body = await self._http.get_json(
            f"{_API}/at-home/server/{chapter_id}",
            at_home=True,
        )
        base_url = body["baseUrl"]
        chapter = body["chapter"]
        chapter_hash = chapter["hash"]
        filenames = chapter.get("data", [])
        return [
            PageInfo(
                page_number=i,
                source_url=f"{base_url}/data/{chapter_hash}/{fn}",
            )
            for i, fn in enumerate(filenames, start=1)
        ]
```

- [ ] **Step 5: Re-run tests**

```bash
docker compose -f backend/docker-compose.local.yml exec fastapi \
  pytest tests/scrapers/test_mangadex_parsing.py -v
```

Expected: 6 passed.

- [ ] **Step 6: Commit**

```bash
git add backend/app/scrapers/comic/mangadex.py \
        backend/tests/scrapers/test_mangadex_parsing.py \
        backend/tests/scrapers/fixtures/mangadex/at_home_server.json
git commit -m "[backend] AST-30 MangadexScraper.get_chapter_pages via at-home server"
```

---

### Task 7: `download_image` override + MD@Home report POST

**Files:**
- Modify: `backend/tests/scrapers/test_mangadex_parsing.py`
- Modify: `backend/app/scrapers/comic/mangadex.py`

- [ ] **Step 1: Add download + report tests**

Append to `backend/tests/scrapers/test_mangadex_parsing.py`:

```python
async def test_download_image_posts_success_report(monkeypatch, tmp_path):
    s = MangadexScraper()
    posts: list[dict] = []

    async def fake_fetch(url, dest_path):
        # Simulate a 50KB write.
        return dest_path, 50_000

    async def fake_post(url, *, json):
        posts.append({"url": url, "json": json})

    monkeypatch.setattr(s._http, "fetch_image_to_disk", fake_fetch)
    monkeypatch.setattr(s._http, "post_json", fake_post)

    result = await s.download_image(
        "https://uploads.mangadex.org/data/abc/1.jpg",
        "comics/story1/ch1/page_0001.jpg",
    )
    assert result == "comics/story1/ch1/page_0001.jpg"
    assert len(posts) == 1
    assert posts[0]["url"] == "https://api.mangadex.network/report"
    assert posts[0]["json"]["url"] == "https://uploads.mangadex.org/data/abc/1.jpg"
    assert posts[0]["json"]["success"] is True
    assert posts[0]["json"]["bytes"] == 50_000
    assert posts[0]["json"]["cached"] is False  # /data path → not cached
    assert "duration" in posts[0]["json"]


async def test_download_image_posts_failure_report_on_exception(monkeypatch):
    s = MangadexScraper()
    posts: list[dict] = []

    async def fake_fetch(url, dest_path):
        raise RuntimeError("simulated network failure")

    async def fake_post(url, *, json):
        posts.append({"url": url, "json": json})

    monkeypatch.setattr(s._http, "fetch_image_to_disk", fake_fetch)
    monkeypatch.setattr(s._http, "post_json", fake_post)

    with pytest.raises(RuntimeError):
        await s.download_image(
            "https://uploads.mangadex.org/data/abc/1.jpg",
            "comics/story1/ch1/page_0001.jpg",
        )
    assert len(posts) == 1
    assert posts[0]["json"]["success"] is False
    assert posts[0]["json"]["bytes"] == 0
```

- [ ] **Step 2: Run — confirm both fail (BaseScraper's download_image runs instead)**

```bash
docker compose -f backend/docker-compose.local.yml exec fastapi \
  pytest tests/scrapers/test_mangadex_parsing.py::test_download_image_posts_success_report \
         tests/scrapers/test_mangadex_parsing.py::test_download_image_posts_failure_report_on_exception -v
```

Expected: AssertionError (no posts captured) or curl_cffi error from the inherited `download_image`.

- [ ] **Step 3: Add `download_image` override to `MangadexScraper`**

Append after `get_chapter_pages` in `backend/app/scrapers/comic/mangadex.py`:

```python
    async def download_image(self, url: str, dest_path: str) -> str:
        """
        Override BaseScraper.download_image to (a) use httpx-based streaming
        and (b) POST a MD@Home report on every fetch. Report failures must
        never break a scrape — they are best-effort per ToS.
        """
        start = time.monotonic()
        # /uploads/ paths are pre-warm CDN; /data/ and /data-saver/ are MD@Home.
        cached = "/uploads/" in url
        try:
            rel_path, byte_count = await self._http.fetch_image_to_disk(url, dest_path)
            await self._http.post_json(self._http.REPORT_URL, json={
                "url": url,
                "success": True,
                "cached": cached,
                "bytes": byte_count,
                "duration": int((time.monotonic() - start) * 1000),
            })
            return rel_path
        except Exception:
            await self._http.post_json(self._http.REPORT_URL, json={
                "url": url,
                "success": False,
                "cached": cached,
                "bytes": 0,
                "duration": int((time.monotonic() - start) * 1000),
            })
            raise
```

- [ ] **Step 4: Re-run tests**

```bash
docker compose -f backend/docker-compose.local.yml exec fastapi \
  pytest tests/scrapers/test_mangadex_parsing.py -v
```

Expected: 8 passed.

- [ ] **Step 5: Commit**

```bash
git add backend/app/scrapers/comic/mangadex.py \
        backend/tests/scrapers/test_mangadex_parsing.py
git commit -m "[backend] AST-30 MangadexScraper.download_image with MD@Home report POST"
```

---

### Task 8: ToS audit test (AST walk)

**Files:**
- Create: `backend/tests/scrapers/test_mangadex_tos_audit.py`

- [ ] **Step 1: Write the audit**

Create `backend/tests/scrapers/test_mangadex_tos_audit.py`:

```python
"""
Static guard: every download_image call path in mangadex.py must invoke
post_json (the MD@Home report). Prevents future refactors from silently
dropping the ToS-required report.
"""
import ast
import pathlib

MANGADEX_PY = pathlib.Path(__file__).resolve().parents[2] / "app" / "scrapers" / "comic" / "mangadex.py"


def _get_func(tree: ast.AST, class_name: str, method_name: str) -> ast.FunctionDef:
    for node in ast.walk(tree):
        if isinstance(node, ast.ClassDef) and node.name == class_name:
            for item in node.body:
                if isinstance(item, ast.AsyncFunctionDef) and item.name == method_name:
                    return item
    raise AssertionError(f"{class_name}.{method_name} not found in {MANGADEX_PY}")


def _calls_to(func: ast.FunctionDef, attr: str) -> list[ast.Call]:
    return [
        node for node in ast.walk(func)
        if isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr == attr
    ]


def test_download_image_calls_post_json_in_both_branches():
    tree = ast.parse(MANGADEX_PY.read_text())
    fn = _get_func(tree, "MangadexScraper", "download_image")

    # Find the try block; assert post_json is called inside both the try (success)
    # and except (failure) branches.
    try_blocks = [n for n in ast.walk(fn) if isinstance(n, ast.Try)]
    assert try_blocks, "download_image must use try/except for report POST"
    tb = try_blocks[0]

    success_posts = [
        c for n in tb.body for c in ast.walk(n)
        if isinstance(c, ast.Call) and isinstance(c.func, ast.Attribute)
        and c.func.attr == "post_json"
    ]
    failure_posts = [
        c for handler in tb.handlers for n in handler.body for c in ast.walk(n)
        if isinstance(c, ast.Call) and isinstance(c.func, ast.Attribute)
        and c.func.attr == "post_json"
    ]
    assert success_posts, "post_json missing on success branch of download_image"
    assert failure_posts, "post_json missing on failure branch of download_image"
```

- [ ] **Step 2: Run — should pass against the Task-7 implementation**

```bash
docker compose -f backend/docker-compose.local.yml exec fastapi \
  pytest tests/scrapers/test_mangadex_tos_audit.py -v
```

Expected: 1 passed.

- [ ] **Step 3: Commit**

```bash
git add backend/tests/scrapers/test_mangadex_tos_audit.py
git commit -m "[backend] AST-30 add ToS audit test for MD@Home report POST"
```

---

### Task 9: `MangadexScraper.search` + matcher service

**Files:**
- Create: `backend/tests/scrapers/fixtures/mangadex/search_results.json`
- Modify: `backend/app/scrapers/comic/mangadex.py`
- Create: `backend/app/services/mangadex_matcher.py`
- Create: `backend/tests/services/__init__.py` (if missing)
- Create: `backend/tests/services/test_mangadex_matcher.py`

- [ ] **Step 1: Save search-results fixture**

Create `backend/tests/scrapers/fixtures/mangadex/search_results.json`:

```json
{
  "result": "ok",
  "data": [
    {
      "id": "match-1",
      "type": "manga",
      "attributes": {
        "title": {"en": "Solo Leveling"},
        "originalLanguage": "ko",
        "lastChapter": "179",
        "tags": [
          {"id": "t1", "type": "tag", "attributes": {"name": {"en": "Action"}, "group": "genre"}},
          {"id": "t2", "type": "tag", "attributes": {"name": {"en": "Adventure"}, "group": "genre"}}
        ]
      },
      "relationships": [
        {"id": "c1", "type": "cover_art", "attributes": {"fileName": "cover.jpg"}}
      ]
    },
    {
      "id": "match-2",
      "type": "manga",
      "attributes": {
        "title": {"en": "Solo Leveling Side Story"},
        "originalLanguage": "ko",
        "lastChapter": "20",
        "tags": []
      },
      "relationships": []
    }
  ]
}
```

- [ ] **Step 2: Implement `MangadexScraper.search`**

Replace the `search` stub in `backend/app/scrapers/comic/mangadex.py` with:

```python
    async def search(
        self, *, title: str, content_ratings: list[str], limit: int = 10,
    ) -> list[dict]:
        """Return a flat list of {id, title, original_language, last_chapter,
        tags, thumbnail_url} dicts."""
        body = await self._http.get_json(
            f"{_API}/manga",
            params={
                "title": title,
                "limit": limit,
                "contentRating[]": content_ratings,
                "includes[]": ["cover_art"],
                "order[relevance]": "desc",
            },
        )
        out: list[dict] = []
        for entry in body.get("data", []):
            attrs = entry.get("attributes", {})
            cover_filename = None
            for rel in entry.get("relationships", []):
                if rel.get("type") == "cover_art":
                    cover_filename = (rel.get("attributes") or {}).get("fileName")
            try:
                last_chapter_int = int(float(attrs.get("lastChapter") or 0))
            except (TypeError, ValueError):
                last_chapter_int = 0
            out.append({
                "id": entry["id"],
                "title": _english_title(attrs.get("title", {})),
                "original_language": attrs.get("originalLanguage"),
                "last_chapter": last_chapter_int,
                "tags": [
                    _english_title((t.get("attributes") or {}).get("name", {}))
                    for t in attrs.get("tags", [])
                ],
                "thumbnail_url": (
                    f"https://uploads.mangadex.org/covers/{entry['id']}/{cover_filename}.512.jpg"
                    if cover_filename else None
                ),
            })
        return out
```

- [ ] **Step 3: Create the matcher service file**

Create `backend/app/services/mangadex_matcher.py`:

```python
"""
MangaDex title matcher (AST-30).

Scores a candidate match between a toongod/hentai20 series and a MangaDex
search result. Pure scoring service — no DB writes.

Score formula (sums to 1.0):
    0.55 × title similarity (rapidfuzz token_set_ratio / 100)
    0.15 × original-language match (1.0 if matches expected for source)
    0.15 × tag Jaccard overlap
    0.15 × chapter-count delta within ±20%

Threshold: settings.mangadex_title_match_threshold (default 0.85).
"""
import logging
import re
import unicodedata
from dataclasses import asdict, dataclass
from typing import Optional

from rapidfuzz import fuzz

from app.core.config import settings
from app.scrapers.comic.mangadex import MangadexScraper

logger = logging.getLogger(__name__)

_EXPECTED_LANG = {
    "toongod": "ko",
    "hentai20": "ja",
}

_NORMALIZE_DROP = re.compile(r"\b(vol(?:ume)?\.?|ch(?:apter)?\.?|ep(?:isode)?\.?|\d+)\b", re.I)
_NON_ALNUM = re.compile(r"[^a-z0-9 ]+")
_MULTI_WS = re.compile(r"\s+")


@dataclass
class MangaDexMatch:
    manga_id: str
    mangadex_url: str
    title: str
    confidence: float
    thumbnail_url: Optional[str]
    chapter_count: int
    source_chapter_count: int

    def to_dict(self) -> dict:
        return asdict(self)


def _normalize(s: str) -> str:
    if not s:
        return ""
    s = unicodedata.normalize("NFKD", s)
    s = "".join(c for c in s if not unicodedata.combining(c))
    s = s.lower()
    s = _NORMALIZE_DROP.sub(" ", s)
    s = _NON_ALNUM.sub(" ", s)
    s = _MULTI_WS.sub(" ", s).strip()
    return s


def _score(
    candidate: dict,
    *,
    source_title: str,
    expected_lang: Optional[str],
    source_tags: set[str],
    source_chapter_count: int,
) -> float:
    title_sim = (
        fuzz.token_set_ratio(_normalize(source_title), _normalize(candidate["title"])) / 100.0
    )
    lang_match = 1.0 if (
        expected_lang and candidate.get("original_language") == expected_lang
    ) else 0.0
    md_tags = {t.lower() for t in candidate.get("tags", []) if t}
    src_tags_lc = {t.lower() for t in source_tags if t}
    if not md_tags and not src_tags_lc:
        tag_jaccard = 0.0
    else:
        union = md_tags | src_tags_lc
        tag_jaccard = (len(md_tags & src_tags_lc) / len(union)) if union else 0.0
    md_chapter_count = candidate.get("last_chapter", 0) or 0
    if source_chapter_count > 0 and md_chapter_count > 0:
        delta_pct = abs(md_chapter_count - source_chapter_count) / source_chapter_count
        chapter_match = 1.0 if delta_pct <= 0.20 else 0.0
    else:
        chapter_match = 0.0
    return (
        0.55 * title_sim
        + 0.15 * lang_match
        + 0.15 * tag_jaccard
        + 0.15 * chapter_match
    )


async def find_mangadex_match(
    *,
    source: str,
    source_url: str,
    source_title: str,
) -> Optional[MangaDexMatch]:
    """Return a MangaDexMatch if best score ≥ threshold, else None."""
    if settings.mangadex_disabled:
        logger.info("find_mangadex_match skipped — kill switch on")
        return None
    if not settings.mangadex_auto_switch_source:
        logger.info("find_mangadex_match skipped — auto-switch disabled")
        return None
    if source not in _EXPECTED_LANG:
        logger.debug("find_mangadex_match skipped — source %s not eligible", source)
        return None

    # Fetch source-side metadata (tags + chapter count) using the existing scraper
    # registry. Imported here to avoid circular import at module load.
    from app.tasks.comic_scrape_task import SCRAPER_REGISTRY

    source_scraper_cls = SCRAPER_REGISTRY.get(source)
    if source_scraper_cls is None:
        logger.warning("find_mangadex_match: no scraper registered for %s", source)
        return None
    try:
        src_meta = await source_scraper_cls().get_story_metadata(source_url)
    except Exception as e:
        logger.warning("find_mangadex_match source meta fetch failed | err=%s", e)
        return None

    src_tags = {t.get("name", "") for t in (src_meta.tags or [])}
    src_chapter_count = src_meta.total_chapters or 0

    md = MangadexScraper()
    try:
        candidates = await md.search(
            title=_normalize(source_title) or source_title,
            content_ratings=["safe", "suggestive", "erotica"],
            limit=10,
        )
    except Exception as e:
        logger.warning("find_mangadex_match mangadex search failed | err=%s", e)
        return None

    best: Optional[tuple[float, dict]] = None
    for c in candidates:
        s = _score(
            c,
            source_title=source_title,
            expected_lang=_EXPECTED_LANG[source],
            source_tags=src_tags,
            source_chapter_count=src_chapter_count,
        )
        if best is None or s > best[0]:
            best = (s, c)

    if best is None or best[0] < settings.mangadex_title_match_threshold:
        logger.info(
            "find_mangadex_match no qualifying match | source=%s best=%.3f",
            source, best[0] if best else 0.0,
        )
        return None

    score, cand = best
    return MangaDexMatch(
        manga_id=cand["id"],
        mangadex_url=f"https://mangadex.org/title/{cand['id']}",
        title=cand["title"],
        confidence=round(score, 3),
        thumbnail_url=cand.get("thumbnail_url"),
        chapter_count=cand.get("last_chapter", 0) or 0,
        source_chapter_count=src_chapter_count,
    )
```

- [ ] **Step 4: Write matcher tests**

Create `backend/tests/services/__init__.py` if missing:

```bash
[ -f backend/tests/services/__init__.py ] || touch backend/tests/services/__init__.py
```

Create `backend/tests/services/test_mangadex_matcher.py`:

```python
"""
Unit tests for the MangaDex matcher's scoring + decision logic.
"""
import pytest

from app.scrapers.base import StoryMetadata
from app.services import mangadex_matcher
from app.services.mangadex_matcher import (
    MangaDexMatch,
    _normalize,
    _score,
    find_mangadex_match,
)


def test_normalize_strips_diacritics_and_volume_markers():
    assert _normalize("Solo Leveling Vol. 1 Chapter 5") == "solo leveling"
    assert _normalize("Café Naïve!") == "cafe naive"
    assert _normalize("") == ""


def test_score_strong_match_passes_threshold():
    candidate = {
        "id": "x",
        "title": "Solo Leveling",
        "original_language": "ko",
        "last_chapter": 179,
        "tags": ["Action", "Adventure"],
    }
    s = _score(
        candidate,
        source_title="Solo Leveling",
        expected_lang="ko",
        source_tags={"Action", "Adventure"},
        source_chapter_count=180,
    )
    assert s >= 0.85


def test_score_title_alone_below_threshold():
    candidate = {
        "id": "x",
        "title": "Solo Leveling",
        "original_language": "en",       # wrong lang
        "last_chapter": 0,                # no chapter info
        "tags": [],
    }
    s = _score(
        candidate,
        source_title="Solo Leveling",
        expected_lang="ko",
        source_tags=set(),
        source_chapter_count=0,
    )
    # Title sim = 1.0, weight 0.55 → at most 0.55. Below threshold.
    assert s < 0.85


def test_score_chapter_delta_outside_20pct_loses_chapter_signal():
    candidate = {
        "id": "x",
        "title": "Different Title",
        "original_language": "ko",
        "last_chapter": 100,
        "tags": [],
    }
    s = _score(
        candidate,
        source_title="Different Title",
        expected_lang="ko",
        source_tags=set(),
        source_chapter_count=200,  # 100/200 → 50% delta → no chapter signal
    )
    # title 0.55 + lang 0.15 + tags 0 + chapter 0 → 0.70
    assert 0.69 < s < 0.71


@pytest.fixture
def patch_settings(monkeypatch):
    from app.core.config import settings
    monkeypatch.setattr(settings, "mangadex_disabled", False)
    monkeypatch.setattr(settings, "mangadex_auto_switch_source", True)
    monkeypatch.setattr(settings, "mangadex_title_match_threshold", 0.85)


@pytest.fixture
def patch_search(monkeypatch):
    """Replace MangadexScraper.search with a fake that returns canned candidates."""
    canned: list[dict] = []
    async def fake_search(self, *, title, content_ratings, limit=10):
        return canned
    from app.scrapers.comic.mangadex import MangadexScraper
    monkeypatch.setattr(MangadexScraper, "search", fake_search)
    return canned


@pytest.fixture
def patch_source_scraper(monkeypatch):
    """Replace the toongod scraper's get_story_metadata with a stub."""
    async def fake_meta(self, url):
        return StoryMetadata(
            title="Solo Leveling",
            source_url=url,
            source_key="toongod",
            tags=[{"name": "Action", "tag_type": "genre"}],
            total_chapters=180,
        )
    from app.scrapers.comic.toongod import ToongodScraper
    monkeypatch.setattr(ToongodScraper, "get_story_metadata", fake_meta)


async def test_find_match_returns_match_when_threshold_met(
    patch_settings, patch_search, patch_source_scraper,
):
    patch_search.append({
        "id": "abc",
        "title": "Solo Leveling",
        "original_language": "ko",
        "last_chapter": 179,
        "tags": ["Action", "Adventure"],
        "thumbnail_url": "https://uploads.mangadex.org/covers/abc/c.jpg.512.jpg",
    })
    match = await find_mangadex_match(
        source="toongod",
        source_url="https://toongod.org/manga/x/",
        source_title="Solo Leveling",
    )
    assert match is not None
    assert match.manga_id == "abc"
    assert match.confidence >= 0.85
    assert match.mangadex_url == "https://mangadex.org/title/abc"


async def test_find_match_returns_none_below_threshold(
    patch_settings, patch_search, patch_source_scraper,
):
    patch_search.append({
        "id": "abc",
        "title": "Completely Different Series",
        "original_language": "en",
        "last_chapter": 5,
        "tags": [],
        "thumbnail_url": None,
    })
    match = await find_mangadex_match(
        source="toongod",
        source_url="https://toongod.org/manga/x/",
        source_title="Solo Leveling",
    )
    assert match is None


async def test_find_match_skipped_when_kill_switch_on(monkeypatch, patch_search):
    from app.core.config import settings
    monkeypatch.setattr(settings, "mangadex_disabled", True)
    match = await find_mangadex_match(
        source="toongod",
        source_url="https://toongod.org/manga/x/",
        source_title="Anything",
    )
    assert match is None


async def test_find_match_skipped_for_ineligible_source(patch_settings, patch_search):
    match = await find_mangadex_match(
        source="nhentai",
        source_url="https://nhentai.net/g/1",
        source_title="Anything",
    )
    assert match is None
```

- [ ] **Step 5: Run all matcher and parsing tests**

```bash
docker compose -f backend/docker-compose.local.yml exec fastapi \
  pytest tests/services/test_mangadex_matcher.py tests/scrapers/test_mangadex_parsing.py -v
```

Expected: all pass (8 parsing + 8 matcher = 16 total).

- [ ] **Step 6: Commit**

```bash
git add backend/app/scrapers/comic/mangadex.py \
        backend/app/services/mangadex_matcher.py \
        backend/tests/scrapers/fixtures/mangadex/search_results.json \
        backend/tests/services/test_mangadex_matcher.py \
        backend/tests/services/__init__.py
git commit -m "[backend] AST-30 add MangaDex matcher service + scraper.search"
```

---

### Task 10: Alembic migration — three nullable columns on `comics`

**Files:**
- Create: `backend/alembic/versions/f2a3b4c5d6e7_add_comic_mangadex_swap_columns.py`
- Modify: `backend/app/models/comic.py`

- [ ] **Step 1: Create the migration file**

Create `backend/alembic/versions/f2a3b4c5d6e7_add_comic_mangadex_swap_columns.py`:

```python
"""add comic mangadex swap columns

Revision ID: f2a3b4c5d6e7
Revises: e1f2a3b4c5d6
Create Date: 2026-04-19 22:00:00.000000

"""
from alembic import op
import sqlalchemy as sa


revision = "f2a3b4c5d6e7"
down_revision = "e1f2a3b4c5d6"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "comics",
        sa.Column("previous_source", sa.String(length=50), nullable=True),
    )
    op.add_column(
        "comics",
        sa.Column("previous_source_url", sa.String(length=2000), nullable=True),
    )
    op.add_column(
        "comics",
        sa.Column("match_confidence", sa.Float(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("comics", "match_confidence")
    op.drop_column("comics", "previous_source_url")
    op.drop_column("comics", "previous_source")
```

- [ ] **Step 2: Add the columns to the ORM model**

In `backend/app/models/comic.py`, append three new mapped columns to the `Comic` class — insert after the existing `archive_status` line (line 29):

```python
    archive_status: Mapped[str] = mapped_column(String(20), nullable=False, default="none", server_default="none")
    # MangaDex source-swap audit trail (AST-30)
    previous_source: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
    previous_source_url: Mapped[Optional[str]] = mapped_column(String(2000), nullable=True)
    match_confidence: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
```

- [ ] **Step 3: Apply migration to local DB**

The `alembic` CLI is not bundled in the fastapi container per CLAUDE.md notes. Apply via direct SQL on the postgres container:

```bash
docker exec backend-postgres-1 psql -U astral -d astral -c \
  "ALTER TABLE comics
   ADD COLUMN previous_source VARCHAR(50),
   ADD COLUMN previous_source_url VARCHAR(2000),
   ADD COLUMN match_confidence DOUBLE PRECISION;"

docker exec backend-postgres-1 psql -U astral -d astral -c \
  "UPDATE alembic_version SET version_num = 'f2a3b4c5d6e7';"
```

Verify:

```bash
docker exec backend-postgres-1 psql -U astral -d astral -c \
  "SELECT column_name FROM information_schema.columns
   WHERE table_name = 'comics' AND column_name LIKE 'previous%' OR column_name = 'match_confidence';"
```

Expected: 3 rows.

- [ ] **Step 4: Confirm ORM still reads cleanly**

```bash
docker compose -f backend/docker-compose.local.yml exec fastapi \
  python -c "from app.models.comic import Comic; print([c.name for c in Comic.__table__.columns if 'previous' in c.name or c.name == 'match_confidence'])"
```

Expected: `['previous_source', 'previous_source_url', 'match_confidence']`.

- [ ] **Step 5: Commit**

```bash
git add backend/alembic/versions/f2a3b4c5d6e7_add_comic_mangadex_swap_columns.py \
        backend/app/models/comic.py
git commit -m "[backend] AST-30 add Comic columns previous_source/previous_source_url/match_confidence"
```

---

### Task 11: Extend `ScrapeRequest` schema + `scrape_service.initiate_scrape`

**Files:**
- Modify: `backend/app/schemas/scrape.py`
- Modify: `backend/app/services/scrape_service.py`

- [ ] **Step 1: Extend `ScrapeRequest` and add response schemas**

Replace the `ScrapeRequest` class in `backend/app/schemas/scrape.py` and append two new ones:

```python
class ScrapeRequest(BaseModel):
    url: str
    source_key: str
    cookies: list[CookieDTO]
    user_agent: str
    content_type: str = "comic"
    # AST-30 — MangaDex matcher fields. All optional, ignored for ineligible sources.
    page_title: Optional[str] = None
    skip_match: bool = False
    previous_source: Optional[str] = None
    previous_source_url: Optional[str] = None
    match_confidence: Optional[float] = None


class MangaDexMatchPayload(BaseModel):
    manga_id: str
    mangadex_url: str
    title: str
    confidence: float
    thumbnail_url: Optional[str] = None
    chapter_count: int
    source_chapter_count: int


class ScrapeMatchResponse(BaseModel):
    match: MangaDexMatchPayload
```

- [ ] **Step 2: Pass new fields through `initiate_scrape`**

In `backend/app/services/scrape_service.py`, modify the comic-creation block (around lines 67–83) to set the three new columns on a freshly-created Comic:

Find:

```python
        else:
            comic = Comic(
                id=story_id,
                title="Pending scrape...",
                source_key=body.source_key,
                source_url=body.url,
            )
            db.add(comic)
            logger.info("initiate_scrape new comic placeholder created | story_id=%s", story_id)
```

Replace with:

```python
        else:
            comic = Comic(
                id=story_id,
                title="Pending scrape...",
                source_key=body.source_key,
                source_url=body.url,
                previous_source=body.previous_source,
                previous_source_url=body.previous_source_url,
                match_confidence=body.match_confidence,
            )
            db.add(comic)
            logger.info(
                "initiate_scrape new comic placeholder created | story_id=%s prev=%s conf=%s",
                story_id, body.previous_source, body.match_confidence,
            )
```

- [ ] **Step 3: Smoke-test schema construction**

```bash
docker compose -f backend/docker-compose.local.yml exec fastapi python -c "
from app.schemas.scrape import ScrapeRequest, MangaDexMatchPayload, ScrapeMatchResponse
r = ScrapeRequest(url='x', source_key='toongod', cookies=[], user_agent='ua', content_type='comic',
                  page_title='t', skip_match=True, previous_source='toongod',
                  previous_source_url='https://toongod.org/x', match_confidence=0.91)
print('ok:', r.skip_match, r.match_confidence)
m = ScrapeMatchResponse(match=MangaDexMatchPayload(manga_id='id', mangadex_url='u', title='t',
                                                    confidence=0.9, chapter_count=10, source_chapter_count=12))
print('match ok:', m.match.title)
"
```

Expected: `ok: True 0.91` then `match ok: t`.

- [ ] **Step 4: Commit**

```bash
git add backend/app/schemas/scrape.py backend/app/services/scrape_service.py
git commit -m "[backend] AST-30 extend ScrapeRequest with matcher fields + persist on Comic"
```

---

### Task 12: Wire matcher hook into `POST /scrape/comic` + 503 kill switch

**Files:**
- Modify: `backend/app/api/v1/routes/scrape.py`
- Create: `backend/tests/api/__init__.py` (if missing)
- Create: `backend/tests/api/test_scrape_router_mangadex.py`

- [ ] **Step 1: Update the route handler**

Replace the `initiate_comic_scrape` handler in `backend/app/api/v1/routes/scrape.py` (lines 13–16) with:

```python
@router.post(
    "/comic",
    responses={
        202: {"description": "Scrape job created OR MangaDex match proposed (distinguished by response body shape)"},
        503: {"description": "MangaDex disabled (kill switch)"},
    },
)
async def initiate_comic_scrape(body: ScrapeRequest, db: AsyncSession = Depends(get_db)):
    from fastapi.responses import JSONResponse
    from app.core.config import settings
    from app.services.mangadex_matcher import find_mangadex_match

    body_with_type = body.model_copy(update={"content_type": "comic"})

    # Kill switch: hard-stop direct MangaDex scrapes.
    if body_with_type.source_key == "mangadex" and settings.mangadex_disabled:
        return JSONResponse(
            status_code=503,
            content={"detail": "MangaDex temporarily disabled"},
        )

    # Matcher hook: only for eligible sources, only if user hasn't opted out, only if alive.
    if (
        body_with_type.source_key in ("toongod", "hentai20")
        and not body_with_type.skip_match
        and not settings.mangadex_disabled
    ):
        match = await find_mangadex_match(
            source=body_with_type.source_key,
            source_url=body_with_type.url,
            source_title=body_with_type.page_title or body_with_type.url,
        )
        if match is not None:
            return JSONResponse(
                status_code=202,
                content={"match": match.to_dict()},
            )

    # Normal path: create job + enqueue.
    return await scrape_service.initiate_scrape(db, body_with_type)
```

(Note: both the match envelope and the job-created response use 202. iOS distinguishes by body shape — `submitScrape` in Task 18 tries the match-envelope decode first and falls back to `ScrapeJobResponse`. Spec consistency: see [spec § 3](../specs/2026-04-19-ast30-mangadex-source-design.md).)

- [ ] **Step 2: Write API behavior tests**

Create `backend/tests/api/__init__.py` if missing:

```bash
[ -f backend/tests/api/__init__.py ] || touch backend/tests/api/__init__.py
```

Create `backend/tests/api/test_scrape_router_mangadex.py`:

```python
"""
API-level tests for the matcher hook on POST /scrape/comic.

Uses the existing fastapi TestClient setup if present in tests/conftest.py;
otherwise falls back to constructing the app directly.
"""
import pytest
from httpx import AsyncClient, ASGITransport

from app.main import app
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


@pytest.fixture
async def client():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as c:
        yield c


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
        "app.api.v1.routes.scrape.find_mangadex_match", fake_match,
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
        "app.api.v1.routes.scrape.find_mangadex_match", fake_match,
    )
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
        "app.api.v1.routes.scrape.find_mangadex_match", fake_match,
    )
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
```

- [ ] **Step 3: Run API tests**

```bash
docker compose -f backend/docker-compose.local.yml exec fastapi \
  pytest tests/api/test_scrape_router_mangadex.py -v
```

Expected: 4 passed.

- [ ] **Step 4: Commit**

```bash
git add backend/app/api/v1/routes/scrape.py \
        backend/tests/api/test_scrape_router_mangadex.py \
        backend/tests/api/__init__.py
git commit -m "[backend] AST-30 wire MangaDex matcher hook + 503 kill switch into /scrape/comic"
```

---

### Task 13: Register `MangadexScraper` in `SCRAPER_REGISTRY`

**Files:**
- Modify: `backend/app/tasks/comic_scrape_task.py`

- [ ] **Step 1: Add the import + registry entry**

In `backend/app/tasks/comic_scrape_task.py`, add the import next to existing scrapers (line 18 area):

```python
from app.scrapers.comic.hentai20 import Hentai20Scraper
from app.scrapers.comic.mangadex import MangadexScraper  # AST-30
```

Update `SCRAPER_REGISTRY` (lines 22–26):

```python
SCRAPER_REGISTRY = {
    "nhentai": NhentaiScraper,
    "toongod": ToongodScraper,
    "hentai20": Hentai20Scraper,
    "mangadex": MangadexScraper,
}
```

- [ ] **Step 2: Smoke-check registration**

```bash
docker compose -f backend/docker-compose.local.yml exec fastapi python -c "
from app.tasks.comic_scrape_task import SCRAPER_REGISTRY
assert 'mangadex' in SCRAPER_REGISTRY
print('registered:', SCRAPER_REGISTRY['mangadex'].__name__)
"
```

Expected: `registered: MangadexScraper`.

- [ ] **Step 3: Restart the worker so the new registry entry takes effect**

```bash
docker compose -f backend/docker-compose.local.yml restart arq_worker
docker compose -f backend/docker-compose.local.yml logs arq_worker --tail 20
```

Expected: worker restarts cleanly, no import errors.

- [ ] **Step 4: Commit**

```bash
git add backend/app/tasks/comic_scrape_task.py
git commit -m "[backend] AST-30 register MangadexScraper in comic SCRAPER_REGISTRY"
```

---

### Task 14: Update CLAUDE.md with MangaDex env-var docs

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add a short section under Backend Notes**

In `CLAUDE.md`, find the "Backend Notes" section (around line 50). Append after the existing bullets:

```markdown
- MangaDex source (AST-30) — env vars:
  - `MANGADEX_DISABLED=true|false` — kill switch. Hard-stops new mangadex scrapes (HTTP 503), silently disables the matcher for toongod/hentai20 adds.
  - `MANGADEX_TITLE_MATCH_THRESHOLD=0.85` — minimum confidence for the match-confirm dialog.
  - `MANGADEX_AUTO_SWITCH_SOURCE=true|false` — master toggle for the matcher.
  - OAuth2 personal-client login for the `pornographic` content rating is tracked in AST-35 (not in v1).
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "[docs] AST-30 document MangaDex env vars in CLAUDE.md"
```

---

### Task 15: iOS — add `.mangadex` to `ComicSource` + cookie domain

**Files:**
- Modify: `ios/Astral/Packages/Core/Sources/Core/Utilities/ContentType.swift`
- Modify: `ios/Astral/Packages/Networking/Sources/Networking/CookieStore.swift`

- [ ] **Step 1: Add the enum case**

In `ios/Astral/Packages/Core/Sources/Core/Utilities/ContentType.swift`, replace lines 35–39:

```swift
public enum ComicSource: String, CaseIterable, Codable, Sendable {
    case nhentai
    case toongod
    case hentai20
    case mangadex
}
```

- [ ] **Step 2: Add the cookie domain mapping**

In `ios/Astral/Packages/Networking/Sources/Networking/CookieStore.swift`, replace the `sourceDomains` dict (lines 13–19):

```swift
    private let sourceDomains: [String: String] = [
        "nhentai": "nhentai.net",
        "toongod": "toongod.org",
        "hentai20": "hentai20.io",
        "ao3": "archiveofourown.org",
        "ffnet": "fanfiction.net",
        "mangadex": "mangadex.org",
    ]
```

- [ ] **Step 3: Build to confirm no compile errors elsewhere**

```bash
cd ios/Astral && xcodebuild -scheme Astral \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' \
  build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`. Any unhandled `case .mangadex:` in switches will be caught here and addressed in subsequent tasks.

- [ ] **Step 4: Commit**

```bash
git add ios/Astral/Packages/Core/Sources/Core/Utilities/ContentType.swift \
        ios/Astral/Packages/Networking/Sources/Networking/CookieStore.swift
git commit -m "[ios] AST-30 add ComicSource.mangadex + cookie domain mapping"
```

---

### Task 16: iOS — add MangaDex to comic browser + card icon

**Files:**
- Modify: `ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/ComicBrowserView.swift`
- Modify: `ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicCardView.swift`

- [ ] **Step 1: Add the icon case**

In `ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicCardView.swift`, replace the `sourceIcon` switch (lines 20–27):

```swift
    private var sourceIcon: String {
        switch comic.sourceKey {
        case "nhentai": "n.square.fill"
        case "toongod": "t.square.fill"
        case "hentai20": "h.square.fill"
        case "mangadex": "m.square.fill"
        default: "questionmark.square.fill"
        }
    }
```

- [ ] **Step 2: Add MangaDex to `allowedDomains`, `sourceURL`, `evaluateCanScrape`, `resetToSourceHome`**

In `ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/ComicBrowserView.swift`:

Replace `allowedDomains` (lines 154–160):

```swift
    var allowedDomains: [String] {
        switch selectedSource {
        case .nhentai: return ["nhentai.net", "nhentai.to"]
        case .toongod: return ["toongod.org", "toongod.com"]
        case .hentai20: return ["hentai20.io"]
        case .mangadex: return ["mangadex.org"]
        }
    }
```

Replace `sourceURL` (lines 172–181):

```swift
    var sourceURL: URL {
        if let saved = savedURLs[selectedSource] {
            return saved
        }
        switch selectedSource {
        case .nhentai: return URL(string: "https://nhentai.net")!
        case .toongod: return URL(string: "https://www.toongod.org")!
        case .hentai20: return URL(string: "https://hentai20.io")!
        case .mangadex: return URL(string: "https://mangadex.org")!
        }
    }
```

Replace `evaluateCanScrape` (lines 242–256):

```swift
    func evaluateCanScrape(url: URL?) {
        guard let url = url else {
            canScrape = false
            return
        }
        let path = url.path
        switch selectedSource {
        case .nhentai:
            canScrape = path.contains("/g/")
        case .toongod:
            canScrape = path.contains("/manga/") || path.contains("/webtoon/")
        case .hentai20:
            canScrape = path.contains("/manga/")
        case .mangadex:
            canScrape = path.contains("/title/")
        }
    }
```

Replace `resetToSourceHome` (lines 262–272):

```swift
    func resetToSourceHome() {
        savedURLs.removeValue(forKey: selectedSource)
        let homeURL: URL
        switch selectedSource {
        case .nhentai: homeURL = URL(string: "https://nhentai.net")!
        case .toongod: homeURL = URL(string: "https://www.toongod.org")!
        case .hentai20: homeURL = URL(string: "https://hentai20.io")!
        case .mangadex: homeURL = URL(string: "https://mangadex.org")!
        }
        webView?.load(URLRequest(url: homeURL))
        addressBarText = homeURL.absoluteString
    }
```

- [ ] **Step 3: Re-build to confirm**

```bash
cd ios/Astral && xcodebuild -scheme Astral \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' \
  build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/ComicBrowserView.swift \
        ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicCardView.swift
git commit -m "[ios] AST-30 add MangaDex to comic browser tabs + card icon"
```

---

### Task 17: iOS — add `previousSource`, `previousSourceURL`, `matchConfidence` to `LocalComic`

**Files:**
- Modify: `ios/Astral/Packages/Core/Sources/Core/Models/LocalComic.swift`

- [ ] **Step 1: Add three optional properties**

In `ios/Astral/Packages/Core/Sources/Core/Models/LocalComic.swift`, append three new properties — insert before `@Relationship` (line 50):

```swift
    /// AST-30 — if this comic was added via the MangaDex matcher, the original
    /// source key the user pasted from (e.g. "toongod"). Nil otherwise.
    public var previousSource: String?
    /// AST-30 — original source URL before the swap, kept for debugging /
    /// re-scrape from the original if MangaDex coverage is incomplete.
    public var previousSourceURL: String?
    /// AST-30 — matcher confidence score that triggered the swap, e.g. 0.91.
    public var matchConfidence: Double?

    @Relationship(deleteRule: .cascade, inverse: \LocalComicChapter.comic)
    public var chapters: [LocalComicChapter]?
```

The init signature stays as-is — existing call sites continue to compile, and the new properties default to `nil`.

- [ ] **Step 2: Build to confirm SwiftData lightweight migration succeeds**

```bash
cd ios/Astral && xcodebuild -scheme Astral \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' \
  build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`. (Adding optional `@Model` properties triggers automatic lightweight migration on iOS 17.2.)

- [ ] **Step 3: Commit**

```bash
git add ios/Astral/Packages/Core/Sources/Core/Models/LocalComic.swift
git commit -m "[ios] AST-30 add previousSource/previousSourceURL/matchConfidence to LocalComic"
```

---

### Task 18: iOS — extend `ScrapeRequest` DTO + add `MangaDexMatchPayload` + `submitScrape`

**Files:**
- Modify: `ios/Astral/Packages/Networking/Sources/Networking/DTOs/ScrapeDTOs.swift`
- Modify: `ios/Astral/Packages/Networking/Sources/Networking/APIClient.swift`

- [ ] **Step 1: Extend `ScrapeRequest` and add the match types**

Replace the `ScrapeRequest` struct in `ios/Astral/Packages/Networking/Sources/Networking/DTOs/ScrapeDTOs.swift` and append the new types:

```swift
public struct ScrapeRequest: Codable, Sendable {
    public let url: String
    public let sourceKey: String
    public let cookies: [CookieDTO]
    public let userAgent: String
    public let contentType: String
    // AST-30 — MangaDex matcher fields. All optional; ignored on backend
    // for ineligible sources.
    public let pageTitle: String?
    public let skipMatch: Bool
    public let previousSource: String?
    public let previousSourceUrl: String?
    public let matchConfidence: Double?

    public init(
        url: String,
        sourceKey: String,
        cookies: [CookieDTO],
        userAgent: String,
        contentType: String,
        pageTitle: String? = nil,
        skipMatch: Bool = false,
        previousSource: String? = nil,
        previousSourceUrl: String? = nil,
        matchConfidence: Double? = nil
    ) {
        self.url = url
        self.sourceKey = sourceKey
        self.cookies = cookies
        self.userAgent = userAgent
        self.contentType = contentType
        self.pageTitle = pageTitle
        self.skipMatch = skipMatch
        self.previousSource = previousSource
        self.previousSourceUrl = previousSourceUrl
        self.matchConfidence = matchConfidence
    }
}

public struct MangaDexMatchPayload: Codable, Sendable, Equatable {
    public let mangaId: String
    public let mangadexUrl: String
    public let title: String
    public let confidence: Double
    public let thumbnailUrl: String?
    public let chapterCount: Int
    public let sourceChapterCount: Int
}

public struct ScrapeMatchResponse: Codable, Sendable {
    public let match: MangaDexMatchPayload
}

public enum ScrapeOutcome: Sendable {
    case jobCreated(ScrapeJobResponse)
    case matchProposed(MangaDexMatchPayload)
}
```

- [ ] **Step 2: Add the `submitScrape` method to `APIClient`**

Append a new method to the `APIClient` actor in `ios/Astral/Packages/Networking/Sources/Networking/APIClient.swift` — inside the actor body, after `requestVoid`:

```swift
    /// AST-30 — submits a scrape request and decodes either a job-created or
    /// match-proposed response based on body shape. Both come back as 2xx.
    public func submitScrape(_ request: ScrapeRequest) async throws -> ScrapeOutcome {
        let endpoint = Endpoint.initiateScrape(request)
        let urlRequest = try endpoint.urlRequest()
        let method = urlRequest.httpMethod ?? "POST"
        let path = urlRequest.url?.path ?? "?"
        let start = CFAbsoluteTimeGetCurrent()

        AstralLogger.network("\(method) \(path) →")

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        let status = httpResponse.statusCode

        switch status {
        case 503:
            throw APIError.serverError(503)
        case 200...299:
            AstralLogger.network("\(method) \(path) → \(status) (\(ms)ms)")
            // Try to decode the match envelope first; on failure, fall back
            // to the standard ScrapeJobResponse.
            if let match = try? decoder.decode(ScrapeMatchResponse.self, from: data) {
                return .matchProposed(match.match)
            }
            let job = try decoder.decode(ScrapeJobResponse.self, from: data)
            return .jobCreated(job)
        case 428:
            throw APIError.cookieRefreshNeeded
        case 429:
            throw APIError.rateLimited
        case 500...599:
            throw APIError.serverError(status)
        default:
            throw APIError.httpError(status)
        }
    }
```

- [ ] **Step 3: Build**

```bash
cd ios/Astral && xcodebuild -scheme Astral \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' \
  build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add ios/Astral/Packages/Networking/Sources/Networking/DTOs/ScrapeDTOs.swift \
        ios/Astral/Packages/Networking/Sources/Networking/APIClient.swift
git commit -m "[ios] AST-30 extend ScrapeRequest + add MangaDexMatchPayload + submitScrape"
```

---

### Task 19: iOS — match dialog component

**Files:**
- Create: `ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/MangaDexMatchDialog.swift`

- [ ] **Step 1: Create the dialog**

Create `ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/MangaDexMatchDialog.swift`:

```swift
import SwiftUI
import Core
import DesignSystem
import Networking

/// Sheet shown when the backend matcher proposes a MangaDex swap for a
/// toongod/hentai20 add. AST-30 — single-user, no public attribution
/// surfaces; this dialog is the only place the user sees the swap.
struct MangaDexMatchDialog: View {
    let match: MangaDexMatchPayload
    let originalSource: String
    let onAccept: () -> Void
    let onDecline: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("MangaDex match found")
                .font(AstralTypography.titleMedium)
                .foregroundStyle(AstralColors.white)

            if let urlString = match.thumbnailUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    default:
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(AstralColors.muted)
                    }
                }
                .frame(maxHeight: 180)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(spacing: 6) {
                Text(match.title)
                    .font(AstralTypography.bodyMedium)
                    .foregroundStyle(AstralColors.white)
                    .multilineTextAlignment(.center)

                Text(
                    "Confidence \(Int(match.confidence * 100))% · "
                    + "\(match.chapterCount) chapters on MangaDex vs "
                    + "\(match.sourceChapterCount) on \(originalSource)"
                )
                .font(AstralTypography.caption)
                .foregroundStyle(AstralColors.muted)
                .multilineTextAlignment(.center)
            }

            VStack(spacing: 8) {
                Button {
                    onAccept()
                    dismiss()
                } label: {
                    Text("Use MangaDex")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(AstralColors.gold, in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)

                Button {
                    onDecline()
                    dismiss()
                } label: {
                    Text("Keep \(originalSource)")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(AstralColors.elevated, in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(AstralColors.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .background(AstralColors.background)
        .presentationDetents([.medium])
    }
}
```

- [ ] **Step 2: Build**

```bash
cd ios/Astral && xcodebuild -scheme Astral \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' \
  build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`. (If `AstralTypography.titleMedium` doesn't exist, swap for an existing token like `bodyMedium` and adjust.)

- [ ] **Step 3: Commit**

```bash
git add ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/MangaDexMatchDialog.swift
git commit -m "[ios] AST-30 add MangaDexMatchDialog confirm sheet"
```

---

### Task 20: iOS — wire matcher flow into `ComicBrowserViewModel`

**Files:**
- Modify: `ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/ComicBrowserView.swift`

- [ ] **Step 1: Add match state to the ViewModel**

In `ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/ComicBrowserView.swift`, add three new properties to `ComicBrowserViewModel` (just below `var canGoForward = false` around line 152):

```swift
    var canGoForward = false

    // AST-30 — MangaDex match flow
    var matchProposal: MangaDexMatchPayload? = nil
    var pendingOriginalRequest: ScrapeRequest? = nil
    var pendingPageTitle: String? = nil
```

- [ ] **Step 2: Replace `extractCookiesAndScrape` to use `submitScrape`**

Replace the entire `extractCookiesAndScrape` method (around lines 183–232) with:

```swift
    func extractCookiesAndScrape() async -> LocalScrapeJob? {
        guard let webView, let url = currentURL, !isScraping else { return nil }
        isScraping = true
        defer { isScraping = false }

        let store = await webView.configuration.websiteDataStore.httpCookieStore
        let allCookies = await store.allCookies()

        let sourceCookies = CookieStore.shared.filterCookies(
            allCookies,
            forSource: selectedSource.rawValue
        )

        let ua = try? await webView.evaluateJavaScript("navigator.userAgent") as? String
        let pageTitle = try? await webView.evaluateJavaScript("document.title") as? String

        let request = ScrapeRequest(
            url: url.absoluteString,
            sourceKey: selectedSource.rawValue,
            cookies: sourceCookies,
            userAgent: ua ?? "Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X)",
            contentType: "comic",
            pageTitle: pageTitle ?? nil
        )
        pendingPageTitle = pageTitle ?? nil

        return await submitAndHandle(request)
    }

    /// Submits a ScrapeRequest. On a match-proposed outcome, stores the proposal
    /// (driving the dialog) and returns nil — the dialog's accept/decline
    /// callbacks finish the flow via acceptMatch/declineMatch.
    private func submitAndHandle(_ request: ScrapeRequest) async -> LocalScrapeJob? {
        do {
            let outcome = try await APIClient.shared.submitScrape(request)
            switch outcome {
            case .jobCreated(let response):
                let alreadyDone = response.status == "complete" || response.status == "partial"
                showToast(ScrapeToast(
                    message: alreadyDone ? "Already in library" : "Scrape queued",
                    isSuccess: true,
                ))
                pendingOriginalRequest = nil
                return LocalScrapeJob(
                    id: response.id,
                    contentType: response.contentType,
                    storyId: response.storyId,
                    status: response.status,
                    chaptersScraped: response.chaptersScraped,
                    chaptersFailed: response.chaptersFailed,
                    totalChapters: response.totalChapters,
                    createdAt: response.createdAt,
                    completedAt: response.completedAt,
                    sourceUrl: response.sourceUrl,
                    sourceKey: response.sourceKey,
                    jobType: response.jobType,
                    errorMessage: response.errorMessage,
                    currentStep: response.currentStep,
                    lastErrorType: response.lastErrorType,
                    startedAt: response.startedAt
                )
            case .matchProposed(let match):
                pendingOriginalRequest = request
                matchProposal = match
                return nil
            }
        } catch {
            showToast(ScrapeToast(message: "Scrape failed: \(error.localizedDescription)", isSuccess: false))
            return nil
        }
    }

    /// Called when the user taps "Use MangaDex" in the match dialog.
    func acceptMatch(modelContext: ModelContext) {
        guard let match = matchProposal,
              let original = pendingOriginalRequest else { return }
        matchProposal = nil
        Task {
            // Re-submit pointing at MangaDex; cookies/UA empty since we don't
            // have MangaDex cookies on hand and the API is public.
            let mangaRequest = ScrapeRequest(
                url: match.mangadexUrl,
                sourceKey: "mangadex",
                cookies: [],
                userAgent: original.userAgent,
                contentType: "comic",
                pageTitle: pendingPageTitle,
                previousSource: original.sourceKey,
                previousSourceUrl: original.url,
                matchConfidence: match.confidence
            )
            if let job = await submitAndHandle(mangaRequest) {
                modelContext.insert(job)
            }
        }
    }

    /// Called when the user taps "Keep <source>" in the match dialog.
    func declineMatch(modelContext: ModelContext) {
        guard let original = pendingOriginalRequest else { return }
        matchProposal = nil
        Task {
            let retry = ScrapeRequest(
                url: original.url,
                sourceKey: original.sourceKey,
                cookies: original.cookies,
                userAgent: original.userAgent,
                contentType: original.contentType,
                pageTitle: original.pageTitle,
                skipMatch: true
            )
            if let job = await submitAndHandle(retry) {
                modelContext.insert(job)
            }
        }
    }
```

- [ ] **Step 3: Present the dialog from the View body**

In the same file, find the `.overlay(alignment: .bottom)` block in the View body (around line 126). Insert a `.sheet(...)` modifier just before it:

```swift
        .background(AstralColors.background)
        .sheet(item: Binding(
            get: { viewModel.matchProposal.map { MatchProposalIdentifiable(payload: $0) } },
            set: { newValue in viewModel.matchProposal = newValue?.payload }
        )) { wrapper in
            MangaDexMatchDialog(
                match: wrapper.payload,
                originalSource: viewModel.pendingOriginalRequest?.sourceKey ?? "",
                onAccept: { viewModel.acceptMatch(modelContext: modelContext) },
                onDecline: { viewModel.declineMatch(modelContext: modelContext) }
            )
        }
        .overlay(alignment: .bottom) {
```

Add a tiny wrapper struct at the bottom of the file (after the WebView / Coordinator extension):

```swift
private struct MatchProposalIdentifiable: Identifiable {
    let payload: MangaDexMatchPayload
    var id: String { payload.mangaId }
}
```

- [ ] **Step 4: Build**

```bash
cd ios/Astral && xcodebuild -scheme Astral \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' \
  build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`. If `AstralTypography.titleMedium` was missing in Task 19, fix it now.

- [ ] **Step 5: Commit**

```bash
git add ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/ComicBrowserView.swift
git commit -m "[ios] AST-30 wire MangaDex match dialog into ComicBrowserView flow"
```

---

### Task 21: Manual end-to-end QA

This task is verification — no code changes. Mark each step done after physically performing it.

- [ ] **Step 1: Restart full backend stack with the new code**

```bash
docker compose -f backend/docker-compose.local.yml up -d --force-recreate fastapi arq_worker
docker compose -f backend/docker-compose.local.yml logs --tail 20 fastapi arq_worker
```

Expected: both come up clean, `MANGADEX_DISABLED=False` settings echoed at startup if logged.

- [ ] **Step 2: Direct MangaDex add via iOS browser**

In iOS sim:
1. Open the app → Comic tab → Browser.
2. Pick MangaDex from the source dropdown — MangaDex home loads.
3. Browse to any title page (URL contains `/title/<uuid>`).
4. Tap the download icon. Toast: "Scrape queued".
5. Switch to Library — comic appears with the `m.square.fill` icon, status fills in over time.

Pass criteria: chapters populate, page images render in the reader, no 429 / circuit-open errors in `arq_worker` logs.

- [ ] **Step 3: Toongod add with MangaDex match found**

Pick a toongod URL for a series you know exists on MangaDex (e.g. Solo Leveling). In iOS:
1. Browser tab → Toongod source → navigate to the series.
2. Tap download.
3. Match dialog should appear within ~2–3s with a confidence ≥ 0.85.
4. Tap **Use MangaDex** — toast "Scrape queued", library shows MangaDex source.

Verify in DB:

```bash
docker exec backend-postgres-1 psql -U astral -d astral -c \
  "SELECT title, source_key, previous_source, previous_source_url, match_confidence
   FROM comics ORDER BY created_at DESC LIMIT 1;"
```

Expected: `source_key=mangadex`, `previous_source=toongod`, `previous_source_url=<toongod URL>`, `match_confidence` populated.

- [ ] **Step 4: Toongod add with MangaDex match — declined**

Repeat Step 3 but tap **Keep toongod**. Toast "Scrape queued" (toongod), library shows toongod source. DB row's `previous_source` is NULL.

- [ ] **Step 5: Toongod add with no MangaDex match**

Pick an obscure toongod series unlikely to be on MangaDex. Add it. **No dialog appears**, scrape proceeds with toongod immediately.

- [ ] **Step 6: Kill switch verification**

```bash
docker compose -f backend/docker-compose.local.yml exec fastapi \
  bash -c "MANGADEX_DISABLED=true python -c \"from app.core.config import Settings; print(Settings().mangadex_disabled)\""
```

Then export and restart with the kill switch on:

```bash
echo "MANGADEX_DISABLED=true" >> backend/.env
docker compose -f backend/docker-compose.local.yml restart fastapi arq_worker
```

In iOS:
- Toongod add: matcher silently skipped, normal toongod scrape runs.
- Direct MangaDex add: toast shows "Scrape failed: Server error (503)".

Roll back the .env line:

```bash
sed -i.bak '/MANGADEX_DISABLED=true/d' backend/.env
docker compose -f backend/docker-compose.local.yml restart fastapi arq_worker
```

- [ ] **Step 7: Stress check**

Add a single 100+ chapter series via the matcher accept path. Tail the worker:

```bash
docker compose -f backend/docker-compose.local.yml logs -f arq_worker | grep -E "mangadex|429|circuit"
```

Expected: zero 429s, zero `MangadexCircuitOpenError`, all chapters scrape to `complete`.

- [ ] **Step 8: Note any regressions**

If anything fails, capture the failing scenario, fix the underlying code, add a test if appropriate, commit, and re-run from the failing step.

---

### Task 22: Final verification + finishing the branch

- [ ] **Step 1: Run the full backend test suite**

```bash
docker compose -f backend/docker-compose.local.yml exec fastapi pytest -v
```

Expected: all green (or pre-existing failures unrelated to AST-30 — verify against `development`'s baseline).

- [ ] **Step 2: Build the iOS target one more time**

```bash
cd ios/Astral && xcodebuild -scheme Astral \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' \
  build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Check `git status` and commit any forgotten files**

```bash
git status
```

If anything's untracked / unstaged that belongs to the feature, stage and commit it. If there's nothing, proceed.

- [ ] **Step 4: Use the finishing-a-development-branch skill**

Invoke `superpowers:finishing-a-development-branch` to handle:
- Pre-merge test verification (re-run)
- Present the four end-of-branch options (merge / push+PR / keep / discard)
- On chosen path: create the PR with body that includes `Closes AST-30` so Linear auto-transitions on merge

PR body template (use exactly this for the auto-link to fire):

```markdown
Closes AST-30

## Summary
- Adds MangaDex as a first-class comic source with rate-limited HTTP, MD@Home report POSTs, and a 5×429-in-60s circuit breaker
- Synchronous title matcher hooks into POST /scrape/comic; on a ≥0.85 hit, returns a match envelope and iOS shows a one-tap confirm sheet
- Three audit columns added to `comics` for transparency on user-confirmed swaps
- Out of scope (split into AST-35 — OAuth porn-tier; deferred — attribution UI, library backfill)

## Test plan
- [ ] Direct MangaDex add via iOS browser → chapters scrape, images render
- [ ] Toongod add with known match → dialog appears, accept → MangaDex source in DB with previous_source populated
- [ ] Toongod add with known match → decline → toongod scrape proceeds
- [ ] Toongod add with no match → no dialog
- [ ] MANGADEX_DISABLED=true → matcher silently skipped, direct mangadex POST returns 503
- [ ] 100-chapter stress test → no 429s or circuit opens
```

---

## Acceptance criteria (from spec)

- [ ] `mangadex` source registered in `SCRAPER_REGISTRY` (Task 13).
- [ ] Rate limiters in place: 5/s global + 40/min for `/at-home/server/` (Task 3).
- [ ] MD@Home report POST fires on every page fetch — success and failure (Task 7 + Task 8 audit).
- [ ] Image pre-fetch pipeline stores pages in `astral_media`; served at `/static/comics/...` (Task 7 — uses existing `block_volume_path` + StaticFiles mount).
- [ ] Matcher scores toongod/hentai20 series; ≥ 0.85 confidence presents iOS confirm dialog before swap (Task 9 + 12 + 19 + 20).
- [ ] `previous_source`, `previous_source_url`, `match_confidence` columns added on `comics` (Postgres — Task 10) and `LocalComic` (SwiftData — Task 17).
- [ ] `mangadex` tab added to comic browser view with cookie extraction (Task 16).
- [ ] Kill switch: `MANGADEX_DISABLED=true` halts new mangadex scrapes (503) and silently disables matcher (Task 12 + Task 9).
- [ ] All unit + API tests passing (Task 22). ToS audit test passing (Task 8).
