# Changelog

A running log of what shipped to `development`. Most recent first.

Add a new entry whenever you merge a feature/fix PR into `development`. Keep entries terse — the PR body has the detail; this is the index.

## 2026-04-21

### Backend

- **AST-49** — Prod stack live on OCI: brought up the unified compose stack (postgres, redis, fastapi, arq_worker, nginx, certbot) on the A1 VM at `astral-reader.duckdns.org`. First-time deploy required (a) pre-creating `/mnt/astral-media/postgres` with uid 70 ownership for the alpine postgres container, and (b) fixing a latent bug in `nginx.conf` where `worker_processes auto;` was nested inside the `events{}` block (nginx rejects with `"directive is not allowed here"`). End-to-end verified: `GET https://astral-reader.duckdns.org/api/v1/health` returns `{"status":"ok"}` with a valid LE cert, HTTP→HTTPS 301 redirect works, `fastapi` + `arq_worker` startup logs clean (Redis + Postgres connected, `create_all()` ran, 8 ARQ functions registered including cron jobs). ([PR #44](https://github.com/agenticCoder97/IosTestApp/pull/44))
- **AST-50** — Fix certbot image reference: the previous `certbot/dns-duckdns` image doesn't exist on Docker Hub (pull fails with `repository does not exist`). Switched to `infinityofspace/certbot_dns_duckdns:latest` (community-maintained, bundles certbot + certbot-dns-duckdns plugin). Verified `certbot plugins` lists `dns-duckdns` correctly; initial LE cert for `astral-reader.duckdns.org` successfully issued via DNS-01 and landed in the `letsencrypt` named volume. ([PR #43](https://github.com/agenticCoder97/IosTestApp/pull/43))
- **AST-47** — Merge prod compose files + add Postgres service: consolidated `docker-compose.yml` and `docker-compose.worker.yml` into a single unified prod compose (6 services: `postgres`, `redis`, `fastapi`, `arq_worker`, `nginx`, `certbot`). Adds the previously-missing `postgres:16-alpine` with bind-mount to `/mnt/astral-media/postgres` (block volume → survives VM re-provision). Both app services now `depends_on: postgres (healthy) + redis (started)`, eliminating the silent Redis cache-miss window when bringing stacks up separately. Drops `./wallet:/app/wallet:ro` mounts (Oracle ADB path superseded per AST-42). Part of the OCI migration. ([PR #42](https://github.com/agenticCoder97/IosTestApp/pull/42))

## 2026-04-20

### Backend

- **AST-41** — FFNet chapter text plaintext normalization: new `_html_to_text.html_to_paragraphs` helper strips EPUB/XHTML markup down to paragraphs joined by `\n\n` (matching the AO3 scraper's shape). Wired into both FFNet scraping paths — `_fichub._split_epub_bytes` and `_fanficfare_runner._fetch_sync` — so the iOS reader renders all fanfic sources identically. One-shot idempotent backfill script `scripts/backfill_ffnet_chapter_text.py` cleaned 175 pre-fix rows in-place and recomputed `word_count`. Local compose now mounts `./scripts` into `fastapi` + `arq_worker` so the documented invocation works out of the box. 11 new pinning tests; no schema changes. ([PR #41](https://github.com/agenticCoder97/IosTestApp/pull/41))
- **AST-18** — Guarded against "Unknown Title" scrapes polluting the library: `fanfic_scrape_task` now refuses to overwrite the stored title with empty or `Unknown Title` values, and both FFNet scraper paths (FFF + FicHub) reject an invalid title from the resolver instead of silently writing garbage. iOS `FanficLibraryView` and `FanficScrapesView` filters skip any `LocalFanfic` with title `"Unknown Title"` as belt-and-suspenders. ([PR #40](https://github.com/agenticCoder97/IosTestApp/pull/40))
- **AST-40** — Redis layer consolidation: replaced 8 ad-hoc `aioredis.from_url(...)` + `ArqRedis(r.connection_pool)` sites (which leaked one `ConnectionPool` per call) with a single shared singleton in `app/cache/redis_pool.py`. Pools are opened in FastAPI lifespan + ARQ worker `on_startup`, closed cleanly on shutdown. `BaseScraper._get_cookies()` now wraps `json.loads()` so a corrupted cookie cache degrades to "no cookies" instead of crashing the scrape. `auto_update_task` uses `ctx['redis']` instead of opening its own pool. Magic-number TTLs replaced with `CacheTTL` constants. Net -47 LOC; test suite improves from 21 → 10 pre-existing failures (all unrelated SQL errors). ([PR #39](https://github.com/agenticCoder97/IosTestApp/pull/39))
- **AST-29** — FFNet scraper rewrite: replaced 313 lines of bespoke httpx + 403-retry + BeautifulSoup parsing with `FanFicFare` (primary) + `FicHub` (fallback). New `_fichub.py` shared client (reusable by AST-28) handles FicHub's REST + EPUB-split. New `_fanficfare_runner.py` bridges iOS-harvested cookies into FFF's session and wraps blocking calls in `asyncio.to_thread`. Kill switch `FFNET_NEW_SCRAPER_DISABLED=true` falls through to FicHub-only. Net -151 LOC; 16 unit tests + 3 live smoke tests. ([PR #38](https://github.com/agenticCoder97/IosTestApp/pull/38))

### iOS

- **AST-39** — Backend unreachable on physical device: added `NSLocalNetworkUsageDescription` + `NSBonjourServices` (`_http._tcp`) to `Info.plist` so iOS shows the Local Network permission prompt and allows requests to `192.168.0.108:8000`. Without these keys iOS 14+ silently drops connections to private IPs. Simulator was unaffected (uses `localhost` loopback). ([PR #36](https://github.com/agenticCoder97/IosTestApp/pull/36))

## 2026-04-19

### iOS

- **AST-34** — Fanfic reader chapter-header compaction: title font multiplier `1.4×` → `1.2×`, removed in-flow reading-time HStack (and dead `readingTimeLabel` helper), tightened header VStack spacing `6→4`, header bottom padding `8→4`, outer ScrollView vertical padding `20→10`. First paragraph sits visibly higher; design language preserved. ([PR #34](https://github.com/agenticCoder97/IosTestApp/pull/34))
- **AST-27** — `MorphLandingView` cleanup: extracted phase-geometry magic numbers from `runPhase1`/`runPhase2` into a file-private `PhaseGeometry` enum (4 Phase 1 fractions + 2 Phase 2 fractions), added doc comments on the Phase 3 spring driver and `.onDisappear` animation-token rotation. Sub-item #1 (move `blueColor` to DesignSystem) was already done by AST-21. ([PR #34](https://github.com/agenticCoder97/IosTestApp/pull/34))
- **AST-21** — App logo + AstralColors tokens: added `AstralColors.blue` / `goldLight` / `goldDark` tokens, new `AstralLogo` SwiftUI component in DesignSystem, swapped inline blue hex in `RootView` for the token. ([PR #27](https://github.com/agenticCoder97/IosTestApp/pull/27))

### Backend + iOS

- **AST-30** — MangaDex as a first-class comic source: new `MangadexScraper(BaseScraper)` (search / metadata / chapter list / `/at-home/server/` page URLs / `download_image` override that POSTs MD@Home reports per ToS), shared `MangadexHTTPClient` with `aiolimiter` (5/s global + 40/min for at-home) + 5×429-in-60s circuit breaker, synchronous title matcher hook on `POST /scrape/comic` (returns `202 { match }` envelope on ≥0.85 confidence), iOS `MangaDexMatchDialog` confirm sheet, three `previous_source*` audit columns on `Comic`. Out of scope split: OAuth porn-tier ([AST-35](https://linear.app/nnetraganti/issue/AST-35)); attribution UI deferred (single-user). ([PR #33](https://github.com/agenticCoder97/IosTestApp/pull/33))

## 2026-04-18 and earlier

See `git log` and `docs/superpowers/specs/`.
