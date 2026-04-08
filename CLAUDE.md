# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Astral** — a private, single-user iOS reading application for manga/manhwa comics and fan fiction. Sideloaded via Xcode with a free Apple developer account. Backend runs on OCI Free Tier (not in this repo).

## Build & Run

- **Open project**: `open ios/Astral/Astral.xcodeproj`
- **Regenerate project** (after adding files): `cd ios/Astral && xcodegen generate`
- **Build from CLI**: `cd ios/Astral && xcodebuild -scheme Astral -sdk iphonesimulator -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build`
- **Minimum deployment target**: iOS 17.2

## Architecture

- **Pattern**: MVVM. Views own no logic. ViewModels call services. Services call APIClient or SwiftData.
- **Modular packages** under `ios/Astral/Packages/`:
  - `Core` — SwiftData @Model classes, enums, AppConfig
  - `Networking` — APIClient (async/await), Endpoints, CookieStore, DTOs
  - `DesignSystem` — Colors, Typography, reusable components, view modifiers
  - `ComicFeature` — Comic library, reader, browser, scrapes
  - `FanficFeature` — Fanfic library, reader, browser, scrapes, filter
- **App layer** (`ios/Astral/App/`): RootView, TabBarView, AppState
- **Project generation**: XcodeGen (`project.yml`)

## Conventions

- All async calls use structured concurrency (async/await + Task). No completion handlers.
- All design tokens from DesignSystem package — no hardcoded hex in feature modules.
- Cookie extraction fires on every `webView(_:didFinish:)`, not only on Scrape tap.
- HTTPS only. No ATS exceptions in Info.plist.
- SwiftData predicates tested on iOS 17.2 specifically. Prefer in-memory filtering for small datasets.
- Reading progress debounced: 5s minimum between API writes.
- Commit prefix: `[ios]` or `[backend]` followed by imperative description.
- Branch naming: `feature/{name}`, `fix/{description}`, `chore/{task}`

## Architecture Corrections Applied (from v1.1 doc)

1. `#Unique` macro replaced with `@Attribute(.unique)` (iOS 17.2 compat)
2. CookieStore uses domain mapping dict — "ao3" maps to "archiveofourown.org"
3. Fanfic sidebar includes Scrapes view (missing from original doc)
4. `fanfic_chapters.chapter_number` uses Double (was Integer in doc)
5. `LocalAuthor` includes `updatedAt` (missing from doc)

## Backend Notes

- Backend lives in `backend/` — FastAPI + ARQ worker + Postgres + Redis, run via `docker-compose.local.yml`
- Static files (comic page images, thumbnails) stored in `astral_media` Docker volume at `/mnt/astral-media`
- FastAPI mounts `StaticFiles` at `/static` — iOS constructs URLs as `staticBaseURL + filePath`
- `AppConfig.staticBaseURL` **must** end with a trailing `/` — no trailing slash causes `"/staticcomics/..."` 404s
- curl_cffi impersonation: use `chrome120`, not `safari17_2` (unsupported in curl_cffi 0.7.4)
- `ARQ_MAX_JOBS=3`, `SOFT_DELETE_DAYS=5`, `COOKIE_CACHE_TTL_SECS=86400` are standard env vars

## SwiftData Gotchas

- **Never name a `@Model` property `description`** — conflicts with `CustomStringConvertible`. Use `comicDescription`, `fanficDescription`, etc.
- **Long press on a ZStack overlay blocks `ScrollView`** — use `.simultaneousGesture(LongPressGesture(...).onEnded { })` instead of `.onLongPressGesture` so the scroll and long-press recognizers coexist.
- `scrollTargetBehavior(.paging)` + `scrollPosition(id:)` on a horizontal `ScrollView` + `LazyHStack` is the preferred paged reader pattern (smoother than `TabView(.page)`).
- Reading progress (`lastReadChapterNumber`, `progressPercent`, `lastReadAt`) is written in `ComicReaderView.loadPages()` each time a chapter is opened — not debounced for local SwiftData writes.

## AI Agent Rules

### Required scratchpad workflow

All AI agents must keep reasoning notes in `scratchpad/*.md`.

Rules:
- Create or update a markdown file in `scratchpad/` for task-level thinking.
- Scratchpad notes are for planning, intermediate reasoning, and working assumptions only.
- Use the lowest-capability / lowest-cost model available when generating scratchpad notes.
- Do not use an expensive frontier model for scratchpad drafting.
- Do not place secrets, credentials, tokens, or sensitive user data in scratchpad files.

Suggested naming:
- `scratchpad/claude-YYYY-MM-DD-task-name.md`

### General coding rules

- Read files before changing them.
- Prefer minimum viable edits.
- Keep parsing, heuristics, and scoring out of page components when possible.
- Extend config/feature/store modules before adding UI-only hacks.
- Run `npm run build` after changes.
- Run targeted Playwright coverage for analysis changes when practical.

### Documentation rules

Update docs when these change:
- RuleSheets workflow
- persistence behavior
- logging/observability
- benchmark commands
- major routes or surface behavior
- scratchpad process

## Knowledge Graph Wiki

The `wiki/` directory contains a structured knowledge graph of the entire codebase, inspired by [Karpathy's LLM Knowledge Bases](https://x.com/karpathy/status/2039805659525644595).

- Start with `wiki/INDEX.md` for a complete entity map.
- Read `wiki/SCHEMA.md` for rules on maintaining the wiki.
- When adding new features, models, endpoints, or scrapers, update the relevant wiki pages.
- Entity pages in `wiki/entities/` trace a single entity across all layers (ORM → Schema → DTO → @Model → View).

## Branch and Git Rules

```
main                    ← production releases (god branch, protected)
└── production          ← release candidates, tested and stable
    └── release-1       ← current sprint integration
        └── development ← daily work, feature branches merge here via PR
```

- `main` is the god branch. Protected — only merged from `production`.
- `production` ← merged from `release-1` at end of sprint.
- `release-1` ← merged from `development` when features are stable.
- `development` ← all feature/fix branches branch from here and merge back via PR.
- Never push directly to `main`, `production`, or `release-1`.
- Feature branches: `feature/{name}`, `fix/{description}`, `chore/{task}`
- Do not force-push without explicit approval.
- Do not commit `.env` files or secrets.

### Device targeting (no separate branches needed)
- **Simulator**: `#if targetEnvironment(simulator)` → `localhost:8000`
- **Physical device (debug)**: `#else` in DEBUG → Mac's WiFi IP (`192.168.0.108:8000`)
- **Production (release)**: `#else` → `astral-reader.duckdns.org`
- Change the device IP in `AppConfig.swift` if your Mac's IP changes.
