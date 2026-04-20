# AST-27 + AST-34 — iOS Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land two zero-risk iOS cleanup tickets in one PR — extract MorphLandingView phase-geometry magic numbers + add two doc comments (AST-27 sub-items 2/3/4), and shrink the fanfic reader's in-flow chapter header (AST-34 tweaks 1/2/3).

**Architecture:** Pure refactor + tightening, no behavior change. Single PR closes both Linear tickets via `Closes AST-27` / `Closes AST-34` magic-word lines.

**Tech Stack:** SwiftUI, iOS 17.2 minimum. Build verified with `xcodebuild`.

**Spec:** [docs/superpowers/specs/2026-04-19-ast27-ast34-iOS-cleanup-design.md](../specs/2026-04-19-ast27-ast34-iOS-cleanup-design.md)

**Branch:** `feature/ast-27-ast-34-cleanup` (already created off `origin/development` post-AST-21 merge; spec is committed).

---

## Spec Corrections (from reading the actual code)

The spec was written before re-reading `RootView.swift`. Two adjustments:

1. **Phase 1 fractions are ASYMMETRIC** — gold uses `(0.45, 0.5)` but blue uses `(0.4, 0.45)`. The spec's two-constant pair `phase1HorizontalFraction` / `phase1VerticalFraction` would lose information. Plan uses 4 constants: `phase1GoldHFraction`, `phase1GoldVFraction`, `phase1BlueHFraction`, `phase1BlueVFraction`.
2. **`finalOffsetX/Y` already exist** in `LandingTerminalState.goldOffset` / `LandingTerminalState.blueOffset` (file lines 25-26). Adding duplicates would be confusing — skip them. Phase 3's runPhase3 already pulls from `LandingTerminalState` exclusively, so no work to do there.

Net AST-27 sub-item 2 scope after corrections: 6 named constants total (4 Phase 1 + 2 Phase 2), 4 call-site replacements (the two lines in runPhase1 + two in runPhase2).

---

## File Map

**Modified:**
- `ios/Astral/App/RootView.swift` — `PhaseGeometry` enum (new top-level, file-private), 4 call-site replacements in `runPhase1` + `runPhase2`, 2 doc comments (Phase 3 driver, onDisappear)
- `ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift` — title multiplier (`1.4` → `1.2`), removal of reading-time HStack + computed property, tighter spacings on header VStack + outer ScrollView

No new files. No new tokens. No new dependencies.

---

## Tasks

Each task is a focused commit. iOS build verifies after every code task.

---

### Task 1: AST-27 sub-item 2 — Extract `PhaseGeometry` constants

**Files:**
- Modify: `ios/Astral/App/RootView.swift`

- [ ] **Step 1: Read file to confirm current state**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp"
sed -n '20,40p' ios/Astral/App/RootView.swift
```

Expected: `LandingTerminalState` enum is at lines 23-35. The `MorphLandingView` struct starts at line 73.

- [ ] **Step 2: Add the `PhaseGeometry` enum**

Insert directly above `private struct MorphLandingView: View {` (around line 71, just after `LandingTerminalState`):

```swift
/// Drift-target fractions used by `runPhase1()` and `runPhase2()` to position
/// the gold/blue orbs relative to the screen's halfW/halfH. Extracted from
/// inline literals in those functions (AST-27). Phase 3's terminal state
/// lives in `LandingTerminalState` above. Pure rename — no math change.
private enum PhaseGeometry {
    /// Phase 1 — orbs drift from corners while still small. Asymmetric per the
    /// existing animation: gold pulls slightly farther horizontally, blue
    /// slightly farther vertically.
    static let phase1GoldHFraction: CGFloat = 0.45
    static let phase1GoldVFraction: CGFloat = 0.5
    static let phase1BlueHFraction: CGFloat = 0.4
    static let phase1BlueVFraction: CGFloat = 0.45

    /// Phase 2 — symmetric. Widened from 0.25 to fix orb overlap (AST-2).
    /// Centers stay ≥148pt apart on a 390pt screen, clearing 140pt orbs.
    static let phase2HFraction: CGFloat = 0.38
    static let phase2VFraction: CGFloat = 0.2
}

```

- [ ] **Step 3: Replace Phase 1 call sites**

In `RootView.swift:413-414` (inside `runPhase1`), replace:

```swift
            goldOffset = CGSize(width: -(halfW * 0.45), height: -(halfH * 0.5))
            blueOffset = CGSize(width: halfW * 0.4, height: halfH * 0.45)
```

with:

```swift
            goldOffset = CGSize(
                width: -(halfW * PhaseGeometry.phase1GoldHFraction),
                height: -(halfH * PhaseGeometry.phase1GoldVFraction),
            )
            blueOffset = CGSize(
                width: halfW * PhaseGeometry.phase1BlueHFraction,
                height: halfH * PhaseGeometry.phase1BlueVFraction,
            )
```

- [ ] **Step 4: Replace Phase 2 call sites**

In `RootView.swift:454-455` (inside `runPhase2`), replace:

```swift
            goldOffset = CGSize(width: -(halfW * 0.38), height: -(halfH * 0.2))
            blueOffset = CGSize(width: halfW * 0.38, height: halfH * 0.2)
```

with:

```swift
            goldOffset = CGSize(
                width: -(halfW * PhaseGeometry.phase2HFraction),
                height: -(halfH * PhaseGeometry.phase2VFraction),
            )
            blueOffset = CGSize(
                width: halfW * PhaseGeometry.phase2HFraction,
                height: halfH * PhaseGeometry.phase2VFraction,
            )
```

- [ ] **Step 5: Build**

```bash
cd ios/Astral && xcodebuild -scheme Astral \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' \
  build 2>&1 | grep -E "BUILD|error:" | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Smoke-test landing animation**

Launch the app on the simulator (or open `Astral.xcodeproj` and run). Watch the orbs animate through Phase 1 → Phase 2 → Phase 3 → Phase 4. The animation should be visually identical to before — same curves, same final positions.

If you see any visual regression, the most likely cause is a sign error in the offset calculations (gold uses negative width, blue uses positive — mirror the existing pattern).

- [ ] **Step 7: Commit**

```bash
git add ios/Astral/App/RootView.swift
git commit -m "[ios] AST-27 extract MorphLandingView phase-geometry constants"
```

---

### Task 2: AST-27 sub-item 3 — Phase 3 driver comment

**Files:**
- Modify: `ios/Astral/App/RootView.swift`

- [ ] **Step 1: Locate the morph-spring**

Find `withAnimation(.bouncy(duration: 0.5, extraBounce: 0.15)` inside `runPhase3` (around line 482). The current code has a one-line comment on line 481: `// Driver — morph spring. Carries completion into Phase 4.` We're replacing that with a richer comment.

- [ ] **Step 2: Replace the comment**

In `RootView.swift` find:

```swift
        // Driver — morph spring. Carries completion into Phase 4.
        withAnimation(.bouncy(duration: 0.5, extraBounce: 0.15),
                      completionCriteria: .logicallyComplete) {
```

Replace with:

```swift
        // DRIVER: shortest of this phase's three withAnimations. Title spring
        // (~0.8s) intentionally overlaps into Phase 4's label fade; this makes
        // the sequence feel tighter. Do not swap drivers without updating this
        // comment. Chains completion into Phase 4.
        withAnimation(.bouncy(duration: 0.5, extraBounce: 0.15),
                      completionCriteria: .logicallyComplete) {
```

- [ ] **Step 3: Build**

```bash
cd ios/Astral && xcodebuild -scheme Astral \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' \
  build 2>&1 | grep -E "BUILD|error:" | tail -3
```

Expected: `** BUILD SUCCEEDED **`. (Comment-only change — should not break anything.)

- [ ] **Step 4: Commit**

```bash
git add ios/Astral/App/RootView.swift
git commit -m "[ios] AST-27 document Phase 3 spring driver in MorphLandingView"
```

---

### Task 3: AST-27 sub-item 4 — `onDisappear` token-rotation comment

**Files:**
- Modify: `ios/Astral/App/RootView.swift`

- [ ] **Step 1: Locate the onDisappear block**

`RootView.swift:210-212` currently:

```swift
        .onDisappear {
            animationToken = UUID()
        }
```

- [ ] **Step 2: Replace with documented version**

```swift
        .onDisappear {
            // Rotate token so any in-flight completion closures from the
            // previous animation chain bail out. withAnimation writes are
            // already committed; this only guards runPhaseN() chain re-entry.
            animationToken = UUID()
        }
```

- [ ] **Step 3: Build**

```bash
cd ios/Astral && xcodebuild -scheme Astral \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' \
  build 2>&1 | grep -E "BUILD|error:" | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add ios/Astral/App/RootView.swift
git commit -m "[ios] AST-27 document animation token rotation in MorphLandingView.onDisappear"
```

---

### Task 4: AST-34 tweak 1 — Shrink chapter title font multiplier

**Files:**
- Modify: `ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift`

- [ ] **Step 1: Locate the chapter title Text**

`FanficReaderView.swift:88` currently:

```swift
                                            Text(title)
                                                .font(fontFamily.boldFont(size: fontSize * 1.4))
                                                .foregroundStyle(textColor)
```

- [ ] **Step 2: Change the multiplier**

Replace `1.4` with `1.2`:

```swift
                                            Text(title)
                                                .font(fontFamily.boldFont(size: fontSize * 1.2))
                                                .foregroundStyle(textColor)
```

- [ ] **Step 3: Build**

```bash
cd ios/Astral && xcodebuild -scheme Astral \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' \
  build 2>&1 | grep -E "BUILD|error:" | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift
git commit -m "[ios] AST-34 shrink fanfic reader chapter title from 1.4x to 1.2x fontSize"
```

---

### Task 5: AST-34 tweak 2 — Remove reading-time HStack + dead helper

**Files:**
- Modify: `ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift`

`readingTimeLabel` is consumed only by the HStack we're removing (verified: `grep -n "readingTimeLabel" FanficReaderView.swift` returns 2 hits — the consumer at line 96 and the definition at line 344). Safe to delete the helper too.

- [ ] **Step 1: Remove the HStack consumer**

`FanficReaderView.swift:92-99` currently:

```swift
                                        // Reading time estimate
                                        HStack(spacing: 6) {
                                            Image(systemName: "clock")
                                                .font(.system(size: fontSize * 0.65))
                                            Text(readingTimeLabel)
                                                .font(fontFamily.font(size: fontSize * 0.75))
                                        }
                                        .foregroundStyle(AstralColors.muted.opacity(0.8))
```

Delete those 8 lines entirely (including the `// Reading time estimate` comment).

- [ ] **Step 2: Remove the now-orphan computed property**

`FanficReaderView.swift:344-351` currently:

```swift
    private var readingTimeLabel: String {
        let wordCount = chapterContent.split(separator: " ").count
        let minutes = max(1, wordCount / 238)
        let wordStr = wordCount > 1000
            ? String(format: "%.1fk words", Double(wordCount) / 1000.0)
            : "\(wordCount) words"
        return "\(wordStr) · \(minutes) min read"
    }
```

Delete those 8 lines entirely (plus the surrounding blank line if it leaves a double blank).

- [ ] **Step 3: Build**

```bash
cd ios/Astral && xcodebuild -scheme Astral \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' \
  build 2>&1 | grep -E "BUILD|error:" | tail -5
```

Expected: `** BUILD SUCCEEDED **`. If you get a "cannot find 'readingTimeLabel'" error, you missed a consumer — re-grep:

```bash
grep -n "readingTimeLabel" ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift
```

Expected output: nothing (zero hits).

- [ ] **Step 4: Commit**

```bash
git add ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift
git commit -m "[ios] AST-34 remove reading-time block from in-flow chapter header"
```

---

### Task 6: AST-34 tweak 3 — Tighten chapter header + outer ScrollView spacings

**Files:**
- Modify: `ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift`

Three numeric edits in the same file. Line numbers below reference the state AFTER Task 5 (the reading-time HStack and helper are already gone, which shifts line numbers slightly).

- [ ] **Step 1: Tighten the header VStack spacing**

Find:

```swift
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Chapter \(currentChapter.chapterNumber, specifier: "%.0f")")
```

Replace `spacing: 6` with `spacing: 4`:

```swift
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Chapter \(currentChapter.chapterNumber, specifier: "%.0f")")
```

- [ ] **Step 2: Tighten the header bottom padding**

Find the `.padding(.bottom, 8)` that closes the chapter-header VStack (just above the divider HStack):

```swift
                                    }
                                    .padding(.bottom, 8)

                                    // Divider between header and content
```

Replace `.padding(.bottom, 8)` with `.padding(.bottom, 4)`:

```swift
                                    }
                                    .padding(.bottom, 4)

                                    // Divider between header and content
```

- [ ] **Step 3: Halve the outer ScrollView vertical padding**

Find the `.padding(.vertical, 20)` applied to the outer scrollable content (currently around line 151 pre-Task-5; about line 143 post-Task-5):

```swift
                                .padding(.horizontal, horizontalMargin)
                                .padding(.vertical, 20)
                                .animation(AstralAnimation.quick, value: fontSize)
```

Replace `.padding(.vertical, 20)` with `.padding(.vertical, 10)`:

```swift
                                .padding(.horizontal, horizontalMargin)
                                .padding(.vertical, 10)
                                .animation(AstralAnimation.quick, value: fontSize)
```

- [ ] **Step 4: Build**

```bash
cd ios/Astral && xcodebuild -scheme Astral \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' \
  build 2>&1 | grep -E "BUILD|error:" | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Smoke-test all three reader backgrounds**

Launch the app on the simulator. Open any fanfic with at least one chapter. Verify each background:

1. Tap the reader settings → background = **dark** → chapter header shows: chapter number (uppercase, tracking, muted), title (smaller now), divider (line + diamond + line). First paragraph visible higher on screen than before.
2. Switch background = **sepia** → divider line still visible against sepia background.
3. Switch background = **paper** → divider line still visible against paper background.

If divider opacity needs adjustment for any background, the existing `AstralColors.muted.opacity(0.3)` is the place — but don't tune unless one is genuinely unreadable. The acceptance criterion is "still clearly readable", not "high contrast".

- [ ] **Step 6: Commit**

```bash
git add ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift
git commit -m "[ios] AST-34 tighten chapter header and outer ScrollView spacings"
```

---

### Task 7: Final verification + open PR

- [ ] **Step 1: Full build one more time**

```bash
cd ios/Astral && xcodebuild -scheme Astral \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' \
  build 2>&1 | grep -E "BUILD|error:" | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 2: Confirm commit log**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp"
git log --oneline development..HEAD
```

Expected: 7 commits — the spec doc + 6 implementation commits in this order:

```
<sha> [ios] AST-34 tighten chapter header and outer ScrollView spacings
<sha> [ios] AST-34 remove reading-time block from in-flow chapter header
<sha> [ios] AST-34 shrink fanfic reader chapter title from 1.4x to 1.2x fontSize
<sha> [ios] AST-27 document animation token rotation in MorphLandingView.onDisappear
<sha> [ios] AST-27 document Phase 3 spring driver in MorphLandingView
<sha> [ios] AST-27 extract MorphLandingView phase-geometry constants
<sha> [docs] AST-27 AST-34 add iOS cleanup design spec
```

- [ ] **Step 3: Use the finishing-a-development-branch skill**

Invoke `superpowers:finishing-a-development-branch` to:
- Re-verify build (already done — should pass instantly)
- Present the four end-of-branch options
- On chosen path "push and create PR": push branch + open PR with the body below

PR body template (use exactly this so Linear auto-closes both tickets on merge):

```markdown
Closes AST-27
Closes AST-34

## Summary
- **AST-27 (sub-items 2/3/4)** — `MorphLandingView` cleanup: extracted phase-geometry magic numbers from `runPhase1`/`runPhase2` into a file-private `PhaseGeometry` enum (4 Phase 1 fractions + 2 Phase 2 fractions). Added doc comments on the Phase 3 spring driver and the `onDisappear` animation-token rotation. Sub-item #1 (move `blueColor` to DesignSystem) was already done by AST-21 (PR #27, merged).
- **AST-34 (tweaks 1/2/3)** — Fanfic reader chapter header compaction: title font multiplier `1.4×` → `1.2×`; removed the reading-time HStack (and its dead `readingTimeLabel` computed property) from the in-flow header; tightened header VStack spacing `6→4`, header bottom padding `8→4`, outer ScrollView vertical padding `20→10`. First paragraph sits higher; design language preserved.

## Spec correction noted in plan
Phase 1 fractions are asymmetric (gold `0.45/0.5`, blue `0.4/0.45`) — the original AST-27 ticket assumed a single H/V pair. Plan uses 4 distinct constants. `finalOffsetX/Y` from the ticket already exist in `LandingTerminalState` (file lines 25-26) — not duplicated.

## Test plan
- [x] iOS build passes (`xcodebuild -scheme Astral -sdk iphonesimulator … build`)
- [ ] Landing animation visually unchanged (orbs drift through 4 phases — no jank, same final positions)
- [ ] Fanfic reader chapter header: first paragraph visible higher on iPhone 15/16 simulator than before
- [ ] Chapter number, title, divider still clearly readable in dark / sepia / paper backgrounds
- [ ] Font-size slider scales the header proportionally (no hardcoded points)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

---

## Acceptance criteria (from spec)

**AST-27:**
- [ ] No bare phase-geometry magic numbers in `runPhaseN` bodies (everything goes through `PhaseGeometry.*`) — Task 1.
- [ ] Phase 3 driver doc comment present at the morph-spring `withAnimation` — Task 2.
- [ ] `onDisappear` token-rotation lifecycle doc comment present — Task 3.
- [ ] Build passes; landing animation visually unchanged — Tasks 1 + 7.

**AST-34:**
- [ ] First paragraph visible further up the screen on iPhone 15/16 simulator without scrolling — Tasks 4-6.
- [ ] Chapter number, title, divider remain clearly readable; design language preserved — Task 6 smoke test.
- [ ] Reading-time block gone from the in-flow header (no replacement surface) — Task 5.
- [ ] All three reader backgrounds (dark / sepia / paper) verified — Task 6 smoke test.
- [ ] Font-size slider still scales the header proportionally — implicit (`fontSize * 1.2` still scales).

**Both:**
- [ ] iOS build passes — Task 7.
- [ ] PR body includes `Closes AST-27` and `Closes AST-34` on separate lines — Task 7.
