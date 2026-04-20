# Changelog

A running log of what shipped to `development`. Most recent first.

Add a new entry whenever you merge a feature/fix PR into `development`. Keep entries terse — the PR body has the detail; this is the index.

## 2026-04-20

### Backend

- **AST-29** — FFNet scraper rewrite: replaced 313 lines of bespoke httpx + 403-retry + BeautifulSoup parsing with `FanFicFare` (primary) + `FicHub` (fallback). New `_fichub.py` shared client (reusable by AST-28) handles FicHub's REST + EPUB-split. New `_fanficfare_runner.py` bridges iOS-harvested cookies into FFF's session and wraps blocking calls in `asyncio.to_thread`. Kill switch `FFNET_NEW_SCRAPER_DISABLED=true` falls through to FicHub-only. Net -151 LOC; 16 unit tests + 3 live smoke tests. ([PR #TBD](https://github.com/agenticCoder97/IosTestApp/pull/TBD))

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
