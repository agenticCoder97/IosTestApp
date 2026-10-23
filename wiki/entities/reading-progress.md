# Entity: Reading Progress

> Tracks where the user left off in a comic or fanfic. Exists on both backend and iOS.

## Layer Map

| Layer | Type | File |
|-------|------|------|
| Backend ORM | ReadingProgress | `backend/app/models/progress.py` |
| Backend Schema | ProgressResponse | `backend/app/schemas/progress.py` |
| iOS DTO | ComicProgressRequest | `Packages/Networking/.../DTOs/ProgressDTOs.swift` |
| iOS DTO | FanficProgressRequest | `Packages/Networking/.../DTOs/ProgressDTOs.swift` |
| iOS DTO | ProgressResponse | `Packages/Networking/.../DTOs/ProgressDTOs.swift` |
| iOS Model | LocalComic fields | `Packages/Core/.../Models/LocalComic.swift` |
| iOS Model | LocalFanfic fields | `Packages/Core/.../Models/LocalFanfic.swift` |

## How Progress is Stored

### Device-owned reading positions (22 October 2026)

`ios/Astral/Packages/Core/Sources/Core/Services/ReadingPositionStore.swift` stores per-story, per-chapter checkpoints in preferences using chapter UUIDs. Comic webtoon checkpoints also preserve the offset within a source page when the viewport, skipped-page count and page count match. Otherwise the reader resumes at the logical source page. Explicit page jumps and chapter restart discard the old offset. Fanfic checkpoints retain their existing paragraph, fraction and layout-compatible pixel offset.

`ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift` uses UUID bookmark anchors before the legacy chapter-number fallback, keeping alternate releases with identical chapter numbers independent. See [reader and local-file reliability](../../docs/2026-10-22-reader-and-local-file-reliability.md) for verification scope and remaining runtime checks.

### Backend (ReadingProgress table)
- content_type + story_id (polymorphic)
- last_chapter_number
- last_page_number (comics)
- scroll_offset_percent (fanfics)
- updated_at

### iOS (denormalized on @Model)
- LocalComic: lastReadChapterNumber, lastReadPageNumber, progressPercent, lastReadAt, completedAt
- LocalFanfic: (similar fields)

## Historical Backend Review: Progress Not Synced

The following records the earlier server-backed architecture review; it is not a current inspection of a running backend. The current library is device-owned and does not require a companion.

**Status:** The `reading_progress` backend table is empty.

**Root cause:** ComicReaderView and FanficReaderView write progress to local SwiftData only. The PUT endpoints exist and work, the iOS Endpoint definitions exist, but they are never called from the reader views.

**What works:**
- `GET /progress` (allProgress) IS called by LibraryViewModels on refresh to hydrate from server
- Local SwiftData writes happen on every chapter open

**What's missing:**
- ComicReaderView.loadPages() should call `APIClient.shared.request(.updateComicProgress(...))` after SwiftData save
- FanficReaderView should call `APIClient.shared.request(.updateFanficProgress(...))` after SwiftData save
- Should respect the 5s debounce rule from CLAUDE.md

See [known-issues/empty-tables.md](../known-issues/empty-tables.md) for full details.

## Progress Flow (intended)

```mermaid
graph LR
    READER[ReaderView] -->|write| SD[(SwiftData local)]
    READER -->|PUT /progress/:id| API[Backend API]
    API --> DB[(ReadingProgress table)]

    LIB[LibraryViewModel<br/>on refresh] -->|GET /progress| API
    API --> LIB
    LIB -->|hydrate| SD
```
