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
