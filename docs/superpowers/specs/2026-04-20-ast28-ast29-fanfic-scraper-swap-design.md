# AST-28 + AST-29 — Fanfic Scraper Library Swap

**Status:** Approved (brainstorm complete 2026-04-20)
**Linear:** [AST-29](https://linear.app/nnetraganti/issue/AST-29) (FFNet → FanFicFare + FicHub) · [AST-28](https://linear.app/nnetraganti/issue/AST-28) (AO3 → ao3_api + FicHub)
**Sequence:** AST-29 ships first (PR 1), AST-28 second (PR 2). FicHub client lands with PR 1 and is reused by PR 2.

---

## Problem

The current FFNet and AO3 scrapers (`backend/app/scrapers/fanfic/ffnet.py`, `ao3.py`) are bespoke httpx + curl_cffi + BeautifulSoup pipelines that re-implement Cloudflare bypass, retry/backoff, and chapter parsing. They break when either site shifts CSS selectors or tightens CF rules. Two maintained Python libraries solve these problems with a 10+ year track record:

- **[FanFicFare](https://github.com/JimmXinu/FanFicFare)** — Calibre plugin family, exposes a Python API for FFNet metadata + chapter HTML
- **[ao3_api](https://github.com/wendytg/ao3_api)** — Python wrapper around AO3's public site/API surface

Plus a community archive that sidesteps both:

- **[FicHub](https://fichub.net/api/v0/epub?q=<url>)** — public REST API that returns `{ epub_url, urlId, meta }` for any FFNet/AO3 URL; we download + parse the EPUB on hard-fail of the primary library

---

## Design summary

Two PRs, identical shape:

```
                                    ┌─────────────────────────────┐
   iOS WKWebView cookies            │  BaseScraper subclass        │
        │                            │  (ffnet.py / ao3.py)        │
        ▼                            │                             │
  CookieStore ──cookies+UA────────▶ │  try:                       │
                                    │    primary library          │  ──▶  StoryMetadata + chapters
                                    │  except (LibError, CF):     │
                                    │    _fichub.fetch + parse    │  ──▶  StoryMetadata + chapters
                                    │  except FicHubError:        │
                                    │    raise original           │  ──▶  surface to user
                                    └─────────────────────────────┘
```

- **Primary tier:** FanFicFare (FFNet) / `ao3_api` (AO3) — direct Python API, called via `asyncio.to_thread`
- **Fallback tier:** FicHub REST → EPUB → `ebooklib` parse → chapter list
- **No third tier:** the existing `curl_cffi` legacy paths are deleted (~250 + ~200 LOC removed)

Cookie handling is unchanged from the user's perspective: `WKWebView` still harvests on `didFinish`, `CookieStore` still persists, but the cookies now flow into FanFicFare's `Configuration.session.cookies` / `ao3_api.Session.session.cookies` instead of curl_cffi.

---

## Decisions (from brainstorm)

| # | Decision | Rationale |
|---|---|---|
| 1 | **Sequence: AST-29 first, AST-28 second.** Two PRs, not bundled. | FFNet is the more painful failure case; FicHub client lands with PR 1 and AST-28 reuses it. Each PR reviewable on its own. |
| 2 | **FanFicFare integration via direct Python API.** Not subprocess, not EPUB-roundtrip. | Stays in-process, no per-chapter process spawn, lets us inject cookies + UA directly. |
| 3 | **Two-tier fallback: library → FicHub.** Drop `curl_cffi` legacy entirely. | FFF/ao3_api have built-in retry; FicHub is the second tier. A third tier is dead weight we'd never debug. |
| 4 | **FFNet cookies: bridge iOS-harvested cookies into FanFicFare's session.** | The harvest already works; throwing it away to "see if FFF can solo it" is a regression risk for zero gain. |
| 5 | **FicHub client placement: `backend/app/scrapers/fanfic/_fichub.py`** (sibling, leading underscore). | Mirrors the AST-30 `_mangadex_http.py` precedent. Promotes to `backend/app/clients/` if a third caller appears. |
| 6 | **FicHub fetch model: persist parsed chapters into `fanfic_chapters` immediately, reuse DB on subsequent reads.** | Matches our existing scrape pattern. (a) over-fetches, (b) adds disk-cache infra for a rare path. |
| 7 | **Testing: hybrid.** Library-boundary mocks for fast CI; `pytest -m live` smoke tests run manually before each PR. | Matches AST-30 mock pattern; live suite catches "library's parser changed" between releases. |
| 8 | **AO3 cookies: bridge iOS-harvested cookies into `ao3_api.Session`** (consistent with FFNet). | Same UX as today, covers locked + adult-content automatically. Falls back to anonymous + `?view_adult=true` if cookies missing. |
| 9 | **Per-source kill switches (lib only, not source-wide).** `FFNET_NEW_SCRAPER_DISABLED=true` / `AO3_NEW_SCRAPER_DISABLED=true` skip the library, fall through to FicHub. | Matches the actual failure mode we'd want to recover from. Source-wide kill switch would be over-broad given a working fallback exists. |

---

## File changes

### PR 1 — AST-29 (FFNet)

**New files:**

- `backend/app/scrapers/fanfic/_fichub.py` (~120 lines)
  ```python
  class FicHubError(Exception): ...

  @dataclass
  class FicHubMeta:
      title: str
      author: str
      chapters: int
      status: str          # "complete" | "ongoing"
      word_count: int
      summary: str
      fandoms: list[str]
      epub_url: str        # relative — join with https://fichub.net
      url_id: str          # cache key — bumps when new chapters land

  @dataclass
  class ChapterText:
      number: int          # 1-based
      title: str
      html: str            # raw chapter HTML

  async def fetch_story_meta(fic_url: str) -> FicHubMeta: ...
  async def download_and_split_epub(epub_url: str) -> list[ChapterText]: ...
  ```
  - 30s timeout, single retry on 5xx, no auth/cookies
  - `download_and_split_epub` strips OPS/nav.xhtml + cover; keeps spine items only

- `backend/app/scrapers/fanfic/_fanficfare_runner.py` (~80 lines)
  - `async fetch_via_fanficfare(url, cookies, ua) -> (StoryMetadata, list[ChapterText])`
  - Wraps blocking FFF calls in `asyncio.to_thread`
  - Bridges `cookies: list[dict]` → `http.cookiejar.CookieJar` → `Configuration.get_session().cookies`

**Rewritten files:**

- `backend/app/scrapers/fanfic/ffnet.py` — drops from 313 to ~80 lines
  - `get_story_metadata`, `get_chapter_list`, `get_chapter_text` all delegate to `_fanficfare_runner`
  - One try/except: `FanFicFareError | CookieExpiredError | httpx.ConnectError` → `_fichub` fallback
  - On FicHub failure → re-raise the **original** primary error (not the FicHub one)
  - `FFNET_NEW_SCRAPER_DISABLED=true` short-circuits straight to FicHub

**Modified:**

- `backend/app/core/config.py` — `ffnet_new_scraper_disabled: bool = False`
- `backend/requirements.txt` — `FanFicFare>=4.36.0`, `ebooklib>=0.18`
- `backend/.env.example` — `FFNET_NEW_SCRAPER_DISABLED=false`
- `CLAUDE.md` — document the kill switch under "Backend Notes"
- `CHANGELOG.md` — AST-29 entry

**Unchanged:** `BaseScraper`, `__init__.py`, `comic_scrape_task.py`, DB schema, all DTOs, iOS code, `WKWebView` cookie pipeline.

---

### PR 2 — AST-28 (AO3)

**New files:**

- `backend/app/scrapers/fanfic/_ao3_runner.py` (~90 lines)
  - `async fetch_via_ao3_api(url, cookies, ua) -> (StoryMetadata, list[ChapterText])`
  - Wraps blocking `ao3_api.Work(workid)` calls in `asyncio.to_thread`
  - If cookies present → constructs `ao3_api.Session()` and injects cookies into its `requests.Session`; passes as `Work(workid, session=...)`
  - If cookies missing → anonymous mode + `?view_adult=true` URL param (covers public E-rated; locked fics fail gracefully → fallback to FicHub)

**Rewritten files:**

- `backend/app/scrapers/fanfic/ao3.py` — drops from 291 to ~80 lines
  - Same shape as the new `ffnet.py`
  - One try/except: `Ao3ApiError | CookieExpiredError` → `_fichub` fallback (reuses the file from PR 1)
  - `AO3_NEW_SCRAPER_DISABLED=true` short-circuits to FicHub

**Modified:**

- `backend/app/core/config.py` — `ao3_new_scraper_disabled: bool = False`
- `backend/requirements.txt` — `ao3-api>=2.3.0`
- `backend/.env.example` — `AO3_NEW_SCRAPER_DISABLED=false`
- `CLAUDE.md` — document `AO3_NEW_SCRAPER_DISABLED` alongside the FFNet entry
- `CHANGELOG.md` — AST-28 entry

**No changes from PR 1 needed:** `_fichub.py` is reused exactly as shipped.

---

## Caller pattern (used identically by both scrapers, with FFNet shown)

```python
async def get_story_metadata(self, url: str) -> StoryMetadata:
    primary_err: Exception | None = None

    if not settings.ffnet_new_scraper_disabled:
        try:
            cookies, ua = await self._get_cookies()
            meta, _ = await fetch_via_fanficfare(url, cookies, ua)
            return meta
        except (FanFicFareError, CookieExpiredError, httpx.ConnectError) as e:
            primary_err = e
            logger.warning("FFF failed, trying FicHub | url=%s err=%s", url, e)
        # Any other exception propagates — we do not silently swallow.

    # Fallback path (also reached when kill switch is on, with primary_err = None)
    try:
        fh_meta = await _fichub.fetch_story_meta(url)
        return _to_story_metadata(fh_meta)
    except FicHubError:
        if primary_err is None:
            raise              # kill switch on → surface FicHub error directly
        raise primary_err      # surface the original primary error
```

For AST-28, replace `ffnet_new_scraper_disabled` → `ao3_new_scraper_disabled`,
`fetch_via_fanficfare` → `fetch_via_ao3_api`, and the catch tuple → `(Ao3ApiError, CookieExpiredError, httpx.ConnectError)`.

---

## Test plan

### Unit tests (CI, fast, library boundary mocks)

`backend/tests/scrapers/fanfic/test_ffnet_scraper.py` (~6 tests):

- `test_metadata_via_fanficfare` — mock `fanficfare.adapters.getAdapter` returns canned `Story`; assert `StoryMetadata` mapping
- `test_chapter_list_via_fanficfare` — assert chapter ordering + numbering
- `test_falls_back_to_fichub_on_fanficfare_error` — primary raises; mock `_fichub.fetch_story_meta` returns canned `FicHubMeta`; assert fallback used
- `test_falls_back_to_fichub_on_cookie_expired` — `CookieExpiredError` triggers fallback
- `test_kill_switch_skips_fanficfare` — `FFNET_NEW_SCRAPER_DISABLED=true` → `getAdapter` never called, FicHub called directly
- `test_propagates_original_error_when_both_fail` — both raise → original `FanFicFareError` re-raised

`backend/tests/scrapers/fanfic/test_ao3_scraper.py` — mirror of the above (~6 tests).

`backend/tests/scrapers/fanfic/test_fichub_client.py` (~5 tests):

- `test_fetch_story_meta_success` — `httpx.MockTransport` returns canned JSON; assert `FicHubMeta` fields
- `test_fetch_story_meta_raises_on_err_minus_one` — `{"err":-1, "msg":"..."}` → `FicHubError`
- `test_fetch_story_meta_retries_once_on_5xx` — first call 502, second 200 → success
- `test_download_and_split_epub_extracts_chapters` — fixture EPUB on disk, assert chapter count + ordering
- `test_strips_nav_and_cover_from_chapters` — fixture EPUB with cover.xhtml + nav.xhtml → those excluded

### Live smoke tests (manual, gated, network-required)

`backend/tests/scrapers/fanfic/test_live.py` (~4 tests):

- One real FFNet fic via FanFicFare (a long stable fic, e.g. HPMOR by id)
- One real AO3 fic via `ao3_api` (a public general-rated work)
- One real FicHub fetch + EPUB parse (a fic known to be in FicHub's cache)
- One forced-fallback test (kill switch → FicHub directly for an FFNet URL)

`backend/pytest.ini`:

```ini
markers =
    live: hits real external services; run manually before PR (pytest -m live)
```

CI runs `pytest -m "not live"`. Run `pytest -m live` locally before opening each PR.

### Manual QA checklist (per PR, copied into PR body)

**PR 1 (AST-29):**
- [ ] Add a new FFNet fic from iOS browser → succeeds via FanFicFare
- [ ] `FFNET_NEW_SCRAPER_DISABLED=true`, restart backend, add another FFNet fic → succeeds via FicHub
- [ ] Delta-scrape an existing FFNet fic → only new chapters fetched

**PR 2 (AST-28):**
- [ ] Add a new AO3 explicit-rated fic → cookies bridge works, scrape succeeds
- [ ] Add a public general-rated AO3 fic with no cookies → anonymous mode + `?view_adult=true` works
- [ ] `AO3_NEW_SCRAPER_DISABLED=true`, add an AO3 fic → succeeds via FicHub
- [ ] Delta-scrape an existing AO3 fic → only new chapters fetched

---

## Rollout

| Step | Action |
|---|---|
| 1 | Land PR 1 (AST-29) on `development` with `FFNET_NEW_SCRAPER_DISABLED=false` (default) |
| 2 | Manual QA on physical device for ~2 days; flip kill switch + restart if regression observed |
| 3 | Land PR 2 (AST-28) on `development` with `AO3_NEW_SCRAPER_DISABLED=false` (default) |
| 4 | After ~1 week stable, treat kill switches as emergency-only (no further config changes) |

### Kill-switch matrix

| Env var | Default | Effect when `true` |
|---|---|---|
| `FFNET_NEW_SCRAPER_DISABLED` | `false` | Skip FanFicFare, scrape FFNet via FicHub only |
| `AO3_NEW_SCRAPER_DISABLED` | `false` | Skip `ao3_api`, scrape AO3 via FicHub only |

When both `true`, all fanfic scraping goes through FicHub — degraded but functional.

`MANGADEX_DISABLED` (from AST-30) remains a hard-stop because there is no fallback for MangaDex; these aren't, because there is.

---

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| FanFicFare's sync API blocks the event loop | Wrap every call in `asyncio.to_thread` (in `_fanficfare_runner.py`) |
| FFF / `ao3_api` breaks on a future site change | Kill switch flips to FicHub; we patch the lib version pin during a normal sprint |
| FicHub cache lag (their EPUB doesn't have the latest chapter yet) | Accept it — when fallback fires we get whatever FicHub has; user can re-trigger after primary recovers. Rare since FFF is primary. |
| FicHub itself goes down | Both tiers fail → original error surfaces to user; no silent failure (verified by `test_propagates_original_error_when_both_fail`) |
| EPUB parsing returns junk (cover-as-chapter) | `test_strips_nav_and_cover_from_chapters` covers it; FFF EPUBs have a stable spine so this is detectable |
| `ao3_api` requires Python features we don't have | Backend is on Python 3.11+; verified before pinning |

---

## Out of scope (explicit)

- Re-scraping all existing FFNet/AO3 fics with the new pipeline. Existing `fanfic_chapters` data stays as-is; only new + delta scrapes use the new path.
- Migrating `fanfic_chapters` schema. No changes needed — same shape.
- iOS UI changes. Fallback is invisible to the user; logs only.
- A third tier (`curl_cffi` legacy). Confirmed dropped in Decision #3.
- Promoting `_fichub.py` to `backend/app/clients/`. Premature for one shared client; revisit if a third caller appears.
