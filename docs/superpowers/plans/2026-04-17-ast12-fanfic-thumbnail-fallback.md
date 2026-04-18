# AST-12 — Fanfic Thumbnail Fallback: Implementation Plan

**Date**: 2026-04-17
**Issue**: AST-12
**Spec**: `docs/superpowers/specs/2026-04-17-ast12-fanfic-thumbnail-fallback-design.md`
**Branch**: `feature/ast-12-fanfic-thumbnail-fallback`

---

## Task 0a — Audit: `CachedAsyncImage` 404 handling

### Files

- **Read-only audit**: `ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/CachedAsyncImage.swift` (or wherever `CachedAsyncImage` is defined — search `DesignSystem` package if path differs)

### Verification

Open the file and confirm:
- An HTTP 404 response from the static server does **not** crash or hang the view.
- The component falls through to its failure/placeholder state silently.
- If `AsyncImage` or a custom `URLSession` fetch is used, check that the `.failure` phase is handled.

### Action

- If 404 is already handled gracefully: no code change, leave a note in the commit message.
- If 404 causes a crash or uncaught error: add a `.onFailure` / phase-check guard before continuing to Tasks 2–6.

### Commit message (only if fix needed)
```
[ios] AST-12 guard CachedAsyncImage against 404 with silent failure
```

---

## Task 0b — Audit: `AppConfig.staticBaseURL` trailing `/`

### Files

- **Read-only audit**: `ios/Astral/Packages/Core/Sources/Core/AppConfig.swift`

### Verification

Read `AppConfig.swift` and check all three environment branches:
1. `#if targetEnvironment(simulator)` — `staticBaseURL` should end with `/`
2. `#else` in `DEBUG` (physical device) — `staticBaseURL` should end with `/`
3. Release build branch — `staticBaseURL` should end with `/`

A missing trailing slash produces concatenated URLs like `"/staticfanfic-thumbnails/3.jpg"` which 404s.

### Action

- If all three branches already have trailing `/`: no code change.
- If any branch is missing it: add the trailing `/` and commit.

### Commit message (only if fix needed)
```
[ios] AST-12 ensure staticBaseURL has trailing slash in all env branches
```

---

## Task 1 — Backend: `GET /api/v1/fanfic-thumbnails/random` endpoint

### Files

- **New**: `backend/app/schemas/fanfic_thumbnail.py`
- **New**: `backend/app/api/v1/routes/fanfic_thumbnails.py`
- **Modify**: `backend/app/main.py` — add `include_router` call
- **Modify**: `backend/app/api/v1/routes/__init__.py` (if exists) or just import directly in main.py

### Code

**`backend/app/schemas/fanfic_thumbnail.py`**
```python
from pydantic import BaseModel

FANFIC_THUMBNAIL_COUNT = 50

class RandomThumbnailResponse(BaseModel):
    path: str  # returned when count=1 or count absent

class RandomThumbnailBatchResponse(BaseModel):
    paths: list[str]  # returned when count > 1; length == min(count, 50)
```

**`backend/app/api/v1/routes/fanfic_thumbnails.py`**
```python
import random
from typing import Union
from fastapi import APIRouter, Query
from app.schemas.fanfic_thumbnail import (
    RandomThumbnailResponse,
    RandomThumbnailBatchResponse,
    FANFIC_THUMBNAIL_COUNT,
)

router = APIRouter(prefix="/fanfic-thumbnails", tags=["fanfic-thumbnails"])

@router.get("/random")
async def random_fanfic_thumbnail(
    count: int = Query(default=1, ge=1, le=FANFIC_THUMBNAIL_COUNT),
) -> Union[RandomThumbnailResponse, RandomThumbnailBatchResponse]:
    if count == 1:
        n = random.randint(1, FANFIC_THUMBNAIL_COUNT)
        return RandomThumbnailResponse(path=f"fanfic-thumbnails/{n}.jpg")
    paths = [f"fanfic-thumbnails/{random.randint(1, FANFIC_THUMBNAIL_COUNT)}.jpg"
             for _ in range(count)]
    return RandomThumbnailBatchResponse(paths=paths)
```

Note: FastAPI's `Query(ge=1, le=50)` enforces the cap server-side — no manual clamping needed. Values > 50 return 422 Unprocessable Entity.

**Add to `backend/app/main.py`** (after existing imports line):
```python
from app.api.v1.routes import fanfic_thumbnails
# ...
app.include_router(fanfic_thumbnails.router, prefix="/api/v1")
```

### Commit message
```
[backend] AST-12 add GET /api/v1/fanfic-thumbnails/random endpoint with ?count=N batch support
```

---

## Task 2 — Backend: image seeding script + Pillow dependency

### Files

- **New**: `backend/scripts/seed_fanfic_thumbnails.py`
- **Modify**: `backend/requirements.txt` — add `Pillow>=10.0` if not already present

### Code

Script generates 50 gradient JPGs (400×600) using Pillow. Uses the 6 Astral dark-theme colors. Each image has a gradient direction and an optional Unicode glyph overlay (book/scroll/quill symbol at large size in white at low opacity).

```python
#!/usr/bin/env python3
"""
Seed 50 fanfic thumbnail JPGs into the astral_media volume.
Usage: python scripts/seed_fanfic_thumbnails.py [--force] [--output-dir /path]

Requires: Pillow (`pip install pillow`)
"""
import argparse
import os
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

COLORS = [
    (0x2A, 0x2A, 0x4A),  # deep indigo
    (0x4A, 0x2A, 0x2A),  # deep burgundy
    (0x2A, 0x4A, 0x34),  # deep forest
    (0x40, 0x32, 0x4A),  # deep plum
    (0x32, 0x40, 0x44),  # deep teal
    (0x3A, 0x3A, 0x2A),  # deep olive
]
GLYPHS = ["📖", "📜", "✒️", "🌟", "📚", "🖊️", "🌙", "⭐"]
WIDTH, HEIGHT = 400, 600
COUNT = 50

def make_gradient(color_top, color_bot, size=(WIDTH, HEIGHT)):
    img = Image.new("RGB", size)
    for y in range(size[1]):
        t = y / size[1]
        r = int(color_top[0] * (1 - t) + color_bot[0] * t)
        g = int(color_top[1] * (1 - t) + color_bot[1] * t)
        b = int(color_top[2] * (1 - t) + color_bot[2] * t)
        ImageDraw.Draw(img).line([(0, y), (size[0], y)], fill=(r, g, b))
    return img

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--output-dir", default="/mnt/astral-media/fanfic-thumbnails")
    args = parser.parse_args()

    out = Path(args.output_dir)
    out.mkdir(parents=True, exist_ok=True)

    for n in range(1, COUNT + 1):
        dest = out / f"{n}.jpg"
        if dest.exists() and not args.force:
            print(f"  skip {dest.name} (exists)")
            continue
        color_a = COLORS[(n - 1) % len(COLORS)]
        color_b = COLORS[n % len(COLORS)]
        img = make_gradient(color_a, color_b)
        # Overlay glyph at 30% opacity
        draw = ImageDraw.Draw(img, "RGBA")
        glyph = GLYPHS[(n - 1) % len(GLYPHS)]
        draw.text((WIDTH // 2, HEIGHT // 2), glyph, fill=(255, 255, 255, 77),
                  anchor="mm", font=ImageFont.load_default(size=80))
        img.save(dest, "JPEG", quality=70, optimize=True)
        print(f"  wrote {dest.name}")

    print(f"Done — {COUNT} thumbnails in {out}")

if __name__ == "__main__":
    main()
```

**Run in container**:
```bash
docker compose exec backend python scripts/seed_fanfic_thumbnails.py
```

**TODO**: Replace generated images with curated manga/book-cover art by dropping real 400×600 JPGs named `1.jpg`–`50.jpg` into the volume and re-running with `--force`.

### Pillow dependency step

Before writing the seeding script, add `Pillow>=10.0` to `backend/requirements.txt`:
```
Pillow>=10.0
```
Check if it's already present first (`grep -i pillow backend/requirements.txt`). Only add if absent. This is a script-time dependency — the FastAPI app itself does not import Pillow at runtime.

### Commit message
```
[backend] AST-12 add thumbnail seeding script (50 gradient JPGs) and Pillow>=10.0 dep
```

---

## Task 3 — iOS: DTO + APIClient endpoint

### Files

- **Modify**: `ios/Astral/Packages/Networking/Sources/Networking/DTOs/FanficDTOs.swift`
- **Modify**: `ios/Astral/Packages/Networking/Sources/Networking/Endpoints.swift`

### Code

**FanficDTOs.swift** — add at bottom:
```swift
public struct RandomThumbnailResponse: Codable, Sendable {
    public let path: String
}

public struct RandomThumbnailBatchResponse: Codable, Sendable {
    public let paths: [String]
}
```

**Endpoints.swift** — add inside `public extension Endpoint` Fanfic section:
```swift
static var randomFanficThumbnail: Endpoint {
    Endpoint(path: "/fanfic-thumbnails/random")
}

static func randomFanficThumbnails(count: Int) -> Endpoint {
    Endpoint(path: "/fanfic-thumbnails/random?count=\(count)")
}
```

### Commit message
```
[ios] AST-12 add RandomThumbnailResponse/Batch DTOs and randomFanficThumbnail(s) endpoints
```

---

## Task 4 — iOS: scrape-finalize thumbnail assignment

### Files

- **Modify**: `ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Scrapes/FanficScrapesView.swift`

### Code

In `FanficScrapesView.syncActiveJobs()`, after the existing job-status upsert loop and before `try? modelContext.save()`:

```swift
// AST-12: assign fallback thumbnails for newly-completed fanfics with nil paths
for job in fanficJobs where job.status == "complete" || job.status == "partial" {
    guard let fanfic = fanfics.first(where: { $0.id == job.storyId }),
          fanfic.thumbnailPath == nil else { continue }
    if let dto: RandomThumbnailResponse = try? await APIClient.shared.request(.randomFanficThumbnail) {
        fanfic.thumbnailPath = dto.path
        AstralLogger.info("Assigned thumbnail \(dto.path) to fanfic \(fanfic.id)", context: "FanficScrapes")
    }
}
```

### Commit message
```
[ios] AST-12 assign fallback thumbnail when scrape completes and path is nil
```

---

## Task 5 — iOS: migration for existing fanfics (batch)

### Files

- **Modify**: `ios/Astral/Packages/FanficFeature/Sources/FanficFeature/ViewModels/FanficLibraryViewModel.swift`

### Code

At the end of the `do` block in `fetchFanfics()`, after `lastSyncTime = .now`:

```swift
// AST-12: one-off migration — assign thumbnails to fanfics with nil paths (batch)
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
        // Fanfics beyond the 50-cap stay nil and are handled on the next library open
        try? modelContext.save()
        AstralLogger.info("Migration: thumbnail assignment complete", context: "FanficLibraryVM")
    }
}
```

**Why batch instead of sequential**: Single HTTP round-trip for up to 50 fanfics. The server returns N distinct (with-replacement) paths in one response. The iOS `zip` assigns one path per fanfic locally. Fanfics beyond 50 are handled on the next `fetchFanfics` call.

Note: `RandomThumbnailBatchResponse` and `randomFanficThumbnails(count:)` are both defined in Task 3 (Networking module already imported in this file).

### Commit message
```
[ios] AST-12 migrate existing fanfics with nil thumbnailPath via batch endpoint
```

---

## Task 6 — iOS: StoryThumbnail fallback verification

### Files

- **Read-only audit**: `ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/StoryThumbnail.swift`
- **Read-only audit**: `ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/PlaceholderThumbnail.swift`

### Verification checklist

- `StoryThumbnail(path:title:baseURL:)` already falls back to `PlaceholderThumbnail` when `path` is nil or empty. No change needed.
- `CachedAsyncImage` 404 handling and `AppConfig.staticBaseURL` trailing-slash checks are covered by Tasks 0a and 0b respectively — do not duplicate them here.

### Commit message (only if StoryThumbnail needs fixing)
```
[ios] AST-12 fix StoryThumbnail fallback to PlaceholderThumbnail for nil/empty path
```

---

## Task 7 — Tests

### Backend tests

File: `backend/tests/test_fanfic_thumbnails.py`

```python
import pytest
from httpx import AsyncClient

@pytest.mark.asyncio
async def test_random_thumbnail_returns_valid_path(client: AsyncClient):
    resp = await client.get("/api/v1/fanfic-thumbnails/random")
    assert resp.status_code == 200
    data = resp.json()
    assert "path" in data
    import re
    assert re.fullmatch(r"fanfic-thumbnails/([1-9]|[1-4][0-9]|50)\.jpg", data["path"])

@pytest.mark.asyncio
async def test_random_thumbnail_varies(client: AsyncClient):
    paths = {(await client.get("/api/v1/fanfic-thumbnails/random")).json()["path"]
             for _ in range(20)}
    assert len(paths) >= 3  # probabilistic — 20 draws from 50 must have >= 3 unique
```

### iOS unit tests

Using the existing test target pattern — mock `APIClient` to return a canned `RandomThumbnailResponse`.

Key test cases:
1. `fetchFanfics` migration: fanfic with nil path gets `thumbnailPath` set to `"fanfic-thumbnails/3.jpg"`.
2. `syncActiveJobs`: job status `"complete"` + fanfic with nil path → thumbnail assigned.
3. Offline (URLError thrown): `thumbnailPath` stays nil, no crash, no error propagated to UI.
4. `thumbnailPath` already set: neither hook overwrites it.

### Commit message
```
[ios][backend] AST-12 add tests for thumbnail endpoint and iOS assignment logic
```

---

## Execution Order

```
Task 0a  →  Task 0b  →  Task 1  ┐
(CachedAsync   (AppConfig      (backend    ├──parallel──→  Task 3  →  Task 4  →  Task 5  →  Task 6  →  Task 7
 404 audit)     slash audit)    router)    │              (iOS DTO   (scrape    (migration  (Story     (tests)
                                Task 2  ──┘               + endpt)   hook)      hook-batch) Thumbnail
                               (seeding                                                      audit)
                                script +
                                Pillow dep)
```

- Tasks 0a and 0b are read-only audits — must run first to catch blockers before any code is written.
- Tasks 1 and 2 can run in parallel after audits pass.
- Task 3 (iOS DTO + endpoint) must complete before Tasks 4, 5, and 6.
- Tasks 4, 5, 6 can be parallelized after Task 3.
- Task 7 (tests) is last.
