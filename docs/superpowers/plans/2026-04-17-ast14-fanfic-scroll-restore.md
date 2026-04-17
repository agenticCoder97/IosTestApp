# AST-14 — Fanfic Scroll-Position Restore: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Fix the "Continue Reading" scroll restore so the reader reliably lands at the last-read paragraph rather than the top of the chapter.

**Architecture:** Two Swift files, two commits. No model changes. No new state variables.

**Tech Stack:** SwiftUI, iOS 17.2+, Swift 6.

**Reference spec:** [docs/superpowers/specs/2026-04-17-ast14-fanfic-scroll-restore-design.md](../specs/2026-04-17-ast14-fanfic-scroll-restore-design.md)

**Linear**: [AST-14](https://linear.app/nnetraganti/issue/AST-14)
**Branch**: `feature/ast-14-fanfic-scroll-restore`

---

## Testing Approach

Build + simulator manual verification after each commit. No unit tests (view lifecycle). See spec Testing section for the five verification scenarios.

Build command:
```
cd ios/Astral && xcodebuild -scheme Astral -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build
```

---

## Task 1 — Fix `Int()` truncation in chapter-match comparisons

**Files:**
- Modify: `ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift`
- Modify: `ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift`

### Step 1a — `calculateScrollTarget()` in `FanficReaderView.swift`

Locate `calculateScrollTarget()` (~line 706). Change the chapter-equality guard from:

```swift
// BEFORE
guard let pct = fanfic.scrollOffsetPercent, pct > 0,
      Int(currentChapter.chapterNumber) == fanfic.lastReadChapterNumber,
      !paragraphs.isEmpty else { return }
```

To:

```swift
// AFTER
guard let pct = fanfic.scrollOffsetPercent, pct > 0,
      currentChapter.chapterNumber == Double(fanfic.lastReadChapterNumber),
      !paragraphs.isEmpty else { return }
```

### Step 1b — `FanficContinueReadingButton.readingState` in `FanficDetailView.swift`

Locate `FanficContinueReadingButton.readingState` (~line 753). Change:

```swift
// BEFORE
if let current = chapters.first(where: { Int($0.chapterNumber) == lastReadChapterNumber }) {
    return .continueReading(current)
}
```

To:

```swift
// AFTER
if let current = chapters.first(where: { $0.chapterNumber == Double(lastReadChapterNumber) }) {
    return .continueReading(current)
}
```

- [ ] Apply change to `FanficReaderView.swift` (Step 1a)
- [ ] Apply change to `FanficDetailView.swift` (Step 1b)
- [ ] Build succeeds
- [ ] Commit: `[ios] AST-14 fix Int truncation in chapter-match comparisons for scroll restore`

---

## Task 2 — Replace `DispatchQueue.main.asyncAfter` with data-driven scroll trigger

**Files:**
- Modify: `ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift`

### Step 2 — Rewrite the `ScrollViewReader.onAppear` block (~lines 157–169)

Current code:

```swift
ScrollViewReader { proxy in
    ScrollView {
        // ... content ...
    }
    .onAppear {
        guard !hasRestoredScroll else { return }
        if let target = scrollTargetIndex, !paragraphs.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation { proxy.scrollTo(target, anchor: .top) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    hasRestoredScroll = true
                }
            }
        } else {
            hasRestoredScroll = true
        }
    }
}
```

Replace with:

```swift
ScrollViewReader { proxy in
    ScrollView {
        // ... content ...
    }
    .onAppear {
        guard !hasRestoredScroll else { return }
        if let target = scrollTargetIndex {
            proxy.scrollTo(target, anchor: .top)
            hasRestoredScroll = true
        } else {
            hasRestoredScroll = true
        }
    }
    .onChange(of: scrollTargetIndex) { _, newTarget in
        guard !hasRestoredScroll, let target = newTarget else { return }
        proxy.scrollTo(target, anchor: .top)
        hasRestoredScroll = true
    }
}
```

Key changes:
- Removed both `DispatchQueue.main.asyncAfter` calls.
- Removed `withAnimation` wrapper on `proxy.scrollTo` — instant jump, no animation conflict.
- Removed `!paragraphs.isEmpty` guard in `onAppear` — `scrollTargetIndex` is only ever set in `calculateScrollTarget()` which itself guards `!paragraphs.isEmpty`, so by the time `scrollTargetIndex` is non-nil, paragraphs are guaranteed non-empty.
- `hasRestoredScroll = true` set immediately after `proxy.scrollTo` (not 0.5s later) to close the window where paragraph `.onAppear` callbacks could overwrite the restored position.
- Added `.onChange(of: scrollTargetIndex)` to handle the edge case where `loadChapter()` completes after the `ScrollView` has already appeared (network path on slow connections).

- [ ] Apply the rewrite
- [ ] Build succeeds
- [ ] Manual verify: open fanfic from "Continue Reading" → lands at saved paragraph
- [ ] Manual verify: first open (no history) → lands at top, no crash
- [ ] Manual verify: navigate to next chapter → opens at top (no spurious scroll)
- [ ] Commit: `[ios] AST-14 replace asyncAfter timing hack with onChange scroll trigger`

---

## Task 3 — Create PR and update Linear

- [ ] `git push -u origin feature/ast-14-fanfic-scroll-restore`
- [ ] Create PR off `development` with title `[ios] AST-14 fix fanfic scroll-position restore`
- [ ] PR body includes:
  - Summary of the two root causes fixed
  - `Fixes AST-14`
- [ ] Move AST-14 to **In Review** in Linear
