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

- Changing `LocalFanfic.lastReadChapterNumber` from `Int` to `Double` — migration risk is disproportionate to gain.
- Restoring sub-paragraph reading position (word-level).
- Changing how progress is persisted — only the scroll trigger mechanism changes.
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

### Fix A — `calculateScrollTarget`: use `Double` equality for chapter match

Replace:
```swift
Int(currentChapter.chapterNumber) == fanfic.lastReadChapterNumber
```
With:
```swift
currentChapter.chapterNumber == Double(fanfic.lastReadChapterNumber)
```

This ensures that if the reader was opened on `ch 3.5` but `lastReadChapterNumber` was stored as `3`, the guard fails and no scroll restore is attempted (which is correct — the session was not on this chapter). If `lastReadChapterNumber` is `3` and `currentChapter.chapterNumber` is `3.0`, the equality holds (`3.0 == 3.0`). Whole-number chapters continue to work identically.

**Decision (autonomous)**: `Double(Int)` comparison is exact for all integer values ≤ 2^53 — no floating-point imprecision risk here.

### Fix B — `FanficContinueReadingButton.readingState`: use `Double` equality for chapter lookup

Replace:
```swift
chapters.first(where: { Int($0.chapterNumber) == lastReadChapterNumber })
```
With:
```swift
chapters.first(where: { $0.chapterNumber == Double(lastReadChapterNumber) })
```

For fractional chapters, `Double(3)` is `3.0`, which does not equal `3.5` — so the lookup returns `nil`. The `nil` path then falls through to the next `chapters.first(where: { $0.chapterNumber > Double(lastReadChapterNumber) })` which picks the next chapter after 3.0 — this is the correct "continue" behavior when the exact chapter cannot be found.

**Decision (autonomous)**: This means a user who was mid-chapter 3.5 and whose `lastReadChapterNumber` was saved as `3` will be sent to the *next* chapter (e.g. ch 4.0) on re-open, not ch 3.5. This is a minor UX gap for the fractional-chapter edge case, but it is correct behavior (no scroll position was saved for ch 3.0) and is far better than scrolling to the wrong position in the wrong chapter. The proper long-term fix would be to store `lastReadChapterNumber` as `Double` — noted as an open question.

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

1. **Keep `lastReadChapterNumber: Int`** — adding a `Double` variant to `LocalFanfic` requires a SwiftData migration. The `Int` storage is sufficient when both write-side (`navigateTo`, `onAppear`) and read-side (`calculateScrollTarget`, `FanficContinueReadingButton`) use consistent `Double()` conversion.

2. **Fractional chapter routing fallback** — when the exact chapter cannot be matched (fractional chapter stored as `Int`), route to the next chapter rather than the exact chapter. This is preferable to routing to a different chapter with a bad scroll position.

3. **No animation on scroll restore** — instant jump matches the comic reader's restore behavior and avoids animation-vs-layout conflicts.

4. **`hasRestoredScroll = true` set immediately after `proxy.scrollTo`** — paragraph `.onAppear` callbacks that fire during the scroll gesture would otherwise immediately overwrite `scrollOffsetPercent`. Setting the flag synchronously (not with a 0.5s delay) closes this window.

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
- Two commits: one for `calculateScrollTarget` + `FanficContinueReadingButton` (RC-1/RC-3), one for scroll trigger mechanism (RC-2).
- PR off `development`. Description includes `Fixes AST-14`.
