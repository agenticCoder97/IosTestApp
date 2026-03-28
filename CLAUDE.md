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
