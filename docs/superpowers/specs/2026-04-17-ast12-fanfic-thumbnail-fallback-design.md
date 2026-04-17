# AST-12 — Fanfic Thumbnail Fallback: Design Spec

**Date**: 2026-04-17
**Issue**: AST-12
**Branch**: `feature/ast-12-fanfic-thumbnail-fallback`
**Status**: Design / Pre-implementation — open questions answered 2026-04-17

---

## Summary

Fanfic library cards render blank colored placeholders because `LocalFanfic.thumbnailPath` is almost never populated for scraped fanfics. This spec describes a server-side random-thumbnail endpoint, 50 gradient-SVG-based seed images, iOS integration at the right hook point (scrape finalization poll), and a one-pass migration for existing fanfics with nil paths.

---

## Goals

1. Every fanfic in the library has a visually distinct thumbnail within one app launch after scrape completion.
2. Backend serves random paths — iOS does no selection logic.
3. Backend unreachable at assignment time is fully silent — `PlaceholderThumbnail` continues to render.
4. Seed images are lightweight enough to keep in the Docker volume without significant IO cost.
5. The solution is additive — zero changes to existing scrape flow timing or the `FanficResponse` DTO shape.

---

## Non-Goals

- Changing how `thumbnailPath` is stored on the backend `Fanfic` ORM model (field already exists).
- Scraping cover art from AO3 or FFNet (no consistent image on those pages).
- Bundling images with the IPA.
- User ability to choose or upload thumbnails.
- Any CDN or cache-busting infrastructure (images are static).

---

## Backend API Design

### New router file
`backend/app/api/v1/routes/fanfic_thumbnails.py`

Mounted in `main.py` alongside existing routers:
```python
from app.api.v1.routes import fanfic_thumbnails
app.include_router(fanfic_thumbnails.router, prefix="/api/v1")
```

### Endpoint

```
GET /api/v1/fanfic-thumbnails/random
GET /api/v1/fanfic-thumbnails/random?count=N
```

**Query parameter `count`** (optional, default `1`): integer in range [1, 50]. Capped at `FANFIC_THUMBNAIL_COUNT = 50`. Values > 50 are clamped to 50. Enables the iOS migration to fetch N random paths in a single round-trip.

**Response — single (count absent or count=1, 200 OK)**
```json
{ "path": "fanfic-thumbnails/17.jpg" }
```

**Response — batch (count > 1, 200 OK)**
```json
{ "paths": ["fanfic-thumbnails/17.jpg", "fanfic-thumbnails/3.jpg", "fanfic-thumbnails/42.jpg"] }
```

**Response schema** (`backend/app/schemas/fanfic_thumbnail.py`):
```python
class RandomThumbnailResponse(BaseModel):
    path: str  # present when count=1 (or absent); relative to staticBaseURL

class RandomThumbnailBatchResponse(BaseModel):
    paths: list[str]  # present when count > 1; length == min(count, 50)
```

The endpoint returns `RandomThumbnailResponse` when `count` is absent or `1`, and `RandomThumbnailBatchResponse` when `count > 1`. Paths are sampled with replacement from `random.randint(1, FANFIC_THUMBNAIL_COUNT)`.

**Implementation**: `random.randint(1, FANFIC_THUMBNAIL_COUNT)` where `FANFIC_THUMBNAIL_COUNT = 50`. No DB query needed. The endpoint is stateless.

**Error handling**: No 4xx/5xx expected — it is pure computation. If the thumbnails directory is missing on disk the static server would 404 when iOS fetches the image, which is the correct degradation path (iOS falls back to `PlaceholderThumbnail` via `CachedAsyncImage` failure).

**Rate limiting**: Not warranted. The endpoint is hit at most once per fanfic creation or migration pass. No ARQ job needed. The endpoint is idempotent — iOS may call it again on retry without side effects.

**No auth required**: Consistent with the existing pattern — no bearer token on any Astral API endpoint (private LAN + sideloaded app assumption).

### Static file serving

Files already served by the existing `StaticFiles` mount in `main.py`:
```python
app.mount("/static", StaticFiles(directory=settings.block_volume_path), name="static")
```
`block_volume_path` defaults to `/tmp/astral-media` (dev) and `/mnt/astral-media` (OCI). No change needed.

iOS constructs the full URL as:
```
AppConfig.staticBaseURL + "fanfic-thumbnails/17.jpg"
```
which resolves to e.g. `http://192.168.0.108:8000/static/fanfic-thumbnails/17.jpg`.

---

## Image Sourcing Plan

**Decision (autonomous)**: Generate 50 gradient-based SVG thumbnails at startup and rasterize to 400×600 JPG at seeding time using a one-off Python script. These are placeholder seeds, styled to match the Astral dark theme (using the same 6-color palette as `PlaceholderThumbnail`). A `TODO` comment marks where curated art should replace them.

**Palette** (matches iOS `PlaceholderThumbnail` colors):
```
#2A2A4A  deep indigo
#4A2A2A  deep burgundy
#2A4A34  deep forest
#40324A  deep plum
#324044  deep teal
#3A3A2A  deep olive
```

**50 images** = 6 base colors × ~8 gradient directions + some with overlay symbols (book, scroll, quill glyphs as Unicode text rendered at large size). Each JPG < 30 KB at 400×600 with 70% JPEG quality.

**Seeding script**: `backend/scripts/seed_fanfic_thumbnails.py`
- Generates gradient JPGs using Pillow (rasterization to 400×600 JPG).
- Output: `/mnt/astral-media/fanfic-thumbnails/1.jpg` through `50.jpg`.
- Safe to re-run — skips files that already exist (unless `--force`).
- Must be run once during initial deploy and again when curated art is available.

**Backend dependencies**: `Pillow>=10.0` must be present in `backend/requirements.txt`. Add the following line if not already present:
```
Pillow>=10.0
```
This is required for the seeding script; it is not a runtime dependency of the FastAPI app itself.

**docker-compose.local.yml note**: A `volumes` entry already mounts `astral_media` at `/mnt/astral-media`. The script runs against that path inside the backend container via:
```bash
docker compose exec backend python scripts/seed_fanfic_thumbnails.py
```

---

## iOS Integration

### New DTO

Add to `ios/Astral/Packages/Networking/Sources/Networking/DTOs/FanficDTOs.swift`:
```swift
public struct RandomThumbnailResponse: Codable, Sendable {
    public let path: String
}
```

### New Endpoint

Add to `ios/Astral/Packages/Networking/Sources/Networking/Endpoints.swift` under the Fanfic section:
```swift
static var randomFanficThumbnail: Endpoint {
    Endpoint(path: "/fanfic-thumbnails/random")
}
```

### New APIClient helper

The standard `APIClient.request<T>` method handles this without change. Call site:
```swift
let dto: RandomThumbnailResponse = try await APIClient.shared.request(.randomFanficThumbnail)
fanfic.thumbnailPath = dto.path
```

### Hook point: `FanficScrapesView.syncActiveJobs()`

The right place to assign a thumbnail is when a scrape job transitions to `"complete"` or `"partial"` status AND the associated `LocalFanfic.thumbnailPath == nil`. This is in the existing polling loop in `FanficScrapesView.syncActiveJobs()`, which already upserts scrape job state every 5 seconds.

**After** the existing job-status upsert loop, add:
```swift
// Assign fallback thumbnails for newly-completed fanfics with nil paths
for job in fanficJobs where (job.status == "complete" || job.status == "partial") {
    guard let fanfic = fanfics.first(where: { $0.id == job.storyId }),
          fanfic.thumbnailPath == nil else { continue }
    if let dto = try? await APIClient.shared.request(.randomFanficThumbnail) as RandomThumbnailResponse {
        fanfic.thumbnailPath = dto.path
    }
}
try? modelContext.save()
```

**Rationale for this hook point vs. alternatives**:
- `FanficBrowserViewModel.extractCookiesAndScrape()` — too early; scrape is still queued, `LocalFanfic` may not exist yet.
- `FanficLibraryViewModel.fetchFanfics()` — wrong owner; this runs every 2 minutes and would re-fetch for every library load. Thumbnail assignment is a one-time side-effect, not a library concern.
- `FanficScrapesView.syncActiveJobs()` — polling already runs every 5s; this is the right "scrape just completed" detector. Assignment fires at most once per fanfic (guarded by `thumbnailPath == nil`).

### Migration: existing fanfics with nil thumbnailPath

Added to `FanficLibraryViewModel.fetchFanfics()` at the end of the existing sync, after `lastSyncTime = .now`.

**Batch approach** (replaces the previous N-sequential-call approach): iOS fetches all N random paths in a single round-trip using `?count=N`, then assigns them one-per-fanfic locally. This avoids N sequential HTTP calls for users with many existing fanfics.

```swift
// One-off migration: assign thumbnails to fanfics with nil paths (batch variant)
let nilThumbFanfics = allFanfics.filter { $0.thumbnailPath == nil }
if !nilThumbFanfics.isEmpty {
    let count = min(nilThumbFanfics.count, 50)
    AstralLogger.info("Migration: \(nilThumbFanfics.count) fanfics need thumbnails", context: "FanficLibraryVM")
    if let batch: RandomThumbnailBatchResponse = try? await APIClient.shared.request(
        .randomFanficThumbnails(count: count)
    ) {
        for (fanfic, path) in zip(nilThumbFanfics, batch.paths) {
            fanfic.thumbnailPath = path
        }
        // If more than 50 fanfics need thumbnails, remaining stay nil until next library open
        try? modelContext.save()
        AstralLogger.info("Migration: thumbnail assignment complete", context: "FanficLibraryVM")
    }
}
```

A second pass on next library open handles any fanfics beyond the 50-cap (capped by the server). In practice, a user with > 50 fanfics with nil paths is the very first migration run; subsequent runs will have at most a handful to assign.

**Why in `fetchFanfics` not `RootView.onAppear`**: `fetchFanfics` already has the `ModelContext`, runs under `@MainActor`, and already handles URLError gracefully. The migration guard is `thumbnailPath == nil` — once assigned, it never re-runs for that fanfic. Runs on every library load but only does work when needed.

**Backend unreachable**: Both hook points use `try?` — failure is silently swallowed. `thumbnailPath` stays nil; `StoryThumbnail` renders `PlaceholderThumbnail`. No user-visible error.

---

## Migration Strategy

| Scenario | Behavior |
|---|---|
| Fresh install, no fanfics | No-op |
| Existing fanfics, thumbnailPath nil | `fetchFanfics` migration assigns on next library open |
| New scrape completed | `syncActiveJobs` assigns within ~5s of completion |
| Backend unreachable | Silent no-op, PlaceholderThumbnail renders |
| thumbnailPath already set | Neither hook assigns — guarded by `== nil` check |
| Images not yet seeded on disk | Static file 404 → `CachedAsyncImage` fails → PlaceholderThumbnail |

---

## Pre-implementation Checks

Before writing code, verify each of the following:

1. **`CachedAsyncImage` 404 audit**: Read `ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/CachedAsyncImage.swift` (or wherever it lives). Confirm that an HTTP 404 from the static server does not crash the app — it must fall through silently to `PlaceholderThumbnail`. If it crashes or hangs on 404, add a guard before proceeding to Tasks 3–5.

2. **`AppConfig.staticBaseURL` trailing `/` audit**: Read `ios/Astral/Packages/Core/Sources/Core/AppConfig.swift`. Verify that all three environment branches (`#if targetEnvironment(simulator)`, `#else DEBUG`, and release) set `staticBaseURL` with a trailing `/`. A missing trailing slash produces `"/staticfanfic-thumbnails/..."` 404s. Fix any branch that is missing it before implementing the iOS tasks.

---

## Risks and Gotchas

1. **Static file caching on iOS**: `URLSession` default cache may cache the image at the resolved URL. Since images are numbered 1–50 and static, this is desirable. No cache-busting needed.
2. **`AppConfig.staticBaseURL` trailing slash**: CLAUDE.md explicitly flags this. The path returned (`fanfic-thumbnails/17.jpg`) has no leading slash. `StoryThumbnail` uses `CachedAsyncImage(remotePath:baseURL:)` — `staticBaseURL` must end with `/` in all three environment branches (simulator, device, prod). See Pre-implementation Checks above.
3. **CORS**: Static file serving uses FastAPI `StaticFiles` — no CORS headers needed for same-origin WKWebView or URLSession requests.
4. **Seeding script dependencies**: `Pillow>=10.0` is required in `backend/requirements.txt` (decision: add it). See Backend Dependencies section in Image Sourcing Plan.
5. **`fanfic_thumbnails` key conflict with `fanfic` router prefix**: The new router uses prefix `/fanfic-thumbnails` not `/fanfic` — no routing conflict with existing `/fanfic/{id}` routes.
6. **Migration N+1 resolved**: The `?count=N` batch endpoint eliminates sequential per-fanfic requests. The iOS migration issues one HTTP call for up to 50 fanfics. Fanfics beyond 50 are handled on the next library open (max 50 per pass, limited by the server cap).
7. **SwiftData save contention**: Both `syncActiveJobs` and `fetchFanfics` may run concurrently. Both use `try? modelContext.save()` — SwiftData handles concurrent writes on the same context via `@MainActor` isolation.

---

## Testing

### Backend
- Unit test `GET /api/v1/fanfic-thumbnails/random` (no count) returns 200 with `path` matching `fanfic-thumbnails/\d+.jpg`.
- Verify `int` is in range [1, 50].
- Test 10 calls return at least 3 distinct values (probabilistic, retry-tolerant).
- `GET /api/v1/fanfic-thumbnails/random?count=5` returns 200 with `paths` array of length 5, each matching `fanfic-thumbnails/\d+.jpg`.
- `?count=60` is clamped to 50 — response `paths` length is 50.
- `?count=1` returns `RandomThumbnailResponse` (single `path` field, not batch).
- Seeding script: verify it creates 50 files, skips existing, respects `--force`.

### iOS
- `StoryThumbnail` with a valid `thumbnailPath` renders an image (not placeholder).
- `StoryThumbnail` with nil path renders `PlaceholderThumbnail`.
- `fetchFanfics` migration (batch): inject 3 fanfics with nil `thumbnailPath`, mock batch endpoint returns `{"paths": ["fanfic-thumbnails/3.jpg", "fanfic-thumbnails/7.jpg", "fanfic-thumbnails/12.jpg"]}`, assert all 3 paths are written and saved.
- `syncActiveJobs`: mock a job transitioning to `"complete"`, assert thumbnail assigned via single-path endpoint.
- Offline: mock `APIClient` to throw `URLError`, assert `thumbnailPath` stays nil, no crash.
- `CachedAsyncImage` 404: confirm component falls through to nil/failure state without crashing (pre-implementation check).

---

## Answered Open Questions (2026-04-17)

The following questions were resolved by user input and are now reflected throughout this spec:

1. **Pillow dependency** — Yes: add `Pillow>=10.0` to `backend/requirements.txt`. The seeding script requires it.
2. **`CachedAsyncImage` 404 handling** — Yes: add a pre-implementation audit task. If it crashes on 404, fix before proceeding.
3. **Batch migration endpoint** — Yes: add `?count=N` to `GET /api/v1/fanfic-thumbnails/random`. iOS migration uses one batch call instead of N sequential calls. Default `count=1` (absent param) keeps existing single-path response shape.
4. **`AppConfig.staticBaseURL` trailing slash** — Yes: audit all three environment branches (simulator, device debug, prod release) before implementing iOS tasks.

---

## Decisions Made Autonomously

1. **Image sourcing**: Gradient-SVG-generated JPGs (50 files, ~30 KB each) seeded via `backend/scripts/seed_fanfic_thumbnails.py`. Rationale: avoids licensing concerns, matches dark Astral palette, zero external dependencies at runtime, trivially replaceable with curated art by re-running the script with real images.

2. **Server-side randomization**: Endpoint returns a single random path. iOS does no selection. Rationale: simpler iOS code, consistent with the spec direction, and the selection logic lives in one place.

3. **Hook point for new scrapes**: `FanficScrapesView.syncActiveJobs()` polling loop. Rationale: this is the only place that observes scrape-job status transitions; assigning there keeps library ViewModel free of thumbnail-assignment responsibility.

4. **Hook point for migration**: `FanficLibraryViewModel.fetchFanfics()` end-of-sync block. Rationale: already runs on app foreground, has ModelContext, handles URLError, and the `thumbnailPath == nil` guard means it's effectively a one-shot.

5. **No new router prefix collision**: Using `/fanfic-thumbnails` (hyphenated) avoids shadowing the existing `/fanfic` prefix router.
