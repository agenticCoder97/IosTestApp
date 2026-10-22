# ComicFeature Package

> All comic-related views, view models, and services. Depends on Core, Networking, DesignSystem.

## Entities

### Views

| Name | File | Description |
|------|------|-------------|
| ComicTabView | `ComicTabView.swift` | Root comic tab: sidebar drawer + main content area |
| ComicSidebarView | `ComicSidebarView.swift` | Slide-over sidebar: Recents, Library, Read, Browse, Scrapes, Stats |
| ComicLibraryView | `Library/ComicLibraryView.swift` | LazyVGrid 2-column card grid. Pulls comics from ViewModel. Shows BackendStatusBanner on error. EmptyStateView when empty. |
| ComicCardView | `Library/ComicCardView.swift` | Card cell: thumbnail + title + progress bar + favorite heart |
| ComicDetailView | `Library/ComicDetailView.swift` | Story detail: metadata, chapter list, download, delete. Navigates to ComicReaderView on chapter tap. |
| ComicSearchView | `Library/ComicSearchView.swift` | Search comics by title and metadata |
| ComicReaderView | `Reader/ComicReaderView.swift` | Full-screen image reader. Supports webtoon (vertical scroll) and paged (horizontal swipe) modes. HUD overlay with chapter nav, slider, settings. Long press for page actions. |
| ComicBrowserView | `Browser/ComicBrowserView.swift` | WKWebView with source picker (nhentai/toongod/hentai20). Cookie extraction on every navigation finish. Scrape button. ContentBlocker for ads. |
| ComicScrapesView | `Scrapes/ComicScrapesView.swift` | Scrape job list: in-progress, partial, completed, failed. Retry button. Job detail sheet with logs. |
| StatsView | `Stats/StatsView.swift` | Comic statistics dashboard: reading activity, source distribution, backlog tiers |

### ViewModels

| Name | File | Description |
|------|------|-------------|
| ComicLibraryViewModel | `ViewModels/ComicLibraryViewModel.swift` | @Observable. fetchComics() → API → upsert LocalComic + LocalComicChapter into SwiftData. Fetches allProgress on refresh. Handles APIError (cookieRefreshNeeded, URLError). |

### Services

| Name | File | Description |
|------|------|-------------|
| ChapterDownloadService | `Services/ChapterDownloadService.swift` | Downloads chapter page images to Documents directory for offline reading. Checks local pages before API in reader. |
| ComicImagePipeline | `Reader/ComicImagePipeline.swift` | Deduplicates page loads, limits concurrency to two, and keeps a 64 MB / six-image LRU memory cache. Local and remote images use the same background preparation path. |

## Relationships

```mermaid
graph TB
    CTV[ComicTabView] --> CSB[ComicSidebarView]
    CTV --> CLV[ComicLibraryView]
    CTV --> CBV[ComicBrowserView]
    CTV --> CSV[ComicScrapesView]
    CTV --> STV[StatsView]

    CLV --> CLVM[ComicLibraryViewModel]
    CLVM -->|GET /comics| API[APIClient]
    CLVM -->|upsert| SD[(SwiftData)]

    CLV --> CCV[ComicCardView]
    CLV -->|navigate| CDV[ComicDetailView]
    CDV -->|navigate| CRV[ComicReaderView]

    CRV -->|GET .../pages| API
    CRV -->|AsyncImage| NGINX[Static Files]
    CRV -->|check local| CDS[ChapterDownloadService]

    CBV -->|extract cookies| CS[CookieStore]
    CBV -->|POST /scrape| API
    CSV -->|GET /scrape| API
```

## Reader Details

ComicReaderView supports two modes:
- **Webtoon** (vertical): `ScrollView(.vertical)` + `LazyVStack` — continuous vertical strip
- **Paged** (horizontal): `ScrollView(.horizontal)` + `LazyHStack` + `scrollTargetBehavior(.paging)` + `scrollPosition(id:)`

HUD toggled via `simultaneousGesture(LongPressGesture(minimumDuration: 0.5))` — uses simultaneousGesture to avoid blocking scroll.

Tap zones divide the screen into thirds: left (prev page), center (toggle HUD), right (next page).

Page actions on long press: save image, share.

Reading progress written to SwiftData on every chapter open. Backend progress sync via PUT endpoint (partially wired).

### Device image loading (21 October 2026)

- The current page loads first; the reader then prefetches up to two pages ahead and one behind within the same chapter. Obsolete prefetch consumers are cancelled without cancelling a visible consumer of the same image.
- File I/O, image downsampling and eager decoding run off the UI actor. Display images retain zoom headroom, with a maximum target width of 2,560 pixels and a 12-megapixel decoded-image cap for long strips. Saved originals are unchanged. Offscreen rows release their display images; leaving the reader clears its pipeline.
- A completed offline save switches the open reader to local page URLs immediately, retaining page IDs, position and zoom state. Download completion is also observed when the save started elsewhere.
- Prefetching adds no permanent page cache and does not occupy an offline comic slot. The adjustable two-comic default, storage byte budget and pull-to-next/previous handlers are unchanged.
- Minimal verification: Release simulator build; temporary focused checks for deduplication, concurrency, eviction, cancellation/retry, bounded prefetch, tall-image preparation/orientation and unchanged originals; existing pull-state checks. Evidence: `/tmp/astral-comic-image-checks/`. No NSFW sources were exercised and no physical-device frame-rate measurement is claimed.
