# AST-14 — Fanfic Scroll-Position Restore: Design

- **Date**: 2026-04-17
- **Issue**: [AST-14](https://linear.app/nnetraganti/issue/AST-14)
- **Closes**: AST-14
- **Files**: `ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift` (primary), `ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift` (secondary)
- **Branch**: `feature/ast-14-fanfic-scroll-restore`

---

## Summary

Opening a fanfic from the "Continue Reading" button drops the user at the top of the chapter instead of restoring the last scroll position. The bug has two confirmed root causes: (1) the scroll-target calculation uses `Int()` truncation that can match the wrong chapter in the presence of fractional chapter numbers, and (2) the `ScrollViewReader.onAppear` fires the scroll before the view has finished layout, relying on an arbitrary 300 ms `DispatchQueue.main.asyncAfter` delay that is fragile. A third, latent issue is that `FanficContinueReadingButton` also uses `Int()` truncation to pick the resume chapter, which can silently select the wrong chapter.

The fix is small: replace the `DispatchQueue` approach with a data-driven `.onChange(of: scrollTargetIndex)` trigger and fix the `Int()` truncation comparison in both `calculateScrollTarget` and `FanficContinueReadingButton`.

---

## Goals

1. When "Continue Reading" opens a chapter, scroll to the saved `scrollOffsetPercent` paragraph index reliably.
2. Ensure the chapter-match comparison in `calculateScrollTarget` is not defeated by fractional chapter numbers.
3. Ensure `FanficContinueReadingButton` routes to the correct chapter for fractional chapter numbers.
4. Eliminate the fragile `DispatchQueue.main.asyncAfter` timing hack.
5. Preserve the `hasRestoredScroll` guard so live `.onAppear` paragraph tracking is not overwritten during the restore scroll.

## Non-goals

- Restoring sub-paragraph reading position (word-level).
- Changing how progress is persisted — only the scroll trigger mechanism and model field type change.
- Addressing the `pct > 0` guard (intentional — scroll to index 0 is the natural default).

---

## Root Cause Analysis

### RC-1 — `Int()` truncation breaks chapter matching (confirmed)

**Location**: `FanficReaderView.calculateScrollTarget()` line 708, `FanficContinueReadingButton.readingState` line 753.

`fanfic.lastReadChapterNumber` is stored as `Int(currentChapter.chapterNumber)`. For a chapter with `chapterNumber = 3.5`, the stored value is `3`. `FanficContinueReadingButton` then picks the chapter where `Int($0.chapterNumber) == 3` — which matches `ch 3.0` before `ch 3.5` because chapters are sorted ascending. The reader opens `ch 3.0` while `scrollOffsetPercent` was saved for `ch 3.5`. Inside `calculateScrollTarget`, `Int(currentChapter.chapterNumber) == fanfic.lastReadChapterNumber` evaluates as `Int(3.0) == 3` — the guard passes, but the scroll index is applied to the wrong chapter's paragraph array.

**Frequency**: Only affects fanfics with fractional chapter numbers (e.g., AO3 bonus chapters). Whole-number chapters are unaffected.

### RC-2 — `DispatchQueue.main.asyncAfter` fires before layout is stable (confirmed)

**Location**: `FanficReaderView` body, lines 157–168.

The scroll is triggered from `ScrollViewReader.onAppear` with a 300 ms delay. The delay is intended to wait for layout, but this is a timing assumption, not a data-driven signal. On fast devices with cached (local file) chapters, layout may complete before 300 ms. On slow devices or large chapters, layout may not be complete at 300 ms. More importantly: `scrollTargetIndex` is set in `calculateScrollTarget()`, which runs synchronously at the end of `loadChapter()`, before `isLoading = false`. By the time the ScrollView mounts and `onAppear` fires, `scrollTargetIndex` is already set — so the asyncAfter is not needed at all. The simpler and more robust approach is to trigger the scroll when `scrollTargetIndex` transitions from `nil` to a value.

### RC-3 — `FanficContinueReadingButton` ambiguous chapter lookup (confirmed, same root as RC-1)

**Location**: `FanficDetailView.swift` line 753.

`chapters.first(where: { Int($0.chapterNumber) == lastReadChapterNumber })` finds the first chapter whose `Int()` truncation matches. For chapters sorted ascending, `ch 3.0` is found before `ch 3.5` even if the saved session was on `ch 3.5`. The fix is to compare `$0.chapterNumber == Double(lastReadChapterNumber)` — which returns `nil` for fractional chapters (no exact match), then falls through to the next candidate. See fix design below for how this is handled.

---

## Design

### Model migration — `LocalFanfic.lastReadChapterNumber`: `Int` → `Double?`

#### Current state

`LocalFanfic.lastReadChapterNumber` is declared as `public var lastReadChapterNumber: Int` (non-optional, default `0`). The target type is `Double?` (optional, keeping the "not yet read" semantic explicit via `nil` rather than the sentinel `0`).

**All read/write sites in `ios/`:**

| File | Nature | Note |
|---|---|---|
| `Core/Models/LocalFanfic.swift` | Declaration + init param | Change `Int` → `Double?`, default `nil` |
| `FanficFeature/Reader/FanficReaderView.swift` line 265 | **Write** — `fanfic.lastReadChapterNumber = Int(currentChapter.chapterNumber)` | Change to `= currentChapter.chapterNumber` |
| `FanficFeature/Reader/FanficReaderView.swift` line 268 | **Read** — `Double(fanfic.lastReadChapterNumber)` in progress calc | Simplifies to `(fanfic.lastReadChapterNumber ?? 0)` |
| `FanficFeature/Reader/FanficReaderView.swift` line 278 | **Read** — `lastChapterNumber: Int(currentChapter.chapterNumber)` passed to `FanficProgressRequest` | DTO `FanficProgressRequest.lastChapterNumber` is `Int`; keep `Int(currentChapter.chapterNumber)` here (DTO is unchanged) |
| `FanficFeature/Reader/FanficReaderView.swift` line 292 | **Read** — `lastChapterNumber: fanfic.lastReadChapterNumber` in progress request | Change to `lastChapterNumber: Int(fanfic.lastReadChapterNumber ?? 0)` |
| `FanficFeature/Reader/FanficReaderView.swift` line 708 | **Read** — `Int(currentChapter.chapterNumber) == fanfic.lastReadChapterNumber` | Simplifies to `currentChapter.chapterNumber == (fanfic.lastReadChapterNumber ?? 0)` (both `Double`) |
| `FanficFeature/Reader/FanficReaderView.swift` line 737 | **Write** — `fanfic.lastReadChapterNumber = Int(chapter.chapterNumber)` | Change to `= chapter.chapterNumber` |
| `FanficFeature/Reader/FanficReaderView.swift` line 741 | **Read** — `Double(fanfic.lastReadChapterNumber)` in progress calc | Simplifies to `(fanfic.lastReadChapterNumber ?? 0)` |
| `FanficFeature/Library/FanficDetailView.swift` line 55 | **Read** — passed as `lastReadChapterNumber:` to `FanficContinueReadingButton` | Change `FanficContinueReadingButton.lastReadChapterNumber` param type to `Double?` |
| `FanficFeature/Library/FanficDetailView.swift` line 123–124 | **Read** — `Double(fanfic.lastReadChapterNumber)` for `isLastRead`/`isRead` comparisons | Simplifies to `(fanfic.lastReadChapterNumber ?? 0)` |
| `FanficFeature/Library/FanficDetailView.swift` line 738 | **`FanficContinueReadingButton` param** — `let lastReadChapterNumber: Int` | Change to `Double?` |
| `FanficFeature/Library/FanficDetailView.swift` line 749 | **Read** — `if lastReadChapterNumber == 0` | Change to `guard let lastRead = lastReadChapterNumber, lastRead > 0 else { ... }` |
| `FanficFeature/Library/FanficDetailView.swift` line 753 | **Read** — `Int($0.chapterNumber) == lastReadChapterNumber` | Simplifies to `$0.chapterNumber == lastRead` (both `Double`) |
| `FanficFeature/Library/FanficDetailView.swift` line 756 | **Read** — `$0.chapterNumber > Double(lastReadChapterNumber)` | Simplifies to `$0.chapterNumber > lastRead` |
| `FanficFeature/Library/FanficLibraryView.swift` line 240 | **Read** — `Double(fanfic.lastReadChapterNumber)` | Simplifies to `(fanfic.lastReadChapterNumber ?? 0)` |
| `FanficFeature/Library/FanficLibraryView.swift` line 310 | **Read** — `Double(fanfic.lastReadChapterNumber) / Double(fanfic.totalChapters)` | Simplifies to `(fanfic.lastReadChapterNumber ?? 0) / Double(fanfic.totalChapters)` |
| `FanficFeature/Library/FanficLibraryView.swift` line 461 | **Read** — `fanfic.lastReadChapterNumber > 0` | Change to `(fanfic.lastReadChapterNumber ?? 0) > 0` |
| `FanficFeature/Library/FanficLibraryView.swift` line 473 | **Read** — `"\(fanfic.lastReadChapterNumber)"` in UI string | Change to `"\(Int(fanfic.lastReadChapterNumber ?? 0))"` |
| `FanficFeature/Stats/FanficStatsView.swift` lines 100–101 | **Read** — `.reduce(0) { $0 + $1.lastReadChapterNumber }` | Change to `.reduce(0) { $0 + Int($1.lastReadChapterNumber ?? 0) }` |
| `FanficFeature/Stats/FanficStatsView.swift` line 385–387 | **Read** — tuple type `lastReadChapterNumber: Int` | Change tuple field to `Double?` |
| `FanficFeature/Stats/FanficStatsView.swift` line 393 | **Read** — `s.lastReadChapterNumber >= s.totalChapters` | Change to `Int(s.lastReadChapterNumber ?? 0) >= s.totalChapters` |
| `FanficFeature/Stats/FanficStatsView.swift` lines 413, 418 | **Read** — `$0.totalChapters - $0.lastReadChapterNumber` | Change to `$0.totalChapters - Int($0.lastReadChapterNumber ?? 0)` |
| `FanficFeature/ViewModels/FanficLibraryViewModel.swift` line 122 | **Read** — `progress.lastChapterNumber > fanfic.lastReadChapterNumber` | `ProgressResponse.lastChapterNumber` is `Int`; change to `Double(progress.lastChapterNumber) > (fanfic.lastReadChapterNumber ?? -1)` |
| `FanficFeature/ViewModels/FanficLibraryViewModel.swift` line 123 | **Write** — `fanfic.lastReadChapterNumber = progress.lastChapterNumber` | Change to `= Double(progress.lastChapterNumber)` |
| `Core/PreviewMocks.swift` lines 141, 165, 186 | **Read** — fanfic preview mocks pass `lastReadChapterNumber: 12`, etc. | Change to `Double` literals e.g. `12.0` or just `12` (Int literal is assignable to `Double?`) |
| `Core/Tests/CoreTests/LocalFanficTests.swift` | **Test** — `#expect(fanfic.lastReadChapterNumber == 0)` and `lastReadChapterNumber: 12` | Update assertions and init param to `Double?` |

Note: `ComicFeature` files and `LocalComic.lastReadChapterNumber` are **not** changed — that is a separate model with its own `Int` field. Only `LocalFanfic` is migrated.

#### SwiftData migration behavior

SwiftData on iOS 17.2 handles numeric widening (from `Int` to `Double`) automatically for stored properties — it reads the existing integer bytes and coerces to the wider type on first access. No explicit `.versioned` schema migration is required. The project already uses `@Attribute(.unique)` patterns (not `#Unique` macro) per CLAUDE.md "Architecture Corrections Applied", so there are no compatibility blockers.

**Fallback data mapping**: existing `Int` values widen losslessly (e.g. `3 → 3.0`). No data loss. The sentinel `0` (not-yet-read) migrates to `0.0`; call sites that previously tested `== 0` should be updated to test `== nil` or `== 0.0` (or unwrap with `?? 0`).

**Breaking change notice**: this is a persisted model change. Once the new app binary runs against an existing SwiftData store, the migration runs automatically and is irreversible. Users must not roll back to a prior build — doing so will cause SwiftData to encounter a `Double` column where it expects `Int`, which may result in a store error or data reset depending on SwiftData's error policy. This is acceptable for a private single-user sideloaded app.

### Fix A — `calculateScrollTarget`: native `Double` equality for chapter match

After migration, both sides of the comparison are `Double`. Replace:
```swift
Int(currentChapter.chapterNumber) == fanfic.lastReadChapterNumber
```
With:
```swift
currentChapter.chapterNumber == (fanfic.lastReadChapterNumber ?? 0)
```

No coercion needed. If `lastReadChapterNumber` is `nil` (never read), the guard fails at the `pct > 0` check before reaching this line anyway.

### Fix B — `FanficContinueReadingButton.readingState`: native `Double` equality for chapter lookup

After migration, `lastReadChapterNumber` is `Double?`. Replace:
```swift
chapters.first(where: { Int($0.chapterNumber) == lastReadChapterNumber })
```
With:
```swift
chapters.first(where: { $0.chapterNumber == lastRead })
```

Where `lastRead` is the unwrapped `Double` from the `guard let` above. Exact `Double == Double` comparison — no truncation, no cast.

For fractional chapters, if `lastReadChapterNumber` stored `3.5` (now possible with `Double` storage), the lookup finds `ch 3.5` exactly. For whole-number chapters, `3.0 == 3.0` holds. This is the key fidelity improvement over the `Int` approach.

### Fix C — replace `DispatchQueue.main.asyncAfter` with `.onChange(of: scrollTargetIndex)`

Remove the `ScrollViewReader.onAppear` timing hack entirely. Replace with an `.onChange(of: scrollTargetIndex)` modifier on the `ScrollView` inside `ScrollViewReader`:

```swift
ScrollViewReader { proxy in
    ScrollView {
        // ... content ...
    }
    .onChange(of: scrollTargetIndex) { _, newTarget in
        guard !hasRestoredScroll, let target = newTarget else { return }
        proxy.scrollTo(target, anchor: .top)
        hasRestoredScroll = true
    }
}
```

**Why this works**: `scrollTargetIndex` is set synchronously inside `loadChapter()` before `isLoading` is set to `false`. When `isLoading` becomes false, SwiftUI re-renders and mounts the `ScrollView`. The `onChange` modifier observes `scrollTargetIndex`, which already has a value at mount time — but `onChange` only fires on *transitions*, not on initial value. To handle the initial case where `scrollTargetIndex` is already set when the view mounts, add an `.onAppear` on the `ScrollView` (not the `ScrollViewReader`) that performs the same check:

```swift
ScrollViewReader { proxy in
    ScrollView {
        // ... content ...
    }
    .onAppear {
        guard !hasRestoredScroll, let target = scrollTargetIndex else {
            if scrollTargetIndex == nil { hasRestoredScroll = true }
            return
        }
        proxy.scrollTo(target, anchor: .top)
        hasRestoredScroll = true
    }
    .onChange(of: scrollTargetIndex) { _, newTarget in
        guard !hasRestoredScroll, let target = newTarget else { return }
        proxy.scrollTo(target, anchor: .top)
        hasRestoredScroll = true
    }
}
```

The `onAppear` handles the case where `scrollTargetIndex` was set before the view mounted (the typical "continue reading" flow). The `onChange` handles the case where `loadChapter()` completes slightly after the view mounts (slower network path). This eliminates all timing assumptions.

**Decision (autonomous)**: No `withAnimation` wrapper on `proxy.scrollTo` — the `DispatchQueue` approach had `withAnimation` which could compete with the scroll view's own deceleration. Removing the animation wrapper gives a cleaner instant jump, consistent with the `ComicReaderView` pattern.

**Decision (autonomous)**: Remove the nested `DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { hasRestoredScroll = true }` — `hasRestoredScroll` is now set immediately after `proxy.scrollTo` to prevent any transient paragraph `.onAppear` callbacks from overwriting the restored position.

---

## Decisions Made Autonomously

1. **Migrate `lastReadChapterNumber` to `Double?`** — user decision. Provides exact fractional-chapter fidelity (e.g., ch 3.5 stored as `3.5` not `3`). SwiftData handles numeric widening automatically on iOS 17.2+.

2. **Fractional chapter routing** — with `Double` storage, `FanficContinueReadingButton` now finds the exact fractional chapter (e.g., ch 3.5). The fallback to "next chapter" still applies if `lastReadChapterNumber` is `nil` or has no match.

3. **No animation on scroll restore** — instant jump matches the comic reader's restore behavior and avoids animation-vs-layout conflicts.

4. **`hasRestoredScroll = true` set immediately after `proxy.scrollTo`** — paragraph `.onAppear` callbacks that fire during the scroll gesture would otherwise immediately overwrite `scrollOffsetPercent`. Setting the flag synchronously (not with a 0.5s delay) closes this window.

5. **`FanficProgressRequest.lastChapterNumber` stays `Int`** — the backend API contract uses `Int`. The write path truncates via `Int(currentChapter.chapterNumber)` at the network boundary only; local SwiftData storage uses full `Double` fidelity.

---

## Testing

### Manual verification (simulator)

1. Open a fanfic → read past 3+ paragraphs → background the app → reopen → tap "Continue Reading".
   - **Expected**: reader scrolls to approximately the last-read paragraph on open, not top.
2. Chapter with fractional number (e.g. 3.5) — verify "Continue Reading" routes to the correct chapter (ch 4 if no exact match, not ch 3).
3. First-open (no scroll history, `scrollOffsetPercent == nil`) — reader opens at top, no crash.
4. Navigate to next chapter from footer, then back — verify no spurious scroll on the second chapter (no saved scroll position for it).
5. Chapter navigated via `navigateTo()` resets `hasRestoredScroll = false` and `scrollTargetIndex = nil` — verify next chapter opens at top.

### Build check

```
cd ios/Astral && xcodebuild -scheme Astral -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build
```

No new warnings expected (pure Swift logic changes, no API surface changes).

### No unit tests

Logic is view lifecycle — not practical to unit test without a simulator. Manual verification is the testing plan.

---

## Rollout

- Branch: `feature/ast-14-fanfic-scroll-restore`
- Three commits: (1) model migration `LocalFanfic.lastReadChapterNumber` `Int` → `Double?` + all call sites, (2) simplify chapter-match comparisons now that both sides are `Double`, (3) replace `DispatchQueue.main.asyncAfter` with `.onChange(of: scrollTargetIndex)`.
- PR off `development`. Description includes `Fixes AST-14`.
- **Do not roll back** after the migration commit has been installed on device — SwiftData migration is one-way.
