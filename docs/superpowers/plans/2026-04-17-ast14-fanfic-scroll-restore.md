# AST-14 — Fanfic Scroll-Position Restore: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Fix the "Continue Reading" scroll restore so the reader reliably lands at the last-read paragraph rather than the top of the chapter.

**Architecture:** Multiple Swift files, three commits. Includes SwiftData model migration. No new state variables.

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

## Task 1 — Migrate `LocalFanfic.lastReadChapterNumber` from `Int` to `Double?`

**Files:**
- Modify: `ios/Astral/Packages/Core/Sources/Core/Models/LocalFanfic.swift`
- Modify: `ios/Astral/Packages/Core/Sources/Core/PreviewMocks.swift`
- Modify: `ios/Astral/Packages/Core/Tests/CoreTests/LocalFanficTests.swift`
- Modify: `ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift`
- Modify: `ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift`
- Modify: `ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficLibraryView.swift`
- Modify: `ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Stats/FanficStatsView.swift`
- Modify: `ios/Astral/Packages/FanficFeature/Sources/FanficFeature/ViewModels/FanficLibraryViewModel.swift`

### Step 1a — Model declaration (`LocalFanfic.swift`)

Change property declaration and init parameter:

```swift
// BEFORE
public var lastReadChapterNumber: Int
// init param:
lastReadChapterNumber: Int = 0

// AFTER
public var lastReadChapterNumber: Double?
// init param:
lastReadChapterNumber: Double? = nil
```

SwiftData handles this widening automatically on iOS 17.2 — no `.versioned` schema required.

### Step 1b — Write sites in `FanficReaderView.swift` (~lines 265, 737)

```swift
// BEFORE
fanfic.lastReadChapterNumber = Int(currentChapter.chapterNumber)
// AFTER
fanfic.lastReadChapterNumber = currentChapter.chapterNumber
```

(Both write sites at lines 265 and 737 follow the same pattern.)

### Step 1c — Read sites in `FanficReaderView.swift` — progress calculation (~lines 268, 741)

```swift
// BEFORE
fanfic.progressPercent = Double(fanfic.lastReadChapterNumber) / Double(fanfic.totalChapters)
// AFTER
fanfic.progressPercent = (fanfic.lastReadChapterNumber ?? 0) / Double(fanfic.totalChapters)
```

### Step 1d — Read site in `FanficReaderView.swift` — API progress request (~line 292)

`FanficProgressRequest.lastChapterNumber` is `Int` (backend contract — do not change the DTO). Cast at the network boundary:

```swift
// BEFORE
lastChapterNumber: fanfic.lastReadChapterNumber,
// AFTER
lastChapterNumber: Int(fanfic.lastReadChapterNumber ?? 0),
```

### Step 1e — `FanficDetailView.swift` — `FanficContinueReadingButton` struct

Change the struct's stored property and init from `Int` to `Double?`. Update the `readingState` computed property:

```swift
// BEFORE
let lastReadChapterNumber: Int
// ...
if lastReadChapterNumber == 0 { return .startReading }
// AFTER
let lastReadChapterNumber: Double?
// ...
guard let lastRead = lastReadChapterNumber, lastRead > 0 else { return .startReading }
```

The call site (~line 55) passes `fanfic.lastReadChapterNumber` directly — type now matches.

### Step 1f — `FanficDetailView.swift` — `isLastRead`/`isRead` comparisons (~lines 123–124)

```swift
// BEFORE
isLastRead: chapter.chapterNumber == Double(fanfic.lastReadChapterNumber),
isRead: chapter.chapterNumber < Double(fanfic.lastReadChapterNumber),
// AFTER
isLastRead: chapter.chapterNumber == (fanfic.lastReadChapterNumber ?? 0),
isRead: chapter.chapterNumber < (fanfic.lastReadChapterNumber ?? 0),
```

### Step 1g — `FanficLibraryView.swift` read sites (~lines 240, 310, 461, 473)

```swift
// ~line 240
let lastRead = Double(fanfic.lastReadChapterNumber)  →  let lastRead = fanfic.lastReadChapterNumber ?? 0

// ~line 310
Double(fanfic.lastReadChapterNumber) / Double(fanfic.totalChapters)
→  (fanfic.lastReadChapterNumber ?? 0) / Double(fanfic.totalChapters)

// ~line 461
fanfic.lastReadChapterNumber > 0  →  (fanfic.lastReadChapterNumber ?? 0) > 0

// ~line 473
"\(fanfic.lastReadChapterNumber)"  →  "\(Int(fanfic.lastReadChapterNumber ?? 0))"
```

### Step 1h — `FanficStatsView.swift` read sites (~lines 100–101, 385–387, 393, 413, 418)

```swift
// ~lines 100–101
fanfics.reduce(0) { $0 + $1.lastReadChapterNumber }
→  fanfics.reduce(0) { $0 + Int($1.lastReadChapterNumber ?? 0) }

// ~lines 385–387: update tuple type
lastReadChapterNumber: Int  →  lastReadChapterNumber: Double?

// ~line 393
s.lastReadChapterNumber >= s.totalChapters
→  Int(s.lastReadChapterNumber ?? 0) >= s.totalChapters

// ~lines 413, 418
$0.totalChapters - $0.lastReadChapterNumber
→  $0.totalChapters - Int($0.lastReadChapterNumber ?? 0)
```

### Step 1i — `FanficLibraryViewModel.swift` read/write sites (~lines 122–123)

```swift
// BEFORE
progress.lastChapterNumber > fanfic.lastReadChapterNumber
fanfic.lastReadChapterNumber = progress.lastChapterNumber
// AFTER
Double(progress.lastChapterNumber) > (fanfic.lastReadChapterNumber ?? -1)
fanfic.lastReadChapterNumber = Double(progress.lastChapterNumber)
```

### Step 1j — `PreviewMocks.swift` and `LocalFanficTests.swift`

Update fanfic mock init calls to pass `Double` literals (e.g., `lastReadChapterNumber: 12` — Swift infers `Double` from the `Double?` param, so no change needed unless the literal is `0` which was the default). Update test assertions from `== 0` to `== nil` for the "not yet read" case and `== 12.0` for explicit values.

- [ ] Step 1a — model declaration
- [ ] Step 1b — write sites in `FanficReaderView.swift`
- [ ] Step 1c — progress calc read sites in `FanficReaderView.swift`
- [ ] Step 1d — API request write site in `FanficReaderView.swift`
- [ ] Step 1e — `FanficContinueReadingButton` struct
- [ ] Step 1f — `isLastRead`/`isRead` comparisons in `FanficDetailView.swift`
- [ ] Step 1g — `FanficLibraryView.swift` read sites
- [ ] Step 1h — `FanficStatsView.swift` read sites
- [ ] Step 1i — `FanficLibraryViewModel.swift`
- [ ] Step 1j — mocks and tests
- [ ] Build succeeds with no new errors
- [ ] Commit: `[ios] AST-14 migrate LocalFanfic.lastReadChapterNumber from Int to Double?`

---

## Task 2 — Fix chapter-match comparisons (now simplified by Double storage)

**Files:**
- Modify: `ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift`
- Modify: `ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift`

After the Task 1 migration, both `currentChapter.chapterNumber` and `fanfic.lastReadChapterNumber` are `Double`. The comparisons simplify to direct equality — no casts required.

### Step 2a — `calculateScrollTarget()` in `FanficReaderView.swift` (~line 708)

```swift
// BEFORE (post-migration, still has old cast)
Int(currentChapter.chapterNumber) == fanfic.lastReadChapterNumber
// AFTER
currentChapter.chapterNumber == (fanfic.lastReadChapterNumber ?? 0)
```

### Step 2b — `FanficContinueReadingButton.readingState` in `FanficDetailView.swift` (~line 753)

After Step 1e, `lastReadChapterNumber` is `Double?` and `lastRead` is the unwrapped `Double`. The chapter lookup becomes:

```swift
// BEFORE (post-migration, still has old cast)
chapters.first(where: { Int($0.chapterNumber) == lastReadChapterNumber })
// AFTER
chapters.first(where: { $0.chapterNumber == lastRead })
```

- [ ] Apply Step 2a to `FanficReaderView.swift`
- [ ] Apply Step 2b to `FanficDetailView.swift`
- [ ] Build succeeds
- [ ] Commit: `[ios] AST-14 fix chapter-match comparisons after Double migration`

---

## Task 3 — Replace `DispatchQueue.main.asyncAfter` with data-driven scroll trigger (unchanged from original plan)

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

## Task 4 — Create PR and update Linear

- [ ] `git push -u origin feature/ast-14-fanfic-scroll-restore`
- [ ] Create PR off `development` with title `[ios] AST-14 fix fanfic scroll-position restore`
- [ ] PR body includes:
  - Summary of model migration (Int → Double?) and the two reader root causes fixed
  - Note: do not roll back after install — SwiftData migration is one-way
  - `Fixes AST-14`
- [ ] Move AST-14 to **In Review** in Linear
