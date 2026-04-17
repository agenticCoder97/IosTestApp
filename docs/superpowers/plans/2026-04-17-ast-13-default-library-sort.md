# AST-13 Default Library Sort Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Change the default library sort (both comic and fanfic) to `lastReadAt ?? addedAt` descending, in memory. Add a new `FanficSortOption.lastActivity` case and make it the default.

**Architecture:** In-memory post-sort over existing `@Query` output. No schema changes, no backfill, no migration. Fanfic filter gets a new sort chip; the default is swapped to it. Comic library's existing in-memory re-sort comparator is updated to use `lastReadAt ?? addedAt`.

**Tech Stack:** SwiftUI, SwiftData `@Query`, `@Observable` filter state, existing in-memory sort patterns.

**Spec:** [docs/superpowers/specs/2026-04-17-ast-13-default-library-sort-design.md](../specs/2026-04-17-ast-13-default-library-sort-design.md)

**Branch:** `feature/ast-13-default-library-sort` (off `origin/development`, already checked out)

**Testing note:** No unit tests exist for these library views. Verification is `xcodebuild` + manual simulator. Each task runs the build; Task 3 is the user's simulator pass.

---

### Task 1: Apply all three source changes in one commit

**Files:**
- Modify: `ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficFilterView.swift`
- Modify: `ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficLibraryView.swift`
- Modify: `ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicLibraryView.swift`

The three changes MUST land together — adding the `.lastActivity` enum case without updating the switch triggers a compile error ("switch must be exhaustive"), so don't run a build in between.

- [ ] **Step 1: Add `.lastActivity` to `FanficSortOption`**

In `FanficFilterView.swift`, change lines 46-52 from:

```swift
enum FanficSortOption: String, CaseIterable {
    case dateAdded = "Date Added"
    case dateUpdated = "Date Updated"
    case wordCount = "Word Count"
    case title = "Title"
    case chapters = "Chapters"
}
```

to:

```swift
enum FanficSortOption: String, CaseIterable {
    case lastActivity = "Last Activity"
    case dateAdded = "Date Added"
    case dateUpdated = "Date Updated"
    case wordCount = "Word Count"
    case title = "Title"
    case chapters = "Chapters"
}
```

`.lastActivity` is first so it renders as the leading chip in the sort row (the filter view iterates `FanficSortOption.allCases`).

- [ ] **Step 2: Change `FanficFilterState` default sort and reset**

In the same file, change line 22:

```swift
var sortBy: FanficSortOption = .dateAdded
```

to:

```swift
var sortBy: FanficSortOption = .lastActivity
```

And line 39 inside `reset()`:

```swift
sortBy = .dateAdded
```

to:

```swift
sortBy = .lastActivity
```

- [ ] **Step 3: Add the `.lastActivity` branch to the `filteredFanfics` sort switch**

In `FanficLibraryView.swift`, find the sort switch at lines 87-101 (inside `filteredFanfics`):

```swift
switch filterState.sortBy {
case .dateAdded:
    return result.sorted { ascending ? $0.addedAt < $1.addedAt : $0.addedAt > $1.addedAt }
case .dateUpdated:
    ...
```

Insert a new `case .lastActivity` branch BEFORE the existing `case .dateAdded`:

```swift
switch filterState.sortBy {
case .lastActivity:
    return result.sorted { ascending
        ? ($0.lastReadAt ?? $0.addedAt) < ($1.lastReadAt ?? $1.addedAt)
        : ($0.lastReadAt ?? $0.addedAt) > ($1.lastReadAt ?? $1.addedAt)
    }
case .dateAdded:
    return result.sorted { ascending ? $0.addedAt < $1.addedAt : $0.addedAt > $1.addedAt }
case .dateUpdated:
    ...
```

- [ ] **Step 4: Update `ComicLibraryView.displayedComics` sort comparator**

In `ComicLibraryView.swift`, find the sort at lines 41-44:

```swift
return ready.sorted { lhs, rhs in
    if lhs.isArchived != rhs.isArchived { return !lhs.isArchived }
    return lhs.addedAt > rhs.addedAt
}
```

Change the final `return` line to:

```swift
return ready.sorted { lhs, rhs in
    if lhs.isArchived != rhs.isArchived { return !lhs.isArchived }
    return (lhs.lastReadAt ?? lhs.addedAt) > (rhs.lastReadAt ?? rhs.addedAt)
}
```

The archived-to-bottom rule (first conditional) stays intact.

- [ ] **Step 5: Verify the build**

```bash
cd ios/Astral && xcodebuild -scheme Astral -sdk iphonesimulator -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

If the build fails with "Switch must be exhaustive over cases of 'FanficSortOption'", you missed Step 3 — fix it before continuing.

- [ ] **Step 6: Commit**

```bash
git add ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficFilterView.swift \
        ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficLibraryView.swift \
        ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicLibraryView.swift
git commit -m "[ios] AST-13 default library sort by last read

Comic: displayedComics sorts by lastReadAt ?? addedAt descending
(archived-to-bottom rule unchanged).

Fanfic: new FanficSortOption.lastActivity case, set as default for
FanficFilterState.sortBy and reset(). filteredFanfics handles the
new case via lastReadAt ?? addedAt. Existing sort options unchanged.

In-memory coalesce over unchanged @Query output. No schema change,
no backfill, no ComicFilterView (AST-15 covers that)."
```

---

### Task 2: Manual simulator verification (user)

The plan handoff point — subagents cannot run the simulator. User must verify before the PR is opened.

- [ ] **Step 1: Launch the app**

From Xcode on `feature/ast-13-default-library-sort`, Cmd+R to build + run.

- [ ] **Step 2: Comic library check**

  1. Open the Comic tab.
  2. Note the current order of the grid — which comic is at the top?
  3. Find an older comic (added weeks ago) that you HAVEN'T read recently. Open it in the reader — this updates `lastReadAt`.
  4. Go back to the comic library. Expected: the comic you just read is now at (or near) the top, above comics that were added more recently but not read.
  5. Verify archived comics are still at the bottom (if any exist).

- [ ] **Step 3: Fanfic library check**

  1. Open the Fanfic tab.
  2. Tap the filter icon. Expected: the sort chip selector shows "Last Activity" selected by default. Verify all 6 chips are present: Last Activity, Date Added, Date Updated, Word Count, Title, Chapters.
  3. Switch to "Date Added" — the old order returns.
  4. Switch back to "Last Activity" — the new order.
  5. Tap "Reset" in the filter — sort goes back to "Last Activity" (not "Date Added").
  6. Dismiss filter. Open an older fanfic in the reader. Go back — it should move to the top of the grid.

- [ ] **Step 4: Edge cases**

  1. Confirm never-read items (fresh adds with `lastReadAt == nil`) still appear in their `addedAt` position relative to other never-read items.
  2. Verify the ascending toggle still works: turn it on for "Last Activity" — oldest-activity items come to the top.

- [ ] **Step 5: If any check fails**

Stop. Describe what you saw and I'll iterate. Do not open the PR until all checks pass.

---

### Task 3: Push branch and open PR

- [ ] **Step 1: Push**

```bash
git push -u origin feature/ast-13-default-library-sort
```

- [ ] **Step 2: Open PR**

```bash
gh pr create --base development --title "[ios] AST-13 default library sort by last read" --body "$(cat <<'EOF'
## Summary

Both libraries now default-sort by most recent reading activity (`lastReadAt ?? addedAt` descending), not `addedAt` alone.

- **Comic library:** `displayedComics` comparator updated; archived-to-bottom rule preserved.
- **Fanfic library:** new `FanficSortOption.lastActivity` chip in the filter UI, set as the new default for `FanficFilterState.sortBy` and `reset()`. Existing sort options still available.

In-memory coalesce over unchanged `@Query` output. No schema changes, no migration.

Closes [AST-13](https://linear.app/nnetraganti/issue/AST-13/library-default-sort-both-comic-and-fanfic-libraries-by-last-read).

Spec: `docs/superpowers/specs/2026-04-17-ast-13-default-library-sort-design.md`

## Test plan

- [x] `xcodebuild -scheme Astral -sdk iphonesimulator build` succeeds
- [x] Comic: recently-read old comic surfaces above newly-added unread comic
- [x] Fanfic: "Last Activity" chip is the new default; all 6 sort options work; reset restores "Last Activity"
- [x] Archived comics still pinned to bottom
- [x] Never-read items fall back to `addedAt` ordering
- [x] Ascending toggle works for the new sort option

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: Report PR URL**

Print the PR URL returned by `gh pr create`.

---

## Self-review notes

**Spec coverage:**
- Fanfic enum new case + default → Task 1 Steps 1, 2 ✓
- Fanfic switch branch → Task 1 Step 3 ✓
- Comic comparator update → Task 1 Step 4 ✓
- `@Query` sort clauses untouched → spec says so, tasks don't touch them ✓
- Manual verification → Task 2 ✓

**Placeholder scan:** none.

**Type consistency:** `FanficSortOption.lastActivity`, `FanficFilterState.sortBy`, `filteredFanfics`, `displayedComics`, `lastReadAt`, `addedAt` — all match what's in the spec and existing codebase.

**Known sharp edge:** Task 1 Steps 1-3 must be applied together before the first build — adding the enum case without the switch branch will fail to compile. Called out in Step 1's intro and in Step 5's error-handling note.
