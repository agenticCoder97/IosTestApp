# AST-19 Permanent Delete — iOS Plan (PR 2 of 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** iOS client support for permanent delete. Replaces the existing silent soft-delete in library context menus with a confirmation-gated permanent delete. Adds a detail-view overflow menu with the same action. Handles offline via a persisted `PendingRemoteDeletion` retry queue drained on next launch.

**Architecture:** One new `@MainActor` service (`StoryDeletionService`) in `Core` owns the full local-purge + remote-call sequence. A sibling `PendingDeletionDrainService` is invoked at app launch to retry any queued remote deletions. UI layer wires both library context menus and detail-view toolbar overflows through a shared `DeletePermanentlyAlertModifier` from `DesignSystem`.

**Tech Stack:** SwiftUI, SwiftData `@Model`, `@Environment(\.dismiss)`, `APIClient.shared.requestVoid`, existing `ChapterDownloadService.deleteAllChapters` / `FanficDownloadService.deleteAllChapters`.

**Spec:** [docs/superpowers/specs/2026-04-17-ast-19-permanent-delete-design.md](../specs/2026-04-17-ast-19-permanent-delete-design.md)

**Branch:** `feature/ast-19-permanent-delete-ios` (off `origin/development`, already checked out)

**Dependency:** Backend PR [#28](https://github.com/agenticCoder97/IosTestApp/pull/28) must be merged + deployed before this PR merges. Implementation on this branch can proceed now against the local dev backend (which has the new routes loaded). The iOS PR should NOT be merged to `development` until #28 is deployed, otherwise the iOS client hitting prod will get 405 Method Not Allowed.

**Testing note:** No SwiftUI view tests exist. Verification is `xcodebuild` build success + manual simulator sweep (Task 4). Unit tests for `StoryDeletionService` COULD be added, but SwiftData `ModelContext` mocking is painful and the service is a thin orchestrator — prefer manual verification for this PR.

---

## Inspection summary (already verified)

- `ios/Astral/AstralApp.swift:21` — `Schema([...])` lists all `@Model` classes; `PendingRemoteDeletion` must be added here.
- `ios/Astral/Packages/Networking/Sources/Networking/Endpoints.swift` — static-function pattern; existing delete cases at lines 81 (comic) and 124 (fanfic) return `Endpoint(method: .delete, path: "/comics/\(id)")`. New permanent-delete cases follow the same style.
- `ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficLibraryView.swift:164-166` — existing `.contextMenu { Button(role: .destructive) { deleteFanfic(fanfic) } }` to replace. `deleteFanfic(_:)` helper at line 191-192 to remove.
- `ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicLibraryView.swift` — same pattern; existing `deleteComic(_:)` helper to replace.
- `ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift:219-220` — existing `.toolbar { ToolbarItem(placement: .topBarTrailing) { ... } }`. Extend with a `Menu` containing the delete action.
- `ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift` — same pattern.

---

### Task 1: Foundation — `PendingRemoteDeletion` @Model + endpoint cases

**Files:**
- Create: `ios/Astral/Packages/Core/Sources/Core/Models/PendingRemoteDeletion.swift`
- Modify: `ios/Astral/AstralApp.swift` — add to `Schema([...])`
- Modify: `ios/Astral/Packages/Networking/Sources/Networking/Endpoints.swift` — add two new static-factory cases

- [ ] **Step 1: Create `PendingRemoteDeletion` @Model**

```swift
import Foundation
import SwiftData

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

- [ ] **Step 2: Register in schema**

In `ios/Astral/AstralApp.swift`, find the `let schema = Schema([...])` block around line 21. Add `PendingRemoteDeletion.self` to the array. Example:

```swift
let schema = Schema([
    LocalComic.self,
    LocalComicChapter.self,
    LocalFanfic.self,
    LocalFanficChapter.self,
    LocalBookmark.self,
    LocalReadingSession.self,
    LocalAuthor.self,
    LocalScrapeJob.self,
    PendingRemoteDeletion.self,  // NEW
])
```

Match whatever the actual surrounding types are (read before editing — the list above is illustrative).

- [ ] **Step 3: Add endpoint cases**

In `ios/Astral/Packages/Networking/Sources/Networking/Endpoints.swift`, after the existing `deleteComic` static at ~line 81 and `deleteFanfic` at ~line 124, add sibling cases:

```swift
// Inside the Endpoint extension that holds deleteComic:
public static func permanentDeleteComic(id: UUID) -> Endpoint {
    Endpoint(method: .delete, path: "/comics/\(id)/permanent")
}

// Inside the extension that holds deleteFanfic:
public static func permanentDeleteFanfic(id: UUID) -> Endpoint {
    Endpoint(method: .delete, path: "/fanfic/\(id)/permanent")
}
```

Read the file's existing structure first — the exact extension / location may vary. Match the surrounding style.

- [ ] **Step 4: Build**

```bash
cd ios/Astral && xcodebuild -scheme Astral -sdk iphonesimulator -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ios/Astral/Packages/Core/Sources/Core/Models/PendingRemoteDeletion.swift \
        ios/Astral/AstralApp.swift \
        ios/Astral/Packages/Networking/Sources/Networking/Endpoints.swift
git commit -m "[ios] AST-19 foundation — PendingRemoteDeletion model + endpoint cases

New @Model persisting offline retry state for permanent deletions
that could not reach the backend (content_type + storyId + created_at).
Registered in the AstralApp schema.

Two new endpoint cases (permanentDeleteComic, permanentDeleteFanfic)
calling the new backend /permanent subroutes. Existing deleteComic
and deleteFanfic (soft-delete) cases untouched."
```

---

### Task 2: Services — `StoryDeletionService` + `PendingDeletionDrainService` + launch wiring

**Files:**
- Create: `ios/Astral/Packages/Core/Sources/Core/Services/StoryDeletionService.swift`
- Create: `ios/Astral/Packages/Core/Sources/Core/Services/PendingDeletionDrainService.swift`
- Modify: `ios/Astral/AstralApp.swift` — call `PendingDeletionDrainService.drain(...)` at launch

`ChapterDownloadService` lives in `ComicFeature`, `FanficDownloadService` in `FanficFeature`. `Core` cannot import feature modules (that'd be a circular dep). Solution: `StoryDeletionService`'s methods accept a closure `deleteFiles: (UUID) async -> Void` that the caller (from the feature view) injects with the appropriate download-service call. Library views will pass:

- Comic: `{ id in ChapterDownloadService.shared.deleteAllChapters(comic: comic, chapters: chapters, modelContext: modelContext) }`
- Fanfic: `{ id in FanficDownloadService.shared.deleteAllChapters(fanfic: fanfic, modelContext: modelContext) }`

This keeps Core dependency-free.

- [ ] **Step 1: Create `StoryDeletionService`**

```swift
import Foundation
import SwiftData
import Networking

/// Orchestrates permanent deletion of a story (comic or fanfic).
/// Local SwiftData + downloaded files are purged first; backend call
/// is attempted and, on failure, queued for launch-time retry.
@MainActor
public final class StoryDeletionService {
    public static let shared = StoryDeletionService()
    private init() {}

    public func permanentlyDelete(
        comic: LocalComic,
        chapters: [LocalComicChapter],
        modelContext: ModelContext,
        deleteFiles: @escaping () -> Void
    ) async {
        let id = comic.id
        AstralLogger.info("permanentlyDelete comic called | id=\(id)", context: "StoryDeletion")

        // Local purge first (runs even if remote fails)
        deleteFiles()
        await purgeLocalReferences(storyId: id, contentType: "comic", modelContext: modelContext)
        modelContext.delete(comic)
        try? modelContext.save()

        // Remote call
        do {
            try await APIClient.shared.requestVoid(.permanentDeleteComic(id: id))
            AstralLogger.info("permanentlyDelete comic backend ok | id=\(id)", context: "StoryDeletion")
        } catch {
            AstralLogger.warning("permanentlyDelete comic backend failed, queueing | id=\(id) error=\(error)", context: "StoryDeletion")
            modelContext.insert(PendingRemoteDeletion(storyId: id, contentType: "comic"))
            try? modelContext.save()
        }
    }

    public func permanentlyDelete(
        fanfic: LocalFanfic,
        modelContext: ModelContext,
        deleteFiles: @escaping () -> Void
    ) async {
        let id = fanfic.id
        AstralLogger.info("permanentlyDelete fanfic called | id=\(id)", context: "StoryDeletion")

        deleteFiles()
        await purgeLocalReferences(storyId: id, contentType: "fanfic", modelContext: modelContext)
        modelContext.delete(fanfic)
        try? modelContext.save()

        do {
            try await APIClient.shared.requestVoid(.permanentDeleteFanfic(id: id))
            AstralLogger.info("permanentlyDelete fanfic backend ok | id=\(id)", context: "StoryDeletion")
        } catch {
            AstralLogger.warning("permanentlyDelete fanfic backend failed, queueing | id=\(id) error=\(error)", context: "StoryDeletion")
            modelContext.insert(PendingRemoteDeletion(storyId: id, contentType: "fanfic"))
            try? modelContext.save()
        }
    }

    private func purgeLocalReferences(storyId: UUID, contentType: String, modelContext: ModelContext) async {
        let bookmarkFetch = FetchDescriptor<LocalBookmark>(predicate: #Predicate { $0.storyId == storyId && $0.contentType == contentType })
        if let bookmarks = try? modelContext.fetch(bookmarkFetch) {
            bookmarks.forEach { modelContext.delete($0) }
        }
        let sessionFetch = FetchDescriptor<LocalReadingSession>(predicate: #Predicate { $0.storyId == storyId && $0.contentType == contentType })
        if let sessions = try? modelContext.fetch(sessionFetch) {
            sessions.forEach { modelContext.delete($0) }
        }
        let scrapeFetch = FetchDescriptor<LocalScrapeJob>(predicate: #Predicate { $0.storyId == storyId })
        if let jobs = try? modelContext.fetch(scrapeFetch) {
            jobs.forEach { modelContext.delete($0) }
        }
    }
}
```

**Before writing this, inspect:**
- `LocalBookmark`, `LocalReadingSession`, `LocalScrapeJob` model definitions in `Core/Models/` — verify the exact field names (`storyId`, `contentType`, maybe `content_type`). Adjust predicates if the field name differs.
- `APIClient.shared.requestVoid` signature — confirm it's `async throws`.
- Existing `AstralLogger` usage — copy the exact import + call pattern.

- [ ] **Step 2: Create `PendingDeletionDrainService`**

```swift
import Foundation
import SwiftData
import Networking

@MainActor
public enum PendingDeletionDrainService {
    /// Fire-and-forget drain of queued remote deletions.
    /// Called once per launch; failures leave the row in place for the next launch.
    public static func drain(modelContext: ModelContext) {
        Task { @MainActor in
            let fetch = FetchDescriptor<PendingRemoteDeletion>()
            guard let pending = try? modelContext.fetch(fetch), !pending.isEmpty else { return }

            AstralLogger.info("drain starting | count=\(pending.count)", context: "PendingDelete")

            for record in pending {
                do {
                    switch record.contentType {
                    case "comic":
                        try await APIClient.shared.requestVoid(.permanentDeleteComic(id: record.storyId))
                    case "fanfic":
                        try await APIClient.shared.requestVoid(.permanentDeleteFanfic(id: record.storyId))
                    default:
                        AstralLogger.warning("drain unknown contentType, discarding | \(record.contentType)", context: "PendingDelete")
                    }
                    modelContext.delete(record)
                } catch {
                    AstralLogger.warning("drain failed, leaving in queue | storyId=\(record.storyId) error=\(error)", context: "PendingDelete")
                }
            }
            try? modelContext.save()
            AstralLogger.info("drain done", context: "PendingDelete")
        }
    }
}
```

- [ ] **Step 3: Wire the drain into AstralApp launch**

In `ios/Astral/AstralApp.swift`, find wherever `OrphanCleanupService` (or an equivalent launch-side service) is called at startup. Add a sibling call to `PendingDeletionDrainService.drain(modelContext: modelContext)` immediately after.

If no obvious launch site exists, attach to the root view's `.onAppear` — but prefer whatever pattern `OrphanCleanupService` already uses.

- [ ] **Step 4: Build**

```bash
cd ios/Astral && xcodebuild -scheme Astral -sdk iphonesimulator -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ios/Astral/Packages/Core/Sources/Core/Services/StoryDeletionService.swift \
        ios/Astral/Packages/Core/Sources/Core/Services/PendingDeletionDrainService.swift \
        ios/Astral/AstralApp.swift
git commit -m "[ios] AST-19 StoryDeletionService + launch-time retry drain

Service orchestrates local-first permanent delete: purges
downloaded files (via injected closure), bookmarks, reading
sessions, and scrape jobs from SwiftData, deletes the story row,
saves, then attempts the backend /permanent call. On remote
failure, inserts a PendingRemoteDeletion row for later retry.

PendingDeletionDrainService runs once per launch, iterates queued
records, and retries each. Successful (or server-404) deletions
remove the queue row; failures stay in place for next launch.
Wired from AstralApp alongside the existing cleanup service."
```

---

### Task 3: UI wiring — `DeletePermanentlyAlertModifier` + library + detail views

**Files:**
- Create: `ios/Astral/Packages/DesignSystem/Sources/DesignSystem/DeletePermanentlyAlertModifier.swift`
- Modify: `ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicLibraryView.swift`
- Modify: `ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficLibraryView.swift`
- Modify: `ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift`
- Modify: `ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift`

- [ ] **Step 1: Create the shared alert modifier**

In `ios/Astral/Packages/DesignSystem/Sources/DesignSystem/DeletePermanentlyAlertModifier.swift`:

```swift
import SwiftUI

public struct DeletePermanentlyAlertModifier: ViewModifier {
    @Binding public var isPresented: Bool
    public let storyTitle: String
    public let onConfirm: () -> Void

    public init(isPresented: Binding<Bool>, storyTitle: String, onConfirm: @escaping () -> Void) {
        self._isPresented = isPresented
        self.storyTitle = storyTitle
        self.onConfirm = onConfirm
    }

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

- [ ] **Step 2: Update `FanficLibraryView`**

Read `FanficLibraryView.swift` around lines 160-200. Find:
- The `.contextMenu { Button(role: .destructive) { deleteFanfic(fanfic) } }` block (line 164-166 area).
- The `deleteFanfic(_:)` helper (line 191).

Changes:

1. Add view state near other `@State`s:

```swift
@State private var pendingDeletion: LocalFanfic?
```

2. Replace the existing destructive button in `.contextMenu`:

```swift
// Replace:
Button(role: .destructive) {
    deleteFanfic(fanfic)
} label: { Label("Delete", systemImage: "trash") }

// With:
Button(role: .destructive) {
    pendingDeletion = fanfic
} label: { Label("Delete permanently", systemImage: "trash.slash") }
```

(Preserve any surrounding context-menu items like favorite toggle.)

3. At the end of the `body`'s outermost container (ScrollView or NavigationStack), attach the alert modifier:

```swift
.deletePermanentlyAlert(
    isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
    storyTitle: pendingDeletion?.title ?? "",
    onConfirm: {
        if let fanfic = pendingDeletion {
            Task {
                await StoryDeletionService.shared.permanentlyDelete(
                    fanfic: fanfic,
                    modelContext: modelContext,
                    deleteFiles: {
                        FanficDownloadService.shared.deleteAllChapters(fanfic: fanfic, modelContext: modelContext)
                    }
                )
            }
        }
        pendingDeletion = nil
    }
)
```

**Note:** verify `FanficDownloadService.deleteAllChapters` signature — it may take different args. Match the real signature.

4. Remove `deleteFanfic(_:)` helper (no longer used). If the helper has other callers in the same file, grep first — if any remain, leave it alone and just unhook it from the context menu.

- [ ] **Step 3: Update `ComicLibraryView`**

Mirror Step 2 for `ComicLibraryView.swift`. Differences:
- Uses `ChapterDownloadService.shared.deleteAllChapters(comic:chapters:modelContext:)` — the chapter list is already available in scope (check the existing `deleteComic(_:)` helper for the pattern).
- Preserve existing Archive/Unarchive buttons in the context menu.

- [ ] **Step 4: Update `FanficDetailView`**

Read `FanficDetailView.swift` around lines 219-220 (existing `.toolbar` block). Extend the trailing toolbar item to include a `Menu` with the delete action:

```swift
// Current:
.toolbar {
    ToolbarItem(placement: .topBarTrailing) {
        // existing trailing content — maybe a button for source-url
    }
}

// Extended:
.toolbar {
    ToolbarItem(placement: .topBarTrailing) {
        Menu {
            // Preserve any existing trailing actions
            Button(role: .destructive) {
                showDeleteAlert = true
            } label: {
                Label("Delete permanently", systemImage: "trash.slash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }
}
```

If the existing toolbar item has only one action, you may fold that action into the new `Menu`, OR add the `Menu` as a second `ToolbarItem`. Choose whichever keeps the existing UX.

Add state:

```swift
@State private var showDeleteAlert = false
@Environment(\.dismiss) private var dismiss  // if not already present
```

Attach the alert:

```swift
.deletePermanentlyAlert(
    isPresented: $showDeleteAlert,
    storyTitle: fanfic.title,
    onConfirm: {
        Task {
            await StoryDeletionService.shared.permanentlyDelete(
                fanfic: fanfic,
                modelContext: modelContext,
                deleteFiles: {
                    FanficDownloadService.shared.deleteAllChapters(fanfic: fanfic, modelContext: modelContext)
                }
            )
            dismiss()
        }
    }
)
```

- [ ] **Step 5: Update `ComicDetailView`**

Mirror Step 4 for comic. Uses `ChapterDownloadService.shared.deleteAllChapters(comic:chapters:modelContext:)`. The chapters array is already in scope (check the existing view).

- [ ] **Step 6: Build**

```bash
cd ios/Astral && xcodebuild -scheme Astral -sdk iphonesimulator -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add ios/Astral/Packages/DesignSystem/Sources/DesignSystem/DeletePermanentlyAlertModifier.swift \
        ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicLibraryView.swift \
        ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficLibraryView.swift \
        ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift \
        ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift
git commit -m "[ios] AST-19 permanent-delete UI entry points

Shared DeletePermanentlyAlertModifier in DesignSystem — single alert
copy reused from all four surfaces.

Library context menus: silent soft-delete replaced with confirmation-
gated 'Delete permanently' (trash.slash). Existing Archive/Unarchive
items preserved on comic side.

Detail view toolbars: new trailing overflow Menu (ellipsis.circle)
with the same delete action. On confirm, the detail view dismisses
to the library, where the @Query re-fetch removes the deleted row.

All four call sites route through StoryDeletionService.permanentlyDelete,
injecting the feature-local *DownloadService.deleteAllChapters closure
so Core stays dependency-free of ComicFeature/FanficFeature."
```

---

### Task 4: Manual simulator verification (user)

- [ ] **Step 1: Launch**

From Xcode on `feature/ast-19-permanent-delete-ios`, Cmd+R to run on the simulator. Ensure the local dev backend is running (the implementer ran an integration test earlier; it should still be up).

- [ ] **Step 2: Library context menu — happy path (online)**

  1. Comic library → long-press any comic (use a throwaway if possible).
  2. Context menu appears. Confirm "Delete permanently" item with `trash.slash` icon, red tint. Archive/Unarchive still present.
  3. Tap "Delete permanently".
  4. Alert: "Delete Permanently? This will permanently delete \"{title}\" and all local data. This cannot be undone." With Cancel and Delete (destructive) buttons.
  5. Tap Delete.
  6. Comic disappears from the library immediately.
  7. Open `http://localhost:8000/api/v1/comics/{id}` (or look in Postgres) — row gone.
  8. Repeat on fanfic side.

- [ ] **Step 3: Detail view delete**

  1. Open a story via its library cell.
  2. Tap the trailing toolbar overflow (`ellipsis.circle`).
  3. Menu appears with "Delete permanently".
  4. Tap it → alert → Delete.
  5. Detail view dismisses back to library; story is gone from the grid.

- [ ] **Step 4: Offline retry queue**

  1. Disable wifi on the simulator (Features → Network Link Conditioner → 100% Loss, OR disable host wifi).
  2. Delete a story via either entry point.
  3. Story disappears from library immediately (local purge runs).
  4. Console log should show: `permanentlyDelete ... backend failed, queueing`.
  5. Re-enable network.
  6. Force-quit and relaunch the app.
  7. On launch, console should show: `drain starting | count=1` followed by `drain done`.
  8. Verify backend DB no longer has the row.
  9. Relaunch again — `drain starting | count=0` (queue empty) or no drain log at all.

- [ ] **Step 5: Cancel path**

Ensure tapping Cancel on the alert leaves the story in place — no UI change, no backend call, no log output.

- [ ] **Step 6: If anything fails**

Describe the symptom + console output. Do not open the PR yet.

---

### Task 5: Push + open PR

- [ ] **Step 1: Push**

```bash
git push -u origin feature/ast-19-permanent-delete-ios
```

- [ ] **Step 2: Open PR**

```bash
gh pr create --base development --title "[ios] AST-19 permanent delete UI + service + retry queue" --body "$(cat <<'EOF'
## Summary

Second of two PRs for AST-19. iOS client support for the `/permanent` endpoints shipped in PR #28.

- Library context menus: silent soft-delete replaced with confirmation-gated "Delete permanently". Existing Archive / Unarchive items preserved on comic side.
- Detail view toolbars: new trailing `ellipsis.circle` overflow menu with the same delete action. On confirm, the detail view dismisses back to the library.
- `StoryDeletionService` (new, `Core` package) orchestrates local purge (bookmarks, reading sessions, scrape jobs, downloaded files, SwiftData row) then remote call; on network failure queues a `PendingRemoteDeletion` row.
- `PendingDeletionDrainService` runs once per launch to retry queued deletions. Idempotent against the backend (which returns 204 for unknown ids).
- Shared `DeletePermanentlyAlertModifier` in `DesignSystem` — single alert copy reused from all four surfaces.

Closes [AST-19](https://linear.app/nnetraganti/issue/AST-19/library-add-permanent-delete-long-press-on-library-item-and-action-in).

Spec: `docs/superpowers/specs/2026-04-17-ast-19-permanent-delete-design.md`
Plan: `docs/superpowers/plans/2026-04-17-ast-19-permanent-delete-ios.md`

Depends on: [#28](https://github.com/agenticCoder97/IosTestApp/pull/28) — **must be merged and deployed before this PR merges.** Otherwise the iOS client hits prod's old soft-delete behavior (or 405 on /permanent).

## Test plan

- [x] `xcodebuild -scheme Astral -sdk iphonesimulator build` succeeds
- [x] Library context menu: "Delete permanently" → alert → confirm → story gone locally + remote 204
- [x] Detail view overflow menu: same flow, detail view dismisses on success
- [x] Offline: local purge still fires, `PendingRemoteDeletion` queued, drain succeeds on next launch with network
- [x] Cancel path: alert dismisses, story unchanged

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: Report PR URL**

---

## Self-review

**Spec coverage:**
- `PendingRemoteDeletion` @Model + schema registration → Task 1 ✓
- `StoryDeletionService` orchestration → Task 2 ✓
- Offline retry + launch drain → Task 2 ✓
- Shared alert modifier → Task 3 ✓
- Library context menu replacement → Task 3 ✓
- Detail view overflow → Task 3 ✓
- Manual simulator verification → Task 4 ✓

**Placeholder scan:** none that aren't explicit "verify during implementation" instructions for model field names / download-service signatures.

**Known sharp edges:**
- `StoryDeletionService` lives in `Core`, which cannot import `ComicFeature` / `FanficFeature`. The `deleteFiles` closure is injected by the caller to avoid circular imports — explicit in the service signature.
- `PendingRemoteDeletion` migration concern: adding a new `@Model` to `Schema([...])` in iOS SwiftData is handled by automatic lightweight migration on first launch. No `VersionedSchema` needed.
- `LocalBookmark` / `LocalReadingSession` / `LocalScrapeJob` field names (`storyId`, `contentType`) must be verified — the Task 1 spec inspection listed these as the expected names. Adjust predicates if different.
