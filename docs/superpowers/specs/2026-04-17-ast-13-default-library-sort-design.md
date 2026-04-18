# AST-13 — Default library sort by last read

Linear: [AST-13](https://linear.app/nnetraganti/issue/AST-13/library-default-sort-both-comic-and-fanfic-libraries-by-last-read)
Branch: `feature/ast-13-default-library-sort` (off `origin/development`)

## Problem

Both library grids sort by `addedAt` as the default entry-point sort. A user who reads a story nightly but added it months ago sees it buried under newly-added but unread items. The reading-activity field (`lastReadAt`) is already written in both readers and detail views, but it's only consulted by the Continue Reading strips — never the main grids.

## Goal

Default library sort is "most recent activity," falling back to `addedAt` for items that have never been opened.

## Design

### Approach

In-memory coalesce over the existing `@Query` output. **No schema changes, no backfill, no migration.**

### Fanfic library

1. **Add a new sort option.** In `FanficFilterView.swift`:

   ```swift
   enum FanficSortOption: String, CaseIterable {
       case lastActivity = "Last Activity"   // new
       case dateAdded    = "Date Added"
       case dateUpdated  = "Date Updated"
       case wordCount    = "Word Count"
       case title        = "Title"
       case chapters     = "Chapters"
   }
   ```

   Place `.lastActivity` first so it renders as the leading chip in `FanficFilterView`'s sort row (the view renders via `FanficSortOption.allCases`).

2. **Change the default.** In `FanficFilterState` (`FanficFilterView.swift:22`):

   ```swift
   var sortBy: FanficSortOption = .lastActivity   // was .dateAdded
   ```

   Also update `FanficFilterState.reset()` (line 39) to reset to `.lastActivity`.

3. **Wire the new case into the sort switch.** In `FanficLibraryView.filteredFanfics` (`FanficLibraryView.swift:85-102`), add a new branch as the first `case`:

   ```swift
   case .lastActivity:
       return result.sorted { ascending
           ? ($0.lastReadAt ?? $0.addedAt) < ($1.lastReadAt ?? $1.addedAt)
           : ($0.lastReadAt ?? $0.addedAt) > ($1.lastReadAt ?? $1.addedAt)
       }
   ```

4. **No change to `@Query`.** `allFanfics` keeps `sort: \LocalFanfic.addedAt, order: .reverse` — the filter post-sorts in memory.

### Comic library

1. **Update `displayedComics` comparator.** In `ComicLibraryView.swift:41-44`, change:

   ```swift
   return ready.sorted { lhs, rhs in
       if lhs.isArchived != rhs.isArchived { return !lhs.isArchived }
       return lhs.addedAt > rhs.addedAt   // old
   }
   ```

   to:

   ```swift
   return ready.sorted { lhs, rhs in
       if lhs.isArchived != rhs.isArchived { return !lhs.isArchived }
       return (lhs.lastReadAt ?? lhs.addedAt) > (rhs.lastReadAt ?? rhs.addedAt)
   }
   ```

   Archived-to-bottom rule stays as the primary key (unchanged).

2. **No change to `@Query`.** `allComics` keeps `sort: \LocalComic.addedAt, order: .reverse`.

3. **No new `ComicFilterView`.** AST-15 covers filter-UI parity between comic and fanfic — deferred out of scope.

## Out of scope

- Schema migration / `VersionedSchema` / `SchemaMigrationPlan`.
- Backfill task for `lastReadAt`.
- `ComicFilterView` creation (AST-15).
- Any change to `@Query` sort clauses.
- Any change to `inProgressComics` / `inProgressFanfics` (Continue Reading strips already use `lastReadAt ?? addedAt`).
- Changing what "activity" means — we do NOT include `updatedAtSource`, `completedAt`, or bookmark times. Activity means strictly `lastReadAt`.

## Files touched

- `ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficFilterView.swift` — add `.lastActivity` to enum, change default in `FanficFilterState.sortBy` and `reset()`.
- `ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficLibraryView.swift` — add `.lastActivity` branch in `filteredFanfics` switch.
- `ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicLibraryView.swift` — change one line in `displayedComics` sort comparator.

## Acceptance

- Open the comic library fresh: a comic with recent `lastReadAt` appears above a newly-added unread comic (both sorted above archived comics).
- Open the fanfic library fresh: the sort chip selector shows "Last Activity" selected by default; the grid is sorted by `lastReadAt ?? addedAt` descending.
- In the fanfic filter, switching the sort to "Date Added" still produces the old ordering. All five pre-existing sort options still work.
- Reset-filter action restores "Last Activity" as the sort, not "Date Added".
- Never-read items fall back to `addedAt` order in both libraries.
- Archived comics remain at the bottom regardless of `lastReadAt`.

## Verification

- `xcodebuild -scheme Astral -sdk iphonesimulator build` succeeds.
- Manual simulator verification:
  - Comic library: read an old comic in the reader (or open its detail) — it moves to the top of the grid on the next library view.
  - Fanfic library: same check; plus toggle the filter's sort chips to confirm all 6 options sort correctly, and confirm the ascending toggle respects `.lastActivity`.

## Risks

- Sort churn when `lastReadAt` updates mid-session — `@Query` refetches on `LocalFanfic`/`LocalComic` changes and the in-memory sort re-runs. This already happens for the existing in-memory branches; adding another is not a new risk.
- Reset-filter button changes default behavior for any user who was relying on "reset → date added." Low risk; documented in commit.
