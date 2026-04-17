# AST-12 — Fanfic Thumbnail Fallback: Design Spec

**Date**: 2026-04-17
**Issue**: AST-12
**Branch**: `feature/ast-12-fanfic-thumbnail-fallback`
**Status**: Design / Pre-implementation

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
```

**Response (200 OK)**
```json
{ "path": "fanfic-thumbnails/17.jpg" }
```

**Response schema** (`backend/app/schemas/fanfic_thumbnail.py`):
```python
class RandomThumbnailResponse(BaseModel):
    path: str  # relative to staticBaseURL, e.g. "fanfic-thumbnails/17.jpg"
```

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
- Generates SVG as a Python string (no Pillow needed for basic gradients; Pillow used only to rasterize to JPG).
- Output: `/mnt/astral-media/fanfic-thumbnails/1.jpg` through `50.jpg`.
- Safe to re-run — skips files that already exist (unless `--force`).
- Must be run once during initial deploy and again when curated art is available.

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

Added to `FanficLibraryViewModel.fetchFanfics()` at the end of the existing sync, after `lastSyncTime = .now`:

```swift
// One-off migration: assign thumbnails to fanfics with nil paths
let nilThumbFanfics = allFanfics.filter { $0.thumbnailPath == nil }
for fanfic in nilThumbFanfics {
    if let dto = try? await APIClient.shared.request(.randomFanficThumbnail) as RandomThumbnailResponse {
        fanfic.thumbnailPath = dto.path
    }
}
if !nilThumbFanfics.isEmpty {
    try? modelContext.save()
    AstralLogger.info("Migration: assigned thumbnails to \(nilThumbFanfics.count) fanfics", context: "FanficLibraryVM")
}
```

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

## Risks and Gotchas

1. **Static file caching on iOS**: `URLSession` default cache may cache the image at the resolved URL. Since images are numbered 1–50 and static, this is desirable. No cache-busting needed.
2. **`AppConfig.staticBaseURL` trailing slash**: CLAUDE.md explicitly flags this. The path returned (`fanfic-thumbnails/17.jpg`) has no leading slash. `StoryThumbnail` uses `CachedAsyncImage(remotePath:baseURL:)` — verify `CachedAsyncImage` joins them correctly. If it uses simple string concatenation, `staticBaseURL` must end with `/` (already enforced in config).
3. **CORS**: Static file serving uses FastAPI `StaticFiles` — no CORS headers needed for same-origin WKWebView or URLSession requests.
4. **Seeding script dependencies**: Pillow must be available in the backend Docker image. If not installed, add to `requirements.txt`. Alternative: generate pure JPEG bytes with struct-based JFIF header (avoids dependency), but Pillow is simpler and already likely present.
5. **`fanfic_thumbnails` key conflict with `fanfic` router prefix**: The new router uses prefix `/fanfic-thumbnails` not `/fanfic` — no routing conflict with existing `/fanfic/{id}` routes.
6. **N+1 requests in migration**: If a user has 200 fanfics with nil paths, migration fires 200 sequential requests on first library load. Mitigation: the endpoint is local-LAN-only, sub-1ms latency, no DB hit. Acceptable. Could batch with a `?count=N` variant later if needed.
7. **SwiftData save contention**: Both `syncActiveJobs` and `fetchFanfics` may run concurrently. Both use `try? modelContext.save()` — SwiftData handles concurrent writes on the same context via `@MainActor` isolation.

---

## Testing

### Backend
- Unit test `GET /api/v1/fanfic-thumbnails/random` returns 200 with `path` matching `fanfic-thumbnails/\d+.jpg`.
- Verify `int` is in range [1, 50].
- Test 10 calls return at least 3 distinct values (probabilistic, retry-tolerant).
- Seeding script: verify it creates 50 files, skips existing, respects `--force`.

### iOS
- `StoryThumbnail` with a valid `thumbnailPath` renders an image (not placeholder).
- `StoryThumbnail` with nil path renders `PlaceholderThumbnail`.
- `fetchFanfics` migration: inject a fanfic with nil `thumbnailPath`, mock endpoint returns `{"path": "fanfic-thumbnails/3.jpg"}`, assert path is written and saved.
- `syncActiveJobs`: mock a job transitioning to `"complete"`, assert thumbnail assigned.
- Offline: mock `APIClient` to throw `URLError`, assert `thumbnailPath` stays nil, no crash.

---

## Decisions Made Autonomously

1. **Image sourcing**: Gradient-SVG-generated JPGs (50 files, ~30 KB each) seeded via `backend/scripts/seed_fanfic_thumbnails.py`. Rationale: avoids licensing concerns, matches dark Astral palette, zero external dependencies at runtime, trivially replaceable with curated art by re-running the script with real images.

2. **Server-side randomization**: Endpoint returns a single random path. iOS does no selection. Rationale: simpler iOS code, consistent with the spec direction, and the selection logic lives in one place.

3. **Hook point for new scrapes**: `FanficScrapesView.syncActiveJobs()` polling loop. Rationale: this is the only place that observes scrape-job status transitions; assigning there keeps library ViewModel free of thumbnail-assignment responsibility.

4. **Hook point for migration**: `FanficLibraryViewModel.fetchFanfics()` end-of-sync block. Rationale: already runs on app foreground, has ModelContext, handles URLError, and the `thumbnailPath == nil` guard means it's effectively a one-shot.

5. **No new router prefix collision**: Using `/fanfic-thumbnails` (hyphenated) avoids shadowing the existing `/fanfic` prefix router.
