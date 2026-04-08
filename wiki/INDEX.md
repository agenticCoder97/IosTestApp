# Astral Knowledge Graph — Index

> Master index of the Astral codebase wiki. Start here.

## How to Use

- **New to the project?** Read [architecture/overview.md](architecture/overview.md) first
- **Understanding a specific entity?** Check [entities/](#entities) for cross-layer traces
- **Debugging a flow?** Check [concepts/](#concepts) for end-to-end pipelines
- **Maintaining this wiki?** Read [SCHEMA.md](SCHEMA.md) for rules

---

## Architecture

- [Overview](architecture/overview.md) — System diagram, tech stack, deployment topology
- [Data Flow](architecture/data-flow.md) — Scrape→store→display, progress sync, image serving, cookie lifecycle
- [Package Dependency Graph](architecture/package-dependency-graph.md) — SPM packages + backend modules

## iOS

- [App Layer](ios/app-layer.md) — AstralApp, RootView, AppState, TabBarView, MorphLandingView
- [Core Package](ios/core-package.md) — SwiftData @Models (LocalComic, LocalFanfic, etc.), AppConfig, AstralLogger
- [Networking Package](ios/networking-package.md) — APIClient, Endpoint catalog (25+ endpoints), CookieStore, all DTOs
- [DesignSystem Package](ios/design-system-package.md) — AstralColors, AstralTypography, 11 UI components
- [ComicFeature Package](ios/comic-feature.md) — Comic views, ComicReaderView (webtoon+paged), ComicLibraryViewModel, ChapterDownloadService
- [FanficFeature Package](ios/fanfic-feature.md) — Fanfic views, FanficReaderView, FanficFilterView, FanficLibraryViewModel

## Backend

- [API Routes](backend/api-routes.md) — 7 routers, full endpoint catalog with methods/paths/responses
- [Services](backend/services.md) — comic_service, fanfic_service, scrape_service, progress_service, stats_service
- [ORM Models](backend/orm-models.md) — 13 SQLAlchemy models, ER diagram, polymorphic FK pattern
- [Scrapers](backend/scrapers.md) — BaseScraper contract + 5 implementations (nhentai, toongod, hentai20, ao3, ffnet)
- [Tasks](backend/tasks.md) — ARQ worker: comic/fanfic scrape tasks, cleanup cron, auto-update cron
- [Infrastructure](backend/infrastructure.md) — Docker, Nginx, Redis, Oracle ADB, block volume, TLS

## Entities

Cross-cutting pages tracing one entity across all layers (ORM → Schema → DTO → @Model → View):

- [Comic](entities/comic.md) — Field mapping across 6 layers, sources, local-only fields
- [Fanfic](entities/fanfic.md) — Richer metadata, server-side filtering, text storage
- [Author](entities/author.md) — Shared across content types, join table pattern
- [Scrape Job](entities/scrape-job.md) — Lifecycle state machine, job types, iOS polling
- [Reading Progress](entities/reading-progress.md) — Dual storage (local + backend), known sync gap

## Concepts

End-to-end flows crossing module boundaries:

- [Cookie Harvest Flow](concepts/cookie-harvest-flow.md) — WKWebView → CookieStore → Redis → curl_cffi
- [Scrape Pipeline](concepts/scrape-pipeline.md) — Browser tap → job creation → worker execution → library refresh
- [Offline Mode](concepts/offline-mode.md) — ChapterDownloadService, local-first reader, storage limits
- [Soft Delete Pattern](concepts/soft-delete-pattern.md) — deleted_at → cleanup cron → hard delete

## Known Issues

- [Empty Tables](known-issues/empty-tables.md) — reading_progress, comic_authors, comic_tags, tags all empty
- [Scraper Bugs](known-issues/scraper-bugs.md) — Toongod domain, FFNet metadata, Hentai20 selectors
