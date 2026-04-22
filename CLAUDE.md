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
- MangaDex source (AST-30) — env vars:
  - `MANGADEX_DISABLED=true|false` — kill switch. Hard-stops new mangadex scrapes (HTTP 503), silently disables the matcher for toongod/hentai20 adds.
  - `MANGADEX_TITLE_MATCH_THRESHOLD=0.85` — minimum confidence for the match-confirm dialog.
  - `MANGADEX_AUTO_SWITCH_SOURCE=true|false` — master toggle for the matcher.
  - OAuth2 personal-client login for the `pornographic` content rating is tracked in AST-35 (not in v1).
- FFNet scraper (AST-29) — env vars:
  - `FFNET_NEW_SCRAPER_DISABLED=true|false` — kill switch. Set to `true` to skip FanFicFare and serve all FFNet scrapes through FicHub (the fallback tier). Default `false`. Useful when FFF breaks on a future site change.
- Monitor dashboard control plane (AST-70..77) — env vars:
  - `MONITOR_CONTROL_TOKEN` — **required** on the monitor container to enable all `/control/*` endpoints (kill switches, service restart, ARQ retry, on-demand backup, SQL console). Absent → endpoints return HTTP 503. Paste the same token into the dashboard on first use; it's saved in browser localStorage.
  - `MONITOR_READONLY_DSN` — Postgres DSN for the read-only SQL console. Defaults to `postgresql://astral_readonly:astral_readonly@postgres:5432/astral`. The `astral_readonly` role is created by the `a3b4c5d6e7f8` migration and has SELECT-only grants + a 10s statement_timeout.
  - `ASTRAL_READONLY_PASSWORD` — password baked into the role at migration time. Default `astral_readonly`; rotate in prod.
  - `MONITOR_STATE_DIR` — audit log, on-demand backup dumps, and `deploys.jsonl` live here. Defaults to `/var/lib/astral-monitor`. Mounted via the `monitor_state` named volume.
- Kill-switch persistence: the three boolean flags (`MANGADEX_DISABLED`, `FFNET_NEW_SCRAPER_DISABLED`, `MANGADEX_AUTO_SWITCH_SOURCE`) can be toggled live from the monitor dashboard. Values stored at `mon:flag:<KEY>` in Redis. Main app + scrapers read via `app.core.runtime_flags.flag_enabled()` — Redis override wins, falls back to `settings.<flag>` (5s in-process cache).
- Monitor `/var/run/docker.sock` mount: now **read-write** (not `:ro`) so the control plane can restart containers and exec `pg_dump`. Every mutating endpoint is gated by `MONITOR_CONTROL_TOKEN`.
- Deploy hook: `backend/scripts/deploy-hook.sh` is called at the end of a successful `docker-compose up -d`. Polls `/healthz` + `/health`, then appends a record to `/var/lib/astral-monitor/deploys.jsonl`. Surfaced in the "Recent deploys" block.

## Production (OCI) Access

- **SSH:** `ssh -i ~/.ssh/astral_oci ubuntu@astral-reader.duckdns.org` (user `ubuntu`, NOT `opc` — OCI rejects `opc` and prints "Please login as the user 'ubuntu'").
- **Host:** `astral-server` (OCI Always Free A1 ARM instance).
- **Compose root:** `/home/ubuntu/astral/backend/` — all `docker compose` commands must run from there. Containers are named `backend-<service>-1` (e.g., `backend-astral_monitor-1`).
- **Env file:** `/home/ubuntu/astral/backend/.env` — add new env vars here, then `docker compose up -d --no-deps <service>` to pick them up without restarting the whole stack.
- **Logs:** `docker compose logs -f <service>` for live tail. The monitor dashboard's Live log panel (/monitor/, AST-73) is the preferred in-browser surface.
- **Nginx config:** lives under `/home/ubuntu/astral/backend/nginx/` and is volume-mounted into the nginx container. Reload with `docker compose exec nginx nginx -s reload` after edits.
- **Do not run `alembic upgrade head` on prod without explicit user approval.** Read-only roles (e.g., `astral_readonly` from migration `a3b4c5d6e7f8`) need the `ASTRAL_READONLY_PASSWORD` env var set **before** the migration is applied.

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
- **ALWAYS branch new work from `development`. NEVER branch from `main`, `production`, or `release-1`.** `main` is eight merges behind `development` in practice; branching from it creates spurious diffs and merge conflicts.
- Never push directly to `main`, `production`, or `release-1`.
- Feature branches: `feature/{name}`, `fix/{description}`, `chore/{task}`
- Do not force-push without explicit approval.
- Do not commit `.env` files or secrets.

### Linear integration

- Linear team **Astral** (key `AST`) — issues look like `AST-123`.
- Project: [Astral on Linear](https://linear.app/nnetraganti/project/astral-8efbeb753255).
- **Branch naming**: `feature/ast-123-short-description`, `fix/ast-456-description`, `chore/ast-789-description` — the `ast-NNN` slug in the branch name auto-links the branch to the Linear issue.
- **Commit messages**: include the issue ID, e.g. `[ios] AST-123 fix scroll bug in fanfic reader`. Linear backfills commits into the issue timeline.
- **PR descriptions**: use a magic word + issue ID on its own line to auto-close the issue on merge:
  - `Fixes AST-123`
  - `Closes AST-123`
  - `Resolves AST-123`
- Multiple issues: one magic-word line per issue (`Fixes AST-123`, `Fixes AST-124`). The branch name only auto-closes the issue in its slug (e.g. `feature/ast-123-*` closes AST-123 only) — for a bundled PR that touches several issues, each must appear as its own `Fixes AST-NNN` line in the **PR body** (not just the commit message; Linear parses the PR description, not commit messages, for multi-close).

### Release log

- Add a brief entry to [CHANGELOG.md](CHANGELOG.md) at the repo root whenever you merge a feature/fix PR into `development`. Most recent first; the PR body has the detail, the changelog is the index.

### Device targeting (no separate branches needed)
- **Simulator**: `#if targetEnvironment(simulator)` → `localhost:8000`
- **Physical device (debug)**: `#else` in DEBUG → Mac's WiFi IP (`192.168.0.108:8000`)
- **Production (release)**: `#else` → `astral-reader.duckdns.org`
- Change the device IP in `AppConfig.swift` if your Mac's IP changes.
