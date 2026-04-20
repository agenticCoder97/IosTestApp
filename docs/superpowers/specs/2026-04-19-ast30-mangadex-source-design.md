# AST-30 — MangaDex as a New Comic Source (Design)

**Date:** 2026-04-19
**Linear:** [AST-30](https://linear.app/nnetraganti/issue/AST-30/scrape-add-mangadex-as-new-comic-source-primary-for-toongodhentai20)
**Branch:** `feature/ast-30-mangadex-source`

## Problem

Toongod and hentai20 are aggregator sites — fragile to scrape, sometimes incomplete, and a meaningful subset of their catalog also exists on MangaDex behind a stable, public, well-documented JSON API. We want MangaDex as a first-class comic source so we can prefer it whenever a high-confidence title match exists.

## Goal

Add `mangadex` as a comic source alongside `nhentai` / `toongod` / `hentai20`. When a user adds a series from toongod or hentai20, the backend checks MangaDex first; on a high-confidence match (≥ 0.85), iOS shows a confirm dialog and — on accept — the series is added with `mangadex` as the source instead.

## Out of scope (split or deferred)

- **OAuth2 personal-client login** for the `pornographic` content rating → [AST-35](https://linear.app/nnetraganti/issue/AST-35). v1 covers `safe`, `suggestive`, `erotica` only.
- **In-app attribution UI** ("via MangaDex — \[group\]"). Astral is a private, single-user app on a local device; the public-facing ToS attribution clause does not apply. Backend still POSTs MD@Home reports.
- **Library backfill** (running the matcher against existing toongod/hentai20 series). Future ticket if v1 proves the matcher is accurate enough.
- **Multi-language chapter tracks.** v1 is English-only (`translatedLanguage[]=en`). Adding a per-comic language picker is a follow-up.
- **0.6–0.85 "suggestion" tier** from the original ticket. v1 is binary: ≥ 0.85 → dialog, < 0.85 → silent fallback.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ iOS                                                              │
│  ComicBrowserView ─paste/capture URL─▶ ComicBrowserVM           │
│         │                                    │                   │
│         │                  POST /scrape      │                   │
│         │                                    ▼                   │
│         │                          ┌─────────────────┐           │
│         │                          │ MatchDialog     │           │
│         │                          │ (only on 202)   │           │
│         │                          └────────┬────────┘           │
└──────── │ ────────────────────────────────  │ ──────────────────┘
          │                                   │ user decision
          │                                   │ POST /scrape
          ▼                                   ▼
┌─────────────────────────────────────────────────────────────────┐
│ Backend (FastAPI)                                                │
│  POST /scrape  (api/routers/scrape.py)                          │
│    1. if source ∈ {toongod, hentai20} & not skip_match:         │
│         run mangadex_matcher.find_match()  (synchronous, ~2s)   │
│         if match ≥ 0.85: return 202 { match }                   │
│    2. else: create ScrapeJob, enqueue ARQ task                  │
│                                                                  │
│  services/mangadex_matcher.py        scrapers/comic/mangadex.py │
│       (rapidfuzz scoring)            (search/meta/feed/at-home  │
│              │                        + report POST)            │
│              └────────────┬──────────────┘                      │
│                           ▼                                     │
│             scrapers/comic/_mangadex_http.py                    │
│             (httpx + aiolimiter 5/s & 40/min                    │
│              + circuit breaker)                                 │
│                           ▼                                     │
│                     MangaDex API                                │
│                                                                  │
│  tasks/comic_scrape_task.py (ARQ worker)                        │
│    _scrape_chapter() for source=mangadex:                       │
│      fetch_chapter_pages() → for each page URL:                 │
│        download_image() → POST report (success/failure)         │
└─────────────────────────────────────────────────────────────────┘
```

**Boundaries:**
- `mangadex_matcher` is a pure scoring service. Does not touch DB. Called from the API request thread.
- `MangadexScraper` is a `BaseScraper` subclass — same interface as nhentai/toongod/hentai20. The existing `_scrape_chapter` loop in `comic_scrape_task` works against it unchanged.
- Rate limiting + circuit breaker live in `MangadexHTTPClient` (one client, two callers — scraper and matcher).
- Kill switch (`MANGADEX_DISABLED`) checked in two places: API router (rejects new mangadex scrapes with 503) + matcher (returns `None`).

## Components

### `MangadexScraper` (`backend/app/scrapers/comic/mangadex.py`)

Subclass of `BaseScraper`. Implements the four abstract methods:

| Method | URL accepted | Behavior |
|---|---|---|
| `get_story_metadata(url)` | `https://mangadex.org/title/{manga_id}` | GET `/manga/{id}?includes[]=cover_art&includes[]=author`. Returns `ComicMetadata{title, source_id, source_url, thumbnail_url, description, language, total_chapters, authors[], tags[], category}`. |
| `get_chapter_list(url)` | Same | GET `/manga/{id}/feed?translatedLanguage[]=en&order[chapter]=asc&limit=500&offset=N` paginated until `total` exhausted. Skips `externalUrl` chapters (MangaPlus etc.). Returns `[{chapter_number: float, title, source_id (chapter_id), source_url: "https://mangadex.org/chapter/{chapter_id}"}]`. |
| `get_chapter_pages(chapter_url)` | `https://mangadex.org/chapter/{chapter_id}` | GET `/at-home/server/{chapter_id}` (separate 40/min limiter). Builds page URLs as `{baseUrl}/data/{hash}/{filename}`. Returns the list. |
| `get_chapter_text(...)` | n/a | Raises `NotImplementedError` — comic-only adapter. |

**Image download + ToS report** — overrides `BaseScraper.download_image`. After every page download (success or failure), POSTs to `https://api.mangadex.network/report` with `{url, success, cached, bytes, duration}`. Report failures are logged but never raise — they must not break a scrape.

**Class attrs:** `source_key=SourceKey.MANGADEX`, `requires_browser=False`, `request_delay_seconds=0.0` (rate limiter handles pacing).

**ToS comment block** at the top of the file:
```
# MangaDex API ToS (https://api.mangadex.org/docs/):
# - Honor takedown requests (kill-switch via MANGADEX_DISABLED env)
# - Real User-Agent required; no Via header; TLS 1.2+
# - POST success/failure to api.mangadex.network/report on every page fetch
# - Astral is a private single-user app on a local device — public attribution
#   clause does not apply, but report POSTs are still mandatory.
```

### `MangadexHTTPClient` (`backend/app/scrapers/comic/_mangadex_http.py`)

Module-private wrapper used by both the scraper and the matcher. Single source of truth for limiters, retries, and the circuit breaker.

- **HTTP**: `httpx.AsyncClient` with `User-Agent: Astral/1.0 (+contact: nikhil_netra@hotmail.com)`, `Accept: application/json`, `http2=False` (avoid Via injection).
- **Limiters (class-level so all instances share state in the worker process):**
  - `_global_limiter = aiolimiter.AsyncLimiter(5, 1)` — 5 req/s/IP, applies to every endpoint.
  - `_at_home_limiter = aiolimiter.AsyncLimiter(40, 60)` — 40 req/min for `/at-home/server/`, in addition to global.
- **Retries:** on 429, honor `Retry-After` header (or `2 ** attempt + jitter` if absent). Up to 3 attempts. On 5xx, exponential backoff with jitter.
- **Circuit breaker:** track timestamps of the last 5 × 429s in a `deque(maxlen=5)`. If 5 hits land within 60s, open the circuit for 5 min. Calls during the open window raise `MangadexCircuitOpenError`.
- **Errors module:** `MangadexRateLimitError`, `MangadexCircuitOpenError`, `MangadexAPIError`.

| Endpoint family | Limit | Limiter |
|---|---|---|
| `/manga`, `/manga/{id}`, `/manga/{id}/feed` | 5/s/IP | `_global_limiter` |
| `/at-home/server/{chapter_id}` | 40/min | `_at_home_limiter` (additional to global) |
| `api.mangadex.network/report` | none documented | `_global_limiter` (be polite) |
| MD@Home CDN images | none | unrestricted |

### `mangadex_matcher` (`backend/app/services/mangadex_matcher.py`)

Pure scoring service. No DB access.

```python
@dataclass
class MangaDexMatch:
    manga_id: str
    mangadex_url: str
    title: str
    confidence: float
    thumbnail_url: str | None
    chapter_count: int
    source_chapter_count: int

async def find_mangadex_match(
    *, source: str, source_url: str, source_title: str,
) -> MangaDexMatch | None: ...
```

**Steps (synchronous, ~2–3s end to end):**
1. Bail with `None` if `MANGADEX_DISABLED`, `MANGADEX_AUTO_SWITCH_SOURCE=False`, or `source ∉ {toongod, hentai20}`.
2. Fetch source metadata via `SCRAPER_REGISTRY[source]().get_story_metadata(source_url)` — for tags, chapter count, original language.
3. Search MangaDex: `MangadexScraper().search(title=_normalize(source_title), content_ratings=["safe","suggestive","erotica"], limit=10)`.
4. Score each candidate. Pick the highest.
5. If `best_score >= settings.mangadex_title_match_threshold` (default 0.85), return `MangaDexMatch`; else `None`.

**Scoring formula** (weights sum to 1.0):

| Signal | Weight | Source |
|---|---|---|
| Title similarity | **0.55** | `rapidfuzz.fuzz.token_set_ratio(normalize(src_title), normalize(md_title)) / 100` |
| Original-language match | **0.15** | `1.0` if `md.attributes.originalLanguage == {"toongod":"ko","hentai20":"ja"}[source]`, else `0.0` |
| Tag overlap (Jaccard) | **0.15** | `\|src ∩ md\| / \|src ∪ md\|` over normalized tag names |
| Chapter-count delta within ±20% | **0.15** | `1.0` if `\|md.chapter_count − src.chapter_count\| / src.chapter_count ≤ 0.20`, else `0.0` |

**`_normalize`:** lowercase + strip punctuation/diacritics + collapse whitespace + drop common volume/chapter/episode markers.

### `POST /scrape` API hook (`backend/app/api/routers/scrape.py`)

**Request schema additions:**

```python
class ScrapeRequest(BaseModel):
    url: str
    source: str
    page_title: str | None = None       # NEW — iOS WebView document.title
    skip_match: bool = False             # NEW — user declined the dialog
    previous_source: str | None = None   # NEW — original source on accepted swap
    previous_source_url: str | None = None
    match_confidence: float | None = None
```

**Response branches** (existing route already returns 202 for the happy job-create path):
- `503` if `source == "mangadex"` and `MANGADEX_DISABLED`.
- `202 { match: { ... } }` if matcher returns a `MangaDexMatch` (eligible source + not `skip_match` + not disabled).
- `202 { id, story_id, status, ... }` (existing `ScrapeJobResponse`) otherwise — the existing happy path.

Both 2xx envelopes are returned as `202`; the iOS client distinguishes by body shape (tries `ScrapeMatchResponse` decode first, falls back to `ScrapeJobResponse`).

**iOS flow:**
1. iOS POSTs `{url: "toongod...", source: "toongod", page_title: "..."}`.
2. Backend → `202 { match }` → iOS shows confirm dialog.
3. **User accepts** → iOS POSTs `{url: "mangadex.org/title/...", source: "mangadex", previous_source: "toongod", previous_source_url: "toongod...", match_confidence: 0.91}` → `202 { id, story_id, ... }`.
4. **User declines** → iOS POSTs original payload again with `skip_match: true` → `202 { id, story_id, ... }` against the original source.

### Schema changes

**Postgres** (`backend/app/models/comic.py` + Alembic migration) — three nullable columns on `comics`:

| Column | Type | Purpose |
|---|---|---|
| `previous_source` | `VARCHAR(50)` | e.g. `"toongod"` if user accepted a swap. |
| `previous_source_url` | `VARCHAR(2000)` | Original URL — debug / re-scrape source if needed. |
| `match_confidence` | `DOUBLE PRECISION` | Score that triggered the swap (e.g. `0.91`). |

Backfill: nothing — all existing rows stay NULL. New Alembic revision chained off the latest one.

**SwiftData** (`ios/Astral/Packages/Core/Sources/Core/Models/LocalComic.swift`) — mirror the same three optional properties (`previousSource: String?`, `previousSourceURL: String?`, `matchConfidence: Double?`). Adding optional properties is a SwiftData lightweight migration on iOS 17.2 — no schema-version bump needed (matches existing pattern).

### Source enums

- **Backend** (`backend/app/core/constants.py`): add `MANGADEX = "mangadex"` to `SourceKey`. Add a row to `SOURCE_RATE_CONFIG`: `{"delay": 0.0, "max_retries": 3, "requires_browser": False}`.
- **iOS** (`Core/Utilities/ContentType.swift`): add `case mangadex` to `ComicSource`.

### Settings (`backend/app/core/config.py`)

Three new env-backed fields:

```python
mangadex_disabled: bool = False
mangadex_title_match_threshold: float = 0.85
mangadex_auto_switch_source: bool = True
```

**`.env.example`** updated with the three vars (commented). **`CLAUDE.md`** gains a short MangaDex env-var section.

### iOS surface area

**Source-aware tokens (one-line edits each):**
- `Networking/CookieStore.swift:13` — add `"mangadex": "mangadex.org"`.
- `ComicFeature/Library/ComicCardView.swift:20` — add `case "mangadex": "m.square.fill"`.
- `ComicFeature/Browser/ComicBrowserView.swift` — add `.mangadex` to dropdown, `allowedDomains: ["mangadex.org"]`, `sourceURL: URL(string: "https://mangadex.org")!`, scrape-validation requires `/title/`.

**New: `ComicFeature/Browser/MangaDexMatchDialog.swift`**
- `.confirmationDialog` (or `.sheet` if richer layout needed) presented when scrape submission returns `202 { match }`.
- Body: thumbnail (async-loaded from `match.thumbnail_url`), MangaDex title, two-line subtitle ("Confidence 91% • 47 chapters on MangaDex vs 50 on toongod"), two buttons: **Use MangaDex** (primary) / **Keep toongod** (secondary).

**`Networking/ScrapeService.swift`** — extend the existing scrape-submit method:
- Decode by status code: `200` → `.jobCreated(jobId, comicId)`; `202` → `.matchProposed(MangaDexMatchPayload)`; `503` → `.unavailable(message)`.
- Return type becomes an enum.

**`ComicBrowserViewModel`** gains:
- `matchProposal: MangaDexMatchPayload?` — drives the dialog.
- `acceptMatch()` → submit `{source: "mangadex", url: match.mangadex_url, previous_source: original_source, previous_source_url: original_url, match_confidence: match.confidence}`.
- `declineMatch()` → re-submit original payload with `skip_match: true`.

**No new design tokens** — uses existing card/badge styling and an SF Symbol.

## Data flow (happy paths)

**A. New toongod add, MangaDex match found, user accepts:**
1. iOS captures URL + `document.title` from WebView.
2. POST `/scrape {url, source: "toongod", page_title}`.
3. Backend matcher: fetch toongod metadata (1–2s) → search MangaDex (≤ 1s) → score → returns `MangaDexMatch{confidence: 0.91}`.
4. Backend → `202 { match }`.
5. iOS dialog → user taps **Use MangaDex**.
6. iOS POST `/scrape {url: mangadex_url, source: "mangadex", previous_source: "toongod", previous_source_url, match_confidence: 0.91}`.
7. Backend creates ScrapeJob with mangadex source; writes `previous_*` columns; enqueues ARQ.
8. ARQ worker: `MangadexScraper.get_story_metadata` → write Comic row → `get_chapter_list` → write ComicChapter rows → loop chapters: `get_chapter_pages` → `download_image` per page → `_post_report` per page → write Page rows.
9. Job → `complete`. iOS sees the comic populate.

**B. New toongod add, no MangaDex match:**
1–3 as above. Matcher returns `None`.
4. Backend creates ScrapeJob normally with toongod source.
5. Standard toongod scrape flow runs, unchanged from today.

**C. Direct mangadex add (user pastes mangadex URL in the new browser tab):**
1. iOS POSTs `{url, source: "mangadex"}` — matcher does not run (source not eligible).
2. Backend creates ScrapeJob; enqueues. Same worker path as above.

**D. Kill switch on, user adds toongod:**
- Matcher returns `None` immediately. Toongod scrape proceeds as if MangaDex didn't exist.

**E. Kill switch on, user pastes mangadex URL:**
- API returns `503 { detail: "MangaDex temporarily disabled" }`. iOS surfaces the message in a toast.

## Error handling

| Scenario | Behavior |
|---|---|
| MangaDex API 429 | HTTP client honors `Retry-After`, retries up to 3 times. On exhaustion → `MangadexRateLimitError`. Matcher catches → returns `None`. Scraper raises → chapter marked `FAILED` with `last_error_type="MangadexRateLimit"`. |
| 5 × 429 within 60s | Circuit opens for 5 min. Subsequent calls raise `MangadexCircuitOpenError`. Matcher → `None` (silent fallback). Scraper → chapter `FAILED`. |
| Single page download fails | Reported as failure to MD@Home (per ToS), chapter has missing page rows, `total_pages` reflects what landed, scrape continues to next chapter. Existing pattern. |
| Report POST fails | Logged at `WARNING`, never raised. Reporting is best-effort. |
| `externalUrl` chapter (MangaPlus link) | Filtered out at `get_chapter_list` time — we cannot scrape it. |
| Pagination > 500 chapters | Loop until `offset + limit >= total`. |
| Source metadata fetch fails during matcher | Matcher returns `None`. User sees no dialog; toongod scrape proceeds normally. |

## Testing

**Backend unit (pure functions, no I/O):**
- `tests/services/test_mangadex_matcher.py` — scoring grid, normalization, weight verification.
- `tests/scrapers/test_mangadex_parsing.py` — fixture-based parsing of saved API responses (manga, feed, at-home/server). Pagination test. `externalUrl` filter test.

**Backend HTTP behavior (mocked transport via `httpx.MockTransport`):**
- `tests/scrapers/test_mangadex_http.py` — 429 retry, circuit open after 5 × 429 in 60s, circuit auto-close after 5 min, `download_image` reports on success AND failure.

**Backend API (TestClient):**
- `tests/api/test_scrape_router_mangadex.py` — match → 202; `skip_match` → 200; non-eligible source → matcher not invoked; `MANGADEX_DISABLED` + mangadex source → 503.

**ToS audit (CI-grep):**
- A test that walks `mangadex.py` AST and asserts every `download_image` path leads to a `_post_report` call (success and failure branches). Prevents future refactors from silently dropping the report.

**iOS:**
- `ScrapeServiceTests` — given canned 200 / 202 / 503 responses, verify the right enum case is returned.
- `ComicBrowserViewModelTests` — `acceptMatch()` and `declineMatch()` re-submit with the right payloads.

**Manual E2E (post-merge, run-once):**
- 10 toongod series known to exist on MangaDex → dialog appears; accept → first chapter renders.
- 10 toongod series known NOT to be on MangaDex → no dialog, toongod scrape proceeds.
- Browse `mangadex.org` in the iOS browser tab, paste a `/title/` URL, end-to-end scrape.
- 100-chapter stress: tail logs for any `429` or `MangadexCircuitOpen`.
- Kill switch: set `MANGADEX_DISABLED=true`, verify toongod scrape skips matcher silently and mangadex scrape returns 503.

## File inventory

**New (backend):**
- `backend/app/scrapers/comic/mangadex.py`
- `backend/app/scrapers/comic/_mangadex_http.py`
- `backend/app/services/mangadex_matcher.py`
- `backend/alembic/versions/<rev>_add_comic_mangadex_swap_columns.py`
- `backend/tests/scrapers/fixtures/mangadex/*.json`
- `backend/tests/scrapers/test_mangadex_parsing.py`
- `backend/tests/scrapers/test_mangadex_http.py`
- `backend/tests/services/test_mangadex_matcher.py`
- `backend/tests/api/test_scrape_router_mangadex.py`

**Modified (backend):**
- `backend/app/core/constants.py` — `SourceKey.MANGADEX`, rate-config row.
- `backend/app/core/config.py` — three new settings fields.
- `backend/app/models/comic.py` — three new ORM columns.
- `backend/app/api/routers/scrape.py` — request-schema fields, matcher hook, 202 / 503 branches.
- `backend/app/services/scrape_service.py` — accept new optional kwargs in `create_scrape_job`.
- `backend/app/tasks/comic_scrape_task.py` — register `MangadexScraper` in `SCRAPER_REGISTRY`.
- `backend/requirements.txt` — `aiolimiter`, `rapidfuzz` (if not present).
- `backend/.env.example` — three new commented vars.
- `CLAUDE.md` — short MangaDex env-var section.

**New (iOS):**
- `ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/MangaDexMatchDialog.swift`
- `ios/Astral/Packages/ComicFeature/Tests/ComicFeatureTests/MangaDexMatchDialogTests.swift`

**Modified (iOS):**
- `Core/Sources/Core/Models/LocalComic.swift` — three optional properties + init.
- `Core/Sources/Core/Utilities/ContentType.swift` — `.mangadex`.
- `Networking/Sources/Networking/CookieStore.swift` — domain mapping.
- `Networking/Sources/Networking/ScrapeService.swift` — 202 decoding + match payload type + return enum.
- `ComicFeature/Sources/ComicFeature/Browser/ComicBrowserView.swift` + ViewModel — tab + match flow.
- `ComicFeature/Sources/ComicFeature/Library/ComicCardView.swift` — icon.

## Build sequence (TDD-friendly)

1. **HTTP plumbing** — `_mangadex_http.py` + tests. Verifies limiters + circuit breaker without business logic.
2. **Scraper adapter** — `mangadex.py` skeleton + `get_story_metadata` (fixture test) → `get_chapter_list` (with pagination + `externalUrl` filter) → `get_chapter_pages` → `download_image` override + report POST tests.
3. **Matcher** — `mangadex_matcher.py` + scoring tests. Stub `MangadexScraper.search` for unit tests; integration test against fixtures.
4. **DB migration + Comic columns** — Alembic revision + apply locally + ORM model update.
5. **`scrape_service.create_scrape_job`** — accept new optional kwargs, write to columns. Test.
6. **API router** — request-schema additions, matcher hook, 202 + 503 branches. Tests cover all branches.
7. **Worker registration** — add `MangadexScraper` to `SCRAPER_REGISTRY`. Smoke-test `_scrape_chapter` against the new scraper via monkeypatched fixtures.
8. **iOS source-aware tokens** — enum, cookies, icon, browser tab. No new logic. Builds clean.
9. **iOS `LocalComic` migration** — three optional properties; verify lightweight migration on a populated dev DB.
10. **iOS `ScrapeService` 202 decoding** — extend the enum, decode tests.
11. **iOS match dialog + ViewModel wiring** — present dialog on `.matchProposed`; accept/decline submit the right payload.
12. **Manual E2E** — the QA list from Testing.
13. **Final verification** — full backend suite, iOS build, tail logs during a real scrape.

## Acceptance criteria

- [ ] `mangadex` source registered in `SCRAPER_REGISTRY`.
- [ ] Rate limiters in place: 5/s global + 40/min for `/at-home/server/`.
- [ ] MD@Home report POST fires on every page fetch (success and failure).
- [ ] Image pre-fetch pipeline stores pages in `astral_media` volume; served at `/static/comics/...`.
- [ ] Matcher scores toongod/hentai20 series; ≥ 0.85 confidence presents iOS confirm dialog before swap.
- [ ] `previous_source`, `previous_source_url`, `match_confidence` columns added on `comics` (Postgres) and `LocalComic` (SwiftData).
- [ ] `mangadex` tab added to comic browser view with cookie extraction.
- [ ] Kill switch: `MANGADEX_DISABLED=true` halts new mangadex scrapes (503) and silently disables matcher.
- [ ] All unit + API tests passing. ToS audit test passing.

## Risks and follow-ups

- **Coverage variability** — MangaDex may have fewer chapters than the aggregator for a given series. Matcher's chapter-count-delta signal mitigates this; the dialog text shows the delta so the user can decide.
- **Content-policy drift** — MangaDex enforcement around apparent-minor content has shifted; some hentai20 series may vanish from MangaDex over time. Fallback chain (matcher returns None → original source proceeds) covers this.
- **SwiftData migration** — adding optional properties is automatic on iOS 17.2; no schema-version bump required.
- **OAuth porn-tier**: tracked in [AST-35](https://linear.app/nnetraganti/issue/AST-35).
- **Library backfill** of existing toongod/hentai20 series with the matcher: future ticket if v1 proves accurate.

## References

- [MangaDex API docs](https://api.mangadex.org/docs/)
- [Rate limits](https://api.mangadex.org/docs/2-limitations/)
- [Chapter retrieval + report](https://api.mangadex.org/docs/04-chapter/retrieving-chapter/)
- [Content ratings / enumerations](https://api.mangadex.org/docs/3-enumerations/)
- Linear: [AST-30](https://linear.app/nnetraganti/issue/AST-30), [AST-35](https://linear.app/nnetraganti/issue/AST-35) (OAuth follow-up), parent [AST-17](https://linear.app/nnetraganti/issue/AST-17).
