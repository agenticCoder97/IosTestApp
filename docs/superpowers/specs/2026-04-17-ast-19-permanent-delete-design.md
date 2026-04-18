# AST-19 — Permanent delete: library + detail view entry points

Linear: [AST-19](https://linear.app/nnetraganti/issue/AST-19/library-add-permanent-delete-long-press-on-library-item-and-action-in)

## Problem

Users have no way to permanently delete a story. The library's existing context-menu "Delete" action silently soft-deletes via `DELETE /comics/{id}` / `DELETE /fanfic/{id}` (both map to `soft_delete_*` which sets `deleted_at` and waits for the nightly `cleanup_task` to hard-purge after `SOFT_DELETE_DAYS=5`). Two gaps:

1. Local SwiftData state is not deleted on the iOS side — only the backend row is soft-marked.
2. The user has no UI that says "delete this now, permanently, with confirmation."
3. Bookmarks, reading sessions, scrape jobs, and downloaded files on disk are never cleaned up by the existing soft-delete path.

## Goal

Two entry points — library context menu (replace existing silent "Delete") and detail-view toolbar overflow — both gated by an `.alert` confirmation. On confirm, the story is purged immediately from local SwiftData, local filesystem, and the backend database + media store. Offline behavior: local purge happens immediately; remote call is retried via a persisted pending-deletion queue when connectivity returns.

## Scope

This spec covers both backend and iOS. **Shipped as two PRs:**

1. **PR 1 (backend-first)** — new `/permanent` routes, `permanent_delete_*` services, ARQ media-wipe job. Merged and deployed before PR 2.
2. **PR 2 (iOS)** — `StoryDeletionService`, `PendingRemoteDeletion` @Model, shared confirmation alert, library + detail view wiring, launch-time drain.

## Design

### Backend (PR 1)

#### New routes

- `DELETE /api/v1/comics/{comic_id}/permanent` → `comic_service.permanent_delete_comic`
- `DELETE /api/v1/fanfic/{fanfic_id}/permanent` → `fanfic_service.permanent_delete_fanfic`

Each returns `204 No Content` on success. **Idempotent:** if the story is already gone, return 204 (not 404). The client's retry queue depends on this.

#### Service behavior

`permanent_delete_comic(db, comic_id)`:

1. Hard-delete (`DELETE FROM ...`) rows in this order to respect FKs:
   - `Page WHERE chapter_id IN (SELECT id FROM comic_chapters WHERE comic_id = :id)`
   - `ComicChapter WHERE comic_id = :id`
   - `ScrapeJob WHERE story_id = :id AND content_type = 'comic'`
   - `ReadingProgress WHERE comic_id = :id` (if applicable — verify column name)
   - `Comic WHERE id = :id`
2. `await db.commit()`.
3. Invalidate Redis cache: `await redis_cache.invalidate_comics(str(comic_id))`.
4. Enqueue ARQ job `comic_media_wipe_task` with `{comic_id: str}` to delete `/mnt/astral-media/comics/{comic_id}/` (the chapter page directories + the thumbnail).
5. Return `True`. If the Comic row didn't exist at step 1, return `True` anyway (idempotent — caller returns 204).

`permanent_delete_fanfic(db, fanfic_id)` mirrors the above with: `FanficChapter` → `ScrapeJob (content_type='fanfic')` → `ReadingProgress` → `Fanfic`. Thumbnail wipe targets `/mnt/astral-media/fanfics/{fanfic_id}/` if anything is stored there (scan `fanfic_service` to confirm — fanfic currently has no downloaded page store, only thumbnails).

**Author rows (`Author`) are NEVER touched** — they're shared across stories.

#### New ARQ job — `comic_media_wipe_task`

- Arg: `comic_id: str`.
- Body: `shutil.rmtree("/mnt/astral-media/comics/{comic_id}", ignore_errors=True)`; best-effort single-file delete of the thumbnail at its stored path.
- Log success/failure; never raise (this is best-effort, idempotent).
- Registered in `app/worker/worker.py` (or wherever the existing ARQ task list lives).

A separate `fanfic_media_wipe_task` for fanfic if/when there are any media artifacts; if only thumbnails, keep it minimal.

#### Keep the existing soft-delete path

`DELETE /comics/{id}` and `DELETE /fanfic/{id}` continue to call `soft_delete_*` unchanged. This preserves compatibility with any out-of-band caller (admin tool, old iOS clients). The `cleanup_task` nightly cron stays as-is.

### iOS (PR 2)

#### New service — `StoryDeletionService`

Location: `ios/Astral/Packages/Core/Sources/Core/Services/StoryDeletionService.swift`.

`@MainActor final class StoryDeletionService` with `static let shared`.

```swift
func permanentlyDelete(comic: LocalComic, chapters: [LocalComicChapter], modelContext: ModelContext) async
func permanentlyDelete(fanfic: LocalFanfic, modelContext: ModelContext) async
```

**Each method (common skeleton):**

1. Capture `id = comic.id` (or `fanfic.id`) up front — the SwiftData object becomes invalid after deletion.
2. Local purge (always runs, even if remote fails):
   a. `ChapterDownloadService.shared.deleteAllChapters(comic:chapters:modelContext:)` (for comics) or `FanficDownloadService.shared.deleteAllChapters(fanfic:modelContext:)` (for fanfics).
   b. Fetch + delete `LocalBookmark` rows matching `storyId == id && contentType == "comic"|"fanfic"` via `ModelContext.fetch(FetchDescriptor(predicate:))`.
   c. Fetch + delete `LocalReadingSession` rows same predicate.
   d. Fetch + delete `LocalScrapeJob` rows matching `storyId == id`.
   e. `modelContext.delete(comic)` — SwiftData cascades the chapter rows via the existing `comic: LocalComic?` relationship.
   f. `try? modelContext.save()`.
3. Remote call:
   a. `try await APIClient.shared.requestVoid(.permanentDeleteComic(id: id))`.
   b. On success: done.
   c. On throw: insert `PendingRemoteDeletion(id: id, contentType: "comic", createdAt: .now)` into `modelContext`, `try? modelContext.save()`. Log `AstralLogger.warning`.

#### New @Model — `PendingRemoteDeletion`

Location: `ios/Astral/Packages/Core/Sources/Core/Models/PendingRemoteDeletion.swift`.

```swift
@Model
public final class PendingRemoteDeletion {
    @Attribute(.unique) public var id: UUID
    public var storyId: UUID
    public var contentType: String  // "comic" | "fanfic"
    public var createdAt: Date

    public init(storyId: UUID, contentType: String) {
        self.id = UUID()
        self.storyId = storyId
        self.contentType = contentType
        self.createdAt = .now
    }
}
```

Register in `AstralApp.swift`'s `Schema([...])`.

#### Launch-time drain

In `AstralApp.swift`, after the existing `OrphanCleanupService` pass, add a call to `PendingDeletionDrainService.drain(modelContext:)` (new small helper). This service:

1. Fetches all `PendingRemoteDeletion` rows.
2. For each, calls the appropriate `APIClient.requestVoid(.permanentDelete*(id:))`.
3. On success or 404 (idempotent), deletes the `PendingRemoteDeletion` row.
4. On network failure, leaves the row alone for the next launch.
5. `try? modelContext.save()`.

Runs once per launch; fire-and-forget from a `Task { @MainActor in ... }`.

#### New endpoints in `Networking`

In `ios/Astral/Packages/Networking/Sources/Networking/Endpoints.swift`, add:

```swift
case permanentDeleteComic(id: UUID)
case permanentDeleteFanfic(id: UUID)
```

Both `method: .delete`, path `/api/v1/comics/{id}/permanent` / `/api/v1/fanfic/{id}/permanent`.

#### UI — shared confirmation alert

Location: `ios/Astral/Packages/DesignSystem/Sources/DesignSystem/DeletePermanentlyAlert.swift`.

A `ViewModifier` or computed `View` that takes a binding + title + action closure:

```swift
public struct DeletePermanentlyAlertModifier: ViewModifier {
    @Binding public var isPresented: Bool
    public let storyTitle: String
    public let onConfirm: () -> Void

    public func body(content: Content) -> some View {
        content.alert("Delete Permanently?", isPresented: $isPresented) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { onConfirm() }
        } message: {
            Text("This will permanently delete \"\(storyTitle)\" and all local data. This cannot be undone.")
        }
    }
}

public extension View {
    func deletePermanentlyAlert(
        isPresented: Binding<Bool>,
        storyTitle: String,
        onConfirm: @escaping () -> Void
    ) -> some View {
        modifier(DeletePermanentlyAlertModifier(isPresented: isPresented, storyTitle: storyTitle, onConfirm: onConfirm))
    }
}
```

#### Library context menus

- `FanficLibraryView.swift`: inside the existing `.contextMenu { ... }`, **replace** the current destructive "Delete" button (which calls `deleteFanfic(...)`) with a new button:

  ```swift
  Button(role: .destructive) {
      pendingDeletion = fanfic
  } label: {
      Label("Delete permanently", systemImage: "trash.slash")
  }
  ```

  Add view state: `@State private var pendingDeletion: LocalFanfic?`.

  Add the alert modifier on the ScrollView:

  ```swift
  .deletePermanentlyAlert(
      isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
      storyTitle: pendingDeletion?.title ?? "",
      onConfirm: {
          if let fanfic = pendingDeletion {
              Task { await StoryDeletionService.shared.permanentlyDelete(fanfic: fanfic, modelContext: modelContext) }
          }
          pendingDeletion = nil
      }
  )
  ```

  Remove the old `deleteFanfic(_:)` helper (no longer used). If the helper has callers besides the context menu, repoint or leave untouched (audit during implementation).

- `ComicLibraryView.swift`: same pattern. Keep the existing "Archive" / "Unarchive" items; only replace "Delete" with "Delete permanently."

#### Detail view toolbar

- `FanficDetailView.swift`: add a trailing toolbar button with `Menu { ... } label: { Image(systemName: "ellipsis.circle") }` containing a single destructive "Delete permanently" item that sets a local `@State showDeleteAlert: Bool`. On confirm, call `StoryDeletionService.shared.permanentlyDelete(fanfic:modelContext:)`, then dismiss the detail view.

- `ComicDetailView.swift`: same pattern.

**Navigation after successful deletion:** in the detail view's confirm handler, dismiss the view (`@Environment(\.dismiss) var dismiss`) so the user returns to the library, where the just-deleted story is already gone from `@Query`.

#### Haptics

None custom. SwiftUI's `.contextMenu` provides the long-press haptic; `.alert` provides the confirmation feedback.

## Acceptance

### Backend

- `curl -X DELETE http://localhost:8000/api/v1/comics/{id}/permanent` returns 204 for any valid or unknown UUID.
- After the call, Postgres has no `Comic`/`ComicChapter`/`Page`/`ScrapeJob`/`ReadingProgress` rows for that id.
- After the ARQ job fires, `/mnt/astral-media/comics/{id}/` no longer exists.
- Same behavior mirrored for fanfic.
- Redis cache entry for the id is invalidated.

### iOS

- Long-press on library row → context menu includes red "Delete permanently" with `trash.slash` icon.
- Detail view toolbar overflow (`ellipsis.circle`) includes "Delete permanently."
- Either entry point shows the alert: "Delete Permanently? This will permanently delete \"{title}\" and all local data. This cannot be undone."
- On confirm:
  - Story disappears from library (`@Query` re-fetch).
  - Detail view (if open) dismisses to library.
  - Downloaded files for that story are removed from Documents.
  - No bookmark or reading-session rows for that storyId remain.
  - No scrape-job rows for that storyId remain.
  - Backend returns 204 (or the request is queued as `PendingRemoteDeletion` if offline).
- On next app launch with connectivity, any queued `PendingRemoteDeletion` is drained and removed.

## Out of scope

- Soft-delete UI entry point (soft-delete remains on the backend for out-of-band callers; the iOS UI no longer exposes it).
- Undo toast / trash bin.
- Bulk delete.
- The pre-existing `NavigationLink` inside `LazyVStack`/`LazyVGrid` CLAUDE.md violation in both library views.
- Auth middleware (the app is single-user; no bearer token).

## Risks

- **Foreign-key ordering on backend purge** — if the DELETE order is wrong, Postgres will raise. The spec's ordering (pages → chapters → scrape jobs → reading progress → parent row) should be verified against actual FK constraints in the models; if `ON DELETE CASCADE` is already configured, some deletes may be unnecessary.
- **ARQ enqueue failure after the DB commit** — the row is gone from the DB but the media wipe never fires. Matches the existing pattern in `archive_comic` / `unarchive_comic` (logged as warning, not fatal). `cleanup_task` could be extended to orphan-scan media directories weekly, but that's out of scope.
- **Retry queue unbounded growth** — if the user frequently deletes offline, `PendingRemoteDeletion` accumulates. Mitigated by idempotent backend (duplicates are 204s) and launch-time drain. Cap at some sane max if testing reveals unbounded growth.
- **Author rows going stale** — `LocalAuthor` rows that were only referenced by the deleted story become orphans. Existing `OrphanCleanupService` already handles this pattern; verify it covers the author-only-reference case.
- **Spec references models that may not exist** — `LocalScrapeJob`, `LocalReadingSession`, `LocalBookmark` presence + `storyId` field name must be verified during implementation. Adjust query predicates accordingly.
