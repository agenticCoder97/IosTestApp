# Landing Animation Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite the Astral landing animation to fix orb overlap, remove DispatchQueue sequencing, honor `accessibilityReduceMotion`, and add five polish touches — all in one bundled refactor.

**Architecture:** Single-file change to `ios/Astral/App/RootView.swift`. `MorphLandingView` keeps its shape and final visuals; `runAnimation()` is rewritten to use `withAnimation(...) completion:` chaining (iOS 17+) instead of `DispatchQueue.main.asyncAfter`. A cancellation token guards late completions. A local `PhaseAnimator` inside each orb view drives Phase 2 wobble without touching the phase-chain parent.

**Tech Stack:** SwiftUI (iOS 17.2+), Swift 6, Xcode project via XcodeGen, DesignSystem package (`PressButtonStyle`, `AstralAnimation`).

**Reference spec:** [docs/superpowers/specs/2026-04-17-landing-animation-redesign-design.md](../specs/2026-04-17-landing-animation-redesign-design.md)

**Linear:** parent [AST-1](https://linear.app/nnetraganti/issue/AST-1); closes [AST-2](https://linear.app/nnetraganti/issue/AST-2), [AST-3](https://linear.app/nnetraganti/issue/AST-3), [AST-4](https://linear.app/nnetraganti/issue/AST-4), [AST-5](https://linear.app/nnetraganti/issue/AST-5).

**Branch:** `feature/ast-1-landing-animation-redesign` (branched from `development`).

---

## Testing Approach

This is a visual animation refactor. There is no unit-test harness for `RootView.swift` and the behavior being changed is not pure logic — it's motion + layout observed on screen. **Classic TDD does not apply.** Each task instead has:

1. A concrete code change.
2. A build check: `cd ios/Astral && xcodebuild -scheme Astral -sdk iphonesimulator -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build`
3. A simulator run with explicit pass/fail criteria (what you should see).
4. A commit.

The existing `--uitesting` launch arg sets `showLanding = false`, so automated UI tests bypass the landing view and are unaffected by these changes.

---

## Task 0: Branch Setup

**Files:** none (git operation only)

- [ ] **Step 1: Confirm you are on `development` and clean**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp"
git status
git branch --show-current
```

Expected: current branch is `development`. If there are unstaged changes unrelated to this work (`CLAUDE.md`, `project.pbxproj`, etc.), leave them — you will not stage them. If you are on another branch, `git checkout development` first.

- [ ] **Step 2: Create the feature branch**

```bash
git checkout -b feature/ast-1-landing-animation-redesign
```

- [ ] **Step 3: Verify build from a clean slate**

```bash
cd ios/Astral && xcodebuild -scheme Astral -sdk iphonesimulator -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`. If it fails for a reason unrelated to this plan (e.g. simulator ID missing), swap the destination for any available iOS 17.2+ simulator: `xcrun simctl list devices available | grep iPhone`.

No commit for this task.

---

## Task 1: Add New State & Environment — Scaffolding Only

**Files:**
- Modify: `ios/Astral/App/RootView.swift`

Add the new `@State` vars and `@Environment` the spec requires. Split `contentReveal` into `contentRevealGold` / `contentRevealBlue`. **No behavioral change yet** — both new vars animate identically for now.

- [ ] **Step 1: Add `accessibilityReduceMotion` environment and new state**

In `RootView.swift`, inside `private struct MorphLandingView`, just after `let onSelect: (AppTab) -> Void` (line 44), add:

```swift
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
```

Then replace the block declaring `contentReveal` and `contentSlide` (currently lines 70–72):

```swift
    // Content inside orbs
    @State private var contentReveal: Double = 0
    @State private var contentSlide: CGFloat = 20 // internal content slides up
```

with:

```swift
    // Content inside orbs
    @State private var contentRevealGold: Double = 0
    @State private var contentRevealBlue: Double = 0
    @State private var contentSlide: CGFloat = 20 // internal content slides up
```

Just below the title/labels block (after `@State private var labelOpacity: Double = 0`, currently line 78), add:

```swift
    @State private var titleBlur: CGFloat = 8

    // Cancellation guard for phase completion chain
    @State private var animationToken = UUID()
```

- [ ] **Step 2: Update `goldOrb` to use `contentRevealGold`**

In `goldOrb` (the `VStack` block starting at line 191), find:

```swift
            .offset(y: contentSlide)
            .opacity(contentReveal)
            .clipShape(RoundedRectangle(cornerRadius: goldCornerRadius))
```

Change `.opacity(contentReveal)` to `.opacity(contentRevealGold)`.

- [ ] **Step 3: Update `blueOrb` to use `contentRevealBlue`**

In `blueOrb` (the `VStack` block starting at line 243), find:

```swift
            .offset(y: contentSlide)
            .opacity(contentReveal)
            .clipShape(RoundedRectangle(cornerRadius: blueCornerRadius))
```

Change `.opacity(contentReveal)` to `.opacity(contentRevealBlue)`.

- [ ] **Step 4: Update `runAnimation()` content-reveal write to use both new vars**

In `runAnimation()`, find the Phase 2 content reveal block (currently around line 334):

```swift
            // Content fades in and slides up
            withAnimation(.easeOut(duration: 1.0).delay(0.3)) {
                contentReveal = 0.85
                contentSlide = 0
            }
```

Replace the body of the `withAnimation` block so both new vars get 0.85:

```swift
            // Content fades in and slides up
            withAnimation(.easeOut(duration: 1.0).delay(0.3)) {
                contentRevealGold = 0.85
                contentRevealBlue = 0.85
                contentSlide = 0
            }
```

Then find the Phase 3 content dissolve block (currently around line 358):

```swift
            // Content dissolves
            withAnimation(.easeIn(duration: 0.4)) {
                contentReveal = 1.0 // icon stays, decorative lines will be clipped
                contentSlide = -5
            }
```

Replace the body so both new vars get 1.0:

```swift
            // Content dissolves
            withAnimation(.easeIn(duration: 0.4)) {
                contentRevealGold = 1.0 // icon stays, decorative lines will be clipped
                contentRevealBlue = 1.0
                contentSlide = -5
            }
```

- [ ] **Step 5: Attach title blur modifier (still animated to 0 later, but already declared)**

In the title `VStack` (starting at line 105), find `Text("Astral")` and its modifiers:

```swift
                Text("Astral")
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .foregroundStyle(AstralColors.white)
                    .scaleEffect(titleScale)
                    .opacity(titleOpacity)
```

Add `.blur(radius: titleBlur)` between `.foregroundStyle(...)` and `.scaleEffect(...)`:

```swift
                Text("Astral")
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .foregroundStyle(AstralColors.white)
                    .blur(radius: titleBlur)
                    .scaleEffect(titleScale)
                    .opacity(titleOpacity)
```

The title starts with `titleBlur = 8` AND `titleOpacity = 0`, so the blur is invisible until opacity rises — a later task animates blur to 0.

- [ ] **Step 6: Add `onDisappear` token refresh**

At the bottom of the `GeometryReader`'s `ZStack` (currently right after the `onAppear { ... }` block, around line 166), add:

```swift
        .onDisappear {
            animationToken = UUID()
        }
```

Final structure should look like:

```swift
        .onAppear {
            screenSize = geo.size
            // Start orbs at absolute screen corners
            goldOffset = CGSize(width: -(geo.size.width / 2 - 20), height: -(geo.size.height / 3))
            blueOffset = CGSize(width: geo.size.width / 2 - 20, height: geo.size.height / 3)
            runAnimation()
        }
        .onDisappear {
            animationToken = UUID()
        }
        } // GeometryReader
    }
```

- [ ] **Step 7: Build**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral" && xcodebuild -scheme Astral -sdk iphonesimulator -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Simulator smoke check (no behavior change yet)**

Open `ios/Astral/Astral.xcodeproj`, run on an iOS 17.2+ simulator. Launch app. The animation should play **exactly as before** (still uses DispatchQueue — not fixed yet). No new visuals, no regressions.

Pass criteria: animation sequence completes, orbs reach final resting position, labels/subtitle appear, taps work.

- [ ] **Step 9: Commit**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp"
git add ios/Astral/App/RootView.swift
git commit -m "[ios] AST-1 add reduce-motion env + split content-reveal state

Scaffolding for landing animation redesign. No behavioral change —
contentRevealGold/Blue animate together for now. titleBlur attached
but still animated by later phase blocks.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Split `runAnimation()` Into Phase Functions (Pure Refactor)

**Files:**
- Modify: `ios/Astral/App/RootView.swift`

Extract each phase into its own method. Still uses `DispatchQueue.main.asyncAfter` for now — this task is a mechanical refactor to make Task 3 simpler to review.

- [ ] **Step 1: Replace the `runAnimation()` body**

Replace the entire `private func runAnimation() { ... }` (currently lines 269–404) with:

```swift
    // MARK: - Animation Sequence

    private func runAnimation() {
        // Ambient background — continuous slow drift
        withAnimation(.easeInOut(duration: 5.0).repeatForever(autoreverses: true)) {
            ambientShift = true
        }

        runPhase1()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { runPhase2() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { runPhase2MidDrift() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { runPhase3() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.8) { runPhase4() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.2) { phase = 4 }
    }

    // PHASE 1: Blob Appear (0.3s–1.0s) — tiny shapes pop in far from center
    private func runPhase1() {
        let halfW = screenSize.width / 2
        let halfH = screenSize.height / 3

        withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
            goldOpacity = 1
            goldSize = 30
            goldBlobSkew = 1.3
            goldGlow = 0.5
        }

        withAnimation(.easeOut(duration: 0.5).delay(0.5)) {
            blueOpacity = 1
            blueSize = 24
            blueBlobSkew = 0.8
            blueGlow = 0.5
        }

        withAnimation(.easeInOut(duration: 1.2).delay(0.5)) {
            goldOffset = CGSize(width: -(halfW * 0.45), height: -(halfH * 0.5))
            blueOffset = CGSize(width: halfW * 0.4, height: halfH * 0.45)
            goldRotation = -18
            blueRotation = 12
        }
    }

    // PHASE 2: Expand + Drift (1.0s–2.8s) — orbs grow, content fades in
    private func runPhase2() {
        let halfW = screenSize.width / 2
        let halfH = screenSize.height / 3
        phase = 2

        withAnimation(.spring(response: 0.9, dampingFraction: 0.7)) {
            goldSize = 140
            blueSize = 135
            goldBlobSkew = 1.0
            blueBlobSkew = 1.0
            goldGlow = 0.7
            blueGlow = 0.7
        }

        withAnimation(.easeInOut(duration: 1.5)) {
            goldOffset = CGSize(width: -(halfW * 0.3), height: -(halfH * 0.2))
            blueOffset = CGSize(width: halfW * 0.25, height: halfH * 0.2)
            goldRotation = -8
            blueRotation = 6
        }

        withAnimation(.easeOut(duration: 1.0).delay(0.3)) {
            contentRevealGold = 0.85
            contentRevealBlue = 0.85
            contentSlide = 0
        }
    }

    // Mid-drift — floating motion, pulling gradually closer (TO BE REMOVED in Task 4)
    private func runPhase2MidDrift() {
        let halfW = screenSize.width / 2
        let halfH = screenSize.height / 3

        withAnimation(.easeInOut(duration: 1.0)) {
            goldOffset = CGSize(width: -(halfW * 0.2), height: -(halfH * 0.1))
            blueOffset = CGSize(width: halfW * 0.15, height: halfH * 0.12)
            goldRotation = -4
            blueRotation = 3
        }
    }

    // PHASE 3: Contract + Morph (2.8s–3.8s) — pull inward, shape morphs
    private func runPhase3() {
        phase = 3

        withAnimation(.easeIn(duration: 0.4)) {
            contentRevealGold = 1.0
            contentRevealBlue = 1.0
            contentSlide = -5
        }

        withAnimation(.spring(response: 0.55, dampingFraction: 0.55, blendDuration: 0.3)) {
            goldSize = 120
            blueSize = 120
            goldCornerRadius = 28
            blueCornerRadius = 28
            goldOffset = CGSize(width: -80, height: 30)
            blueOffset = CGSize(width: 80, height: 30)
            goldRotation = 0
            blueRotation = 0
            goldGlow = 0.3
            blueGlow = 0.3
        }

        withAnimation(.spring(response: 0.6, dampingFraction: 0.65).delay(0.2)) {
            titleScale = 1.0
            titleOpacity = 1
        }
    }

    // PHASE 4: Ready (3.8s–4.5s) — labels appear, buttons tappable
    private func runPhase4() {
        withAnimation(.easeOut(duration: 0.5)) {
            subtitleOpacity = 1
        }
        withAnimation(.easeOut(duration: 0.4).delay(0.15)) {
            labelOpacity = 1
        }
    }
}
```

Note: the closing `}` above is the `MorphLandingView` struct close — keep one blank line before `#Preview`.

- [ ] **Step 2: Build**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral" && xcodebuild -scheme Astral -sdk iphonesimulator -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Simulator smoke check**

Run in simulator. Animation should still play identically to before. This is a pure mechanical refactor.

Pass criteria: no visible change from Task 1.

- [ ] **Step 4: Commit**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp"
git add ios/Astral/App/RootView.swift
git commit -m "[ios] AST-1 extract runAnimation phases into per-phase functions

Pure refactor — still uses DispatchQueue.main.asyncAfter. Sets up
Task 3 to swap sequencing for withAnimation completion chaining
without a massive diff.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Replace DispatchQueue With Completion Chaining (AST-3)

**Files:**
- Modify: `ios/Astral/App/RootView.swift`

Remove all `DispatchQueue.main.asyncAfter` calls. Drive phase transitions via `withAnimation(_:_:completionCriteria:completion:)`. The "driver" of each phase is the longest-running `withAnimation` and carries the completion handler.

- [ ] **Step 1: Rewrite `runAnimation()` to chain via completion handlers**

Replace the `runAnimation()` method (the one written in Task 2) with:

```swift
    private func runAnimation() {
        // Ambient background — continuous slow drift
        withAnimation(.easeInOut(duration: 5.0).repeatForever(autoreverses: true)) {
            ambientShift = true
        }

        runPhase1()
    }
```

- [ ] **Step 2: Update `runPhase1()` to chain Phase 2 via completion**

Replace `runPhase1()` with:

```swift
    private func runPhase1() {
        let halfW = screenSize.width / 2
        let halfH = screenSize.height / 3
        let token = animationToken

        withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
            goldOpacity = 1
            goldSize = 30
            goldBlobSkew = 1.3
            goldGlow = 0.5
        }

        withAnimation(.easeOut(duration: 0.5).delay(0.5)) {
            blueOpacity = 1
            blueSize = 24
            blueBlobSkew = 0.8
            blueGlow = 0.5
        }

        // Driver — longest (0.5 + 1.2 = 1.7s). Carries completion.
        withAnimation(.easeInOut(duration: 1.2).delay(0.5),
                      completionCriteria: .logicallyComplete) {
            goldOffset = CGSize(width: -(halfW * 0.45), height: -(halfH * 0.5))
            blueOffset = CGSize(width: halfW * 0.4, height: halfH * 0.45)
            goldRotation = -18
            blueRotation = 12
        } completion: {
            guard token == animationToken else { return }
            runPhase2()
        }
    }
```

- [ ] **Step 3: Update `runPhase2()` to chain Phase 2 mid-drift (kept for now) via completion**

Replace `runPhase2()` and `runPhase2MidDrift()` with:

```swift
    private func runPhase2() {
        let halfW = screenSize.width / 2
        let halfH = screenSize.height / 3
        let token = animationToken
        phase = 2

        withAnimation(.spring(response: 0.9, dampingFraction: 0.7)) {
            goldSize = 140
            blueSize = 135
            goldBlobSkew = 1.0
            blueBlobSkew = 1.0
            goldGlow = 0.7
            blueGlow = 0.7
        }

        withAnimation(.easeOut(duration: 1.0).delay(0.3)) {
            contentRevealGold = 0.85
            contentRevealBlue = 0.85
            contentSlide = 0
        }

        // Driver — longest positional drift (1.5s). Chains into mid-drift.
        withAnimation(.easeInOut(duration: 1.5),
                      completionCriteria: .logicallyComplete) {
            goldOffset = CGSize(width: -(halfW * 0.3), height: -(halfH * 0.2))
            blueOffset = CGSize(width: halfW * 0.25, height: halfH * 0.2)
            goldRotation = -8
            blueRotation = 6
        } completion: {
            guard token == animationToken else { return }
            runPhase2MidDrift()
        }
    }

    private func runPhase2MidDrift() {
        let halfW = screenSize.width / 2
        let halfH = screenSize.height / 3
        let token = animationToken

        // Driver — 1.0s. Chains into Phase 3.
        withAnimation(.easeInOut(duration: 1.0),
                      completionCriteria: .logicallyComplete) {
            goldOffset = CGSize(width: -(halfW * 0.2), height: -(halfH * 0.1))
            blueOffset = CGSize(width: halfW * 0.15, height: halfH * 0.12)
            goldRotation = -4
            blueRotation = 3
        } completion: {
            guard token == animationToken else { return }
            runPhase3()
        }
    }
```

- [ ] **Step 4: Update `runPhase3()` to chain Phase 4 via completion**

Replace `runPhase3()` with:

```swift
    private func runPhase3() {
        let token = animationToken
        phase = 3

        withAnimation(.easeIn(duration: 0.4)) {
            contentRevealGold = 1.0
            contentRevealBlue = 1.0
            contentSlide = -5
        }

        withAnimation(.spring(response: 0.6, dampingFraction: 0.65).delay(0.2)) {
            titleScale = 1.0
            titleOpacity = 1
        }

        // Driver — morph spring. Carries completion into Phase 4.
        withAnimation(.spring(response: 0.55, dampingFraction: 0.55, blendDuration: 0.3),
                      completionCriteria: .logicallyComplete) {
            goldSize = 120
            blueSize = 120
            goldCornerRadius = 28
            blueCornerRadius = 28
            goldOffset = CGSize(width: -80, height: 30)
            blueOffset = CGSize(width: 80, height: 30)
            goldRotation = 0
            blueRotation = 0
            goldGlow = 0.3
            blueGlow = 0.3
        } completion: {
            guard token == animationToken else { return }
            runPhase4()
        }
    }
```

- [ ] **Step 5: Update `runPhase4()` to finalize `phase = 4`**

Replace `runPhase4()` with:

```swift
    private func runPhase4() {
        let token = animationToken

        withAnimation(.easeOut(duration: 0.5)) {
            subtitleOpacity = 1
        }

        // Driver — labels are last. Flips phase to 4 when done.
        withAnimation(.easeOut(duration: 0.4).delay(0.15),
                      completionCriteria: .logicallyComplete) {
            labelOpacity = 1
        } completion: {
            guard token == animationToken else { return }
            phase = 4
        }
    }
```

- [ ] **Step 6: Verify NO `DispatchQueue` remains in `RootView.swift`**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp"
grep -n DispatchQueue ios/Astral/App/RootView.swift
```

Expected: no output (grep returns nothing). If any remain, remove them.

- [ ] **Step 7: Build**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral" && xcodebuild -scheme Astral -sdk iphonesimulator -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Simulator check**

Run. Because completion chaining triggers the next phase as soon as the driver's animation logically completes (slightly different from the hardcoded 1.0s / 1.8s / 2.8s / 3.8s timestamps), phases may flow slightly faster or slower — the **ordering** is what matters.

Pass criteria:
- Full sequence plays from blank → orbs appear → expand → morph → labels.
- `phase = 4` is reached and taps become active (tap either zone, app switches to Comic or Fanfic tab).
- No hangs, no frozen orbs.
- Orb overlap still exists (Task 4 fixes that).

- [ ] **Step 9: Commit**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp"
git add ios/Astral/App/RootView.swift
git commit -m "[ios] AST-3 replace DispatchQueue with withAnimation completion chain

Each phase's driver animation carries completionCriteria:.logicallyComplete
and triggers the next runPhase* function. animationToken guards against
completions firing after the view disappears.

Closes AST-3.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Fix Phase 2 Overlap — Delete Mid-Drift & Widen Positions (AST-2)

**Files:**
- Modify: `ios/Astral/App/RootView.swift`

Remove `runPhase2MidDrift()` entirely. Widen Phase 2 positions to `±halfW * 0.38`. Phase 2 now chains directly to Phase 3 on driver completion.

- [ ] **Step 1: Delete `runPhase2MidDrift()`**

Delete the entire `runPhase2MidDrift()` method written in Task 3 (the whole function).

- [ ] **Step 2: Rewrite `runPhase2()` with wider positions and direct chain to Phase 3**

Replace `runPhase2()` with:

```swift
    private func runPhase2() {
        let halfW = screenSize.width / 2
        let halfH = screenSize.height / 3
        let token = animationToken
        phase = 2

        withAnimation(.spring(response: 0.9, dampingFraction: 0.7)) {
            goldSize = 140
            blueSize = 135
            goldBlobSkew = 1.0
            blueBlobSkew = 1.0
            goldGlow = 0.7
            blueGlow = 0.7
        }

        withAnimation(.easeOut(duration: 1.0).delay(0.3)) {
            contentRevealGold = 0.85
            contentRevealBlue = 0.85
            contentSlide = 0
        }

        // Positions kept wider — centers ≥148pt apart on a 390pt screen,
        // clearing 140pt orbs. Replaces the old two-step drift that
        // pulled orbs to ~68pt center distance (AST-2).
        // Driver — longest (1.5s). Chains into Phase 3.
        withAnimation(.easeInOut(duration: 1.5),
                      completionCriteria: .logicallyComplete) {
            goldOffset = CGSize(width: -(halfW * 0.38), height: -(halfH * 0.2))
            blueOffset = CGSize(width: halfW * 0.38, height: halfH * 0.2)
            goldRotation = -8
            blueRotation = 6
        } completion: {
            guard token == animationToken else { return }
            runPhase3()
        }
    }
```

- [ ] **Step 3: Build**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral" && xcodebuild -scheme Astral -sdk iphonesimulator -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Simulator check — verify no orb overlap**

Run on at least two simulator sizes:
- iPhone 15 (393pt wide)
- iPhone SE 3rd gen (375pt wide) — narrowest supported

Watch the animation through Phase 2. Orbs should grow to ~140pt but never visually touch. Slowdown is available via Xcode → Debug → Simulator → Slow Animations (⌘T) to confirm by eye.

Pass criteria:
- No visible orb collision at any point in Phases 1, 2, or 3.
- Phase 3 still lands at `(-80, 30)` / `(80, 30)` with 160pt center separation.
- If orbs visibly clip on iPhone SE, stop and report. Fallback (not applied yet): cap `goldSize`/`blueSize` at 130pt in Phase 2.

- [ ] **Step 5: Commit**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp"
git add ios/Astral/App/RootView.swift
git commit -m "[ios] AST-2 fix Phase 2 orb overlap

Delete the 1.8s mid-drift block that pulled 140pt orbs to 68pt
center distance (72pt visual overlap). Widen Phase 2 positions
to ±halfW * 0.38 so centers stay ≥148pt apart on a 390pt screen.
Phase 2 now chains directly to Phase 3.

Closes AST-2.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Reduce Motion Support (AST-4)

**Files:**
- Modify: `ios/Astral/App/RootView.swift`

Guard `runAnimation()` with a reduce-motion branch that snaps to the final state and cross-fades opacity.

- [ ] **Step 1: Update `runAnimation()` to guard on `reduceMotion`**

Replace `runAnimation()` with:

```swift
    private func runAnimation() {
        if reduceMotion {
            applyReducedMotionState()
            return
        }

        // Ambient background — continuous slow drift
        withAnimation(.easeInOut(duration: 5.0).repeatForever(autoreverses: true)) {
            ambientShift = true
        }

        runPhase1()
    }

    private func applyReducedMotionState() {
        // Snap all state vars to Phase 4 final values (no motion).
        goldSize = 120
        blueSize = 120
        goldOffset = CGSize(width: -80, height: 30)
        blueOffset = CGSize(width: 80, height: 30)
        goldRotation = 0
        blueRotation = 0
        goldBlobSkew = 1.0
        blueBlobSkew = 1.0
        goldCornerRadius = 28
        blueCornerRadius = 28
        goldGlow = 0.3
        blueGlow = 0.3
        contentRevealGold = 1.0
        contentRevealBlue = 1.0
        contentSlide = -5
        titleScale = 1.0
        titleBlur = 0

        // Single cross-fade for opacity values — no positional motion, no ambient drift.
        withAnimation(.easeOut(duration: 0.3)) {
            goldOpacity = 1
            blueOpacity = 1
            titleOpacity = 1
            subtitleOpacity = 1
            labelOpacity = 1
        }
        phase = 4
    }
```

- [ ] **Step 2: Build**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral" && xcodebuild -scheme Astral -sdk iphonesimulator -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Simulator check — Reduce Motion ON**

In simulator: Settings → Accessibility → Motion → Reduce Motion → ON.

Force-quit and relaunch Astral. The landing screen should:
- Show orbs already at final positions (bottom pair, `±80, 30`).
- Cross-fade all opacity over ~0.3s.
- Title "Astral" visible at full scale with no blur.
- Taps active immediately (no 4.2s wait).
- No ambient background drift.

- [ ] **Step 4: Simulator check — Reduce Motion OFF**

Turn Reduce Motion OFF and relaunch. Full animation sequence should play as in Task 4.

Pass criteria: both modes work; taps land in the correct tab.

- [ ] **Step 5: Commit**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp"
git add ios/Astral/App/RootView.swift
git commit -m "[ios] AST-4 honor accessibilityReduceMotion on landing

When Reduce Motion is on, snap orbs to final state and cross-fade
opacity over 0.3s. Skip ambient drift entirely.

Closes AST-4.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Stagger Content Reveal (AST-5 #1)

**Files:**
- Modify: `ios/Astral/App/RootView.swift`

Gold content reveals 0.15s before blue during Phase 2.

- [ ] **Step 1: Split the Phase 2 content-reveal `withAnimation` into two**

In `runPhase2()`, find the content-reveal block:

```swift
        withAnimation(.easeOut(duration: 1.0).delay(0.3)) {
            contentRevealGold = 0.85
            contentRevealBlue = 0.85
            contentSlide = 0
        }
```

Replace with two separate animations for the fades, and animate `contentSlide` with the gold one (so slide happens once, tied to first reveal):

```swift
        // Stagger: gold reveals first, blue 0.15s later.
        withAnimation(.easeOut(duration: 1.0).delay(0.3)) {
            contentRevealGold = 0.85
            contentSlide = 0
        }
        withAnimation(.easeOut(duration: 1.0).delay(0.45)) {
            contentRevealBlue = 0.85
        }
```

- [ ] **Step 2: Build**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral" && xcodebuild -scheme Astral -sdk iphonesimulator -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Simulator check**

Run with Reduce Motion OFF. Watch Phase 2 closely (Slow Animations helps). Gold orb's internal content (book icon + manga panels) should start fading in noticeably before the blue orb's content (scroll icon + text lines).

Pass criteria: visible offset between gold and blue content reveals.

- [ ] **Step 4: Commit**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp"
git add ios/Astral/App/RootView.swift
git commit -m "[ios] AST-5 stagger content reveal between orbs

Gold content fades in at delay 0.3s; blue follows at 0.45s. Adds
rhythm to what was a simultaneous cross-fade.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Bouncy Phase 3 Finale (AST-5 #3)

**Files:**
- Modify: `ios/Astral/App/RootView.swift`

Swap Phase 3 morph spring for `.bouncy(duration: 0.5, extraBounce: 0.15)`.

- [ ] **Step 1: Update the Phase 3 morph driver animation**

In `runPhase3()`, find the driver `withAnimation`:

```swift
        withAnimation(.spring(response: 0.55, dampingFraction: 0.55, blendDuration: 0.3),
                      completionCriteria: .logicallyComplete) {
```

Replace with:

```swift
        withAnimation(.bouncy(duration: 0.5, extraBounce: 0.15),
                      completionCriteria: .logicallyComplete) {
```

- [ ] **Step 2: Build**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral" && xcodebuild -scheme Astral -sdk iphonesimulator -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Simulator check**

Watch Phase 3 — when orbs contract and morph into rounded rectangles, they should "snap" into place with a satisfying bounce. Less random flop than the previous low-damping spring.

Pass criteria: settle motion feels intentional, not janky.

- [ ] **Step 4: Commit**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp"
git add ios/Astral/App/RootView.swift
git commit -m "[ios] AST-5 use .bouncy spring for Phase 3 morph finale"
```

---

## Task 8: Title Blur-In (AST-5 #4)

**Files:**
- Modify: `ios/Astral/App/RootView.swift`

Animate `titleBlur: 8 → 0` alongside the title scale/opacity in Phase 3.

- [ ] **Step 1: Update the Phase 3 title `withAnimation`**

In `runPhase3()`, find:

```swift
        withAnimation(.spring(response: 0.6, dampingFraction: 0.65).delay(0.2)) {
            titleScale = 1.0
            titleOpacity = 1
        }
```

Replace with:

```swift
        withAnimation(.spring(response: 0.6, dampingFraction: 0.65).delay(0.2)) {
            titleScale = 1.0
            titleOpacity = 1
            titleBlur = 0
        }
```

- [ ] **Step 2: Build**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral" && xcodebuild -scheme Astral -sdk iphonesimulator -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Simulator check**

Watch title appear at start of Phase 3. "Astral" should resolve from blurry to sharp as it scales up and fades in.

Pass criteria: title has a visible blur-to-sharp focus transition (not just a plain fade-in).

- [ ] **Step 4: Commit**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp"
git add ios/Astral/App/RootView.swift
git commit -m "[ios] AST-5 blur-in the 'Astral' title during Phase 3"
```

---

## Task 9: Press Feedback on Tap Zones (AST-5 #5)

**Files:**
- Modify: `ios/Astral/App/RootView.swift`

Swap `Color.clear.onTapGesture` for `Button` with `PressButtonStyle` (`.pressEffect()` from `DesignSystem`). Keep accessibility identifiers.

- [ ] **Step 1: Rewrite the tap-zone `HStack`**

In `body`, find the tap-zones block (currently):

```swift
            // Tap zones — only active in phase 4
            if phase >= 4 {
                HStack(spacing: 0) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(.comic) }
                        .accessibilityIdentifier(AccessibilityID.landingComicOrb)
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(.fanfic) }
                        .accessibilityIdentifier(AccessibilityID.landingFanficOrb)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
```

Replace with:

```swift
            // Tap zones — only active in phase 4
            if phase >= 4 {
                HStack(spacing: 0) {
                    Button {
                        onSelect(.comic)
                    } label: {
                        Color.clear
                            .contentShape(Rectangle())
                    }
                    .pressEffect()
                    .accessibilityIdentifier(AccessibilityID.landingComicOrb)

                    Button {
                        onSelect(.fanfic)
                    } label: {
                        Color.clear
                            .contentShape(Rectangle())
                    }
                    .pressEffect()
                    .accessibilityIdentifier(AccessibilityID.landingFanficOrb)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
```

Note: `.pressEffect()` is defined in the `DesignSystem` package (already imported at the top of `RootView.swift`).

- [ ] **Step 2: Build**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral" && xcodebuild -scheme Astral -sdk iphonesimulator -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Simulator check**

Let the animation complete to Phase 4. Tap-and-hold the left half (comic) — the entire left zone should scale down ~4% and fade slightly. Release — returns to full size, navigates to comic tab. Same for the right half (fanfic).

Pass criteria: both zones have the tactile press feedback; tap still dismisses landing into the correct tab.

- [ ] **Step 4: Commit**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp"
git add ios/Astral/App/RootView.swift
git commit -m "[ios] AST-5 add press feedback to landing tap zones

Replace Color.clear.onTapGesture with Button + .pressEffect() so
the tap zones scale + fade on press, matching interactive feel
elsewhere in the app.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 10: Phase 2 Wobble (AST-5 #2)

**Files:**
- Modify: `ios/Astral/App/RootView.swift`

Wrap the orb shape stacks in a local `PhaseAnimator` keyed on `phase == 2`. A single run cycles 0° → -5° → +5° → 0°. Blue is offset 0.15s from gold.

- [ ] **Step 1: Add a wobble helper enum at the file level**

At the top of `RootView.swift`, just below `import FanficFeature`, add:

```swift
// Three-beat wobble cycle used by orbs during Phase 2 expansion.
private enum WobbleBeat: CaseIterable {
    case rest, left, right, settle
    var angle: Double {
        switch self {
        case .rest: return 0
        case .left: return -5
        case .right: return 5
        case .settle: return 0
        }
    }
}
```

- [ ] **Step 2: Wrap `goldOrb` with PhaseAnimator**

Replace the `goldOrb` computed property with:

```swift
    private var goldOrb: some View {
        PhaseAnimator(WobbleBeat.allCases, trigger: phase == 2) { beat in
            goldOrbBody
                .rotationEffect(.degrees(beat.angle))
        } animation: { _ in
            .easeInOut(duration: 0.7)
        }
    }

    private var goldOrbBody: some View {
        ZStack {
            // Glow halo
            RoundedRectangle(cornerRadius: goldCornerRadius)
                .fill(goldColor.opacity(0.15))
                .frame(width: 130 * goldBlobSkew, height: 130)
                .blur(radius: 20)
                .opacity(goldGlow)

            // Main shape
            RoundedRectangle(cornerRadius: goldCornerRadius)
                .fill(goldColor.opacity(0.15))
                .frame(width: 130 * goldBlobSkew, height: 130)

            RoundedRectangle(cornerRadius: goldCornerRadius)
                .stroke(goldColor.opacity(0.35), lineWidth: 2)
                .frame(width: 130 * goldBlobSkew, height: 130)

            // Content inside — manga panel grid + book icon
            VStack(spacing: 5) {
                Image(systemName: "book.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(goldColor.opacity(0.8))

                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(goldColor.opacity(0.2))
                            .frame(width: 24, height: 12)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(goldColor.opacity(0.15))
                            .frame(width: 18, height: 12)
                    }
                    HStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(goldColor.opacity(0.15))
                            .frame(width: 14, height: 10)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(goldColor.opacity(0.2))
                            .frame(width: 28, height: 10)
                    }
                }
            }
            .offset(y: contentSlide)
            .opacity(contentRevealGold)
            .clipShape(RoundedRectangle(cornerRadius: goldCornerRadius))
        }
    }
```

- [ ] **Step 3: Wrap `blueOrb` with PhaseAnimator (with 0.15s delay)**

Replace the `blueOrb` computed property with:

```swift
    private var blueOrb: some View {
        PhaseAnimator(WobbleBeat.allCases, trigger: phase == 2) { beat in
            blueOrbBody
                .rotationEffect(.degrees(beat.angle))
        } animation: { _ in
            .easeInOut(duration: 0.7).delay(0.15)
        }
    }

    private var blueOrbBody: some View {
        ZStack {
            // Glow halo
            RoundedRectangle(cornerRadius: blueCornerRadius)
                .fill(blueColor.opacity(0.15))
                .frame(width: 130 * blueBlobSkew, height: 130)
                .blur(radius: 20)
                .opacity(blueGlow)

            // Main shape
            RoundedRectangle(cornerRadius: blueCornerRadius)
                .fill(blueColor.opacity(0.15))
                .frame(width: 130 * blueBlobSkew, height: 130)

            RoundedRectangle(cornerRadius: blueCornerRadius)
                .stroke(blueColor.opacity(0.35), lineWidth: 2)
                .frame(width: 130 * blueBlobSkew, height: 130)

            // Content inside — text lines + scroll icon
            VStack(spacing: 5) {
                Image(systemName: "scroll.fill")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(blueColor.opacity(0.8))

                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(blueColor.opacity(0.25))
                        .frame(width: 40, height: 3)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(blueColor.opacity(0.18))
                        .frame(width: 32, height: 3)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(blueColor.opacity(0.12))
                        .frame(width: 36, height: 3)
                }
            }
            .offset(y: contentSlide)
            .opacity(contentRevealBlue)
            .clipShape(RoundedRectangle(cornerRadius: blueCornerRadius))
        }
    }
```

- [ ] **Step 4: Remove now-unused static `goldRotation`/`blueRotation` usage from rotation effects on the orbs in `body`**

The outer `.rotationEffect(.degrees(goldRotation))` and `.rotationEffect(.degrees(blueRotation))` applied on the orbs in `body` (currently around lines 123 and 130) **stay** — they drive the larger rotation used in Phases 1 and 3 (`-18°`, `-8°`, `0°` etc.). The new wobble composes on top via `PhaseAnimator` inside the orb.

No change needed in `body` for this step — just confirming. If you accidentally removed the outer `.rotationEffect`, restore it.

- [ ] **Step 5: Build**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral" && xcodebuild -scheme Astral -sdk iphonesimulator -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Simulator check**

Run with Reduce Motion OFF. During Phase 2 (expansion), each orb should tilt subtly: ±5° wobble with a 0.15s offset between gold and blue. Ends at 0° by Phase 3.

Pass criteria:
- Wobble is visible but subtle — not distracting.
- Orbs still don't visually collide (widened positions from Task 4 plus ±5° rotation should still clear).
- Wobble does NOT run when Reduce Motion is ON (because `phase == 2` is never reached — `applyReducedMotionState()` jumps straight to phase 4).

- [ ] **Step 7: Commit**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp"
git add ios/Astral/App/RootView.swift
git commit -m "[ios] AST-5 add Phase 2 wobble via local PhaseAnimator

Each orb tilts ±5° during expansion using an inner PhaseAnimator
keyed on phase == 2. Blue is offset 0.15s from gold. Composes on
top of the outer rotationEffect that drives Phases 1 and 3.

Closes AST-5.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 11: Full Manual Verification Matrix

**Files:** none (test only)

- [ ] **Step 1: Reduce Motion OFF — iPhone 15 simulator**

Launch fresh. Watch the full sequence:
- Phase 1: tiny blobs pop in at corners, drift slightly inward. Gold appears first; blue 0.2s later.
- Phase 2: dramatic spring expansion. Orbs wobble ±5°, offset by 0.15s. Gold content reveals first; blue content follows. No overlap at any point.
- Phase 3: orbs contract + morph to rounded rectangles with a bouncy spring settle. Title "Astral" blurs in from `blur(8)` to sharp.
- Phase 4: subtitle "What are you reading?" fades in, then labels "Comics" / "Fan Fiction".
- Tap left half: scales + fades, then navigates to ComicTab.

- [ ] **Step 2: Reduce Motion OFF — iPhone SE simulator (375pt)**

Repeat. Specifically verify no orb overlap during Phase 2 on the narrowest supported width. If overlap is visible, STOP and report — the design-risk fallback is to cap Phase 2 orb size at 130pt.

- [ ] **Step 3: Reduce Motion ON**

Settings → Accessibility → Motion → Reduce Motion → ON. Relaunch Astral.
- Orbs are at final resting positions immediately.
- ~0.3s opacity cross-fade brings everything in.
- Title is present, sharp, at full scale.
- Labels and subtitle visible.
- Taps work instantly.
- No ambient background drift.

- [ ] **Step 4: Rapid dismiss**

With Reduce Motion OFF, launch app and immediately (mid-Phase 2) tap either half. App should navigate cleanly; no crash, no spurious warnings in Xcode console. Relaunch — no state corruption.

- [ ] **Step 5: Grep confirmation**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp"
grep -n DispatchQueue ios/Astral/App/RootView.swift
```

Expected: no output.

```bash
grep -n "contentReveal\b" ios/Astral/App/RootView.swift
```

Expected: no output (only `contentRevealGold` and `contentRevealBlue` should remain — the `\b` word boundary ensures we don't match the two new names).

- [ ] **Step 6: (Optional) UI test sanity**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral" && xcodebuild -scheme Astral -sdk iphonesimulator -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' test -only-testing:AstralUITests 2>&1 | tail -30
```

Expected: UI tests pass (they bypass landing via `--uitesting`). If a test fails, fix only if it relates to this change — unrelated UI-test failures are out of scope.

No commit for this task.

---

## Task 12: Open Pull Request

**Files:** none (git + gh operation)

- [ ] **Step 1: Push branch**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp"
git push -u origin feature/ast-1-landing-animation-redesign
```

- [ ] **Step 2: Create the PR targeting `development`**

```bash
gh pr create --base development --title "[ios] AST-1 landing animation redesign" --body "$(cat <<'EOF'
## Summary
- Fix Phase 2 orb overlap by widening positions to ±halfW * 0.38 and removing the 1.8s mid-drift step.
- Replace all `DispatchQueue.main.asyncAfter` in `runAnimation()` with `withAnimation(...) completion:` chaining plus an `animationToken` cancellation guard.
- Honor `accessibilityReduceMotion` — skip to final state with a 0.3s cross-fade.
- Polish: staggered content reveal (gold → blue), Phase 2 wobble via local `PhaseAnimator`, `.bouncy` Phase 3 finale, title blur-in, `PressButtonStyle` on tap zones.

Spec: `docs/superpowers/specs/2026-04-17-landing-animation-redesign-design.md`

## Test plan
- [ ] Reduce Motion OFF on iPhone 15 simulator — full sequence plays, no orb overlap.
- [ ] Reduce Motion OFF on iPhone SE (375pt) simulator — no overlap on narrowest supported width.
- [ ] Reduce Motion ON — cross-fade only, orbs at final positions, taps immediate.
- [ ] Rapid-dismiss mid-animation — no crash, correct tab lands.
- [ ] `grep DispatchQueue ios/Astral/App/RootView.swift` returns empty.

Fixes AST-1
Fixes AST-2
Fixes AST-3
Fixes AST-4
Fixes AST-5

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: Report the PR URL back**

The `gh pr create` output prints the PR URL — paste it into the conversation so the user can open it.

---

## Self-Review Notes (completed before handoff)

- Every spec section has a task: AST-2 → Task 4; AST-3 → Tasks 2–3; AST-4 → Task 5; AST-5 #1 → Task 6; AST-5 #2 → Task 10; AST-5 #3 → Task 7; AST-5 #4 → Tasks 1 (var added) + 8 (animation); AST-5 #5 → Task 9.
- New `@State` added in Task 1 and referenced by Tasks 6, 8, 10.
- `applyReducedMotionState()` in Task 5 sets both `contentRevealGold` and `contentRevealBlue` (consistent with Task 1's rename).
- `runPhase2MidDrift()` introduced in Task 2 and removed in Task 4 — intentional; Task 3 chains through it so Task 3 is verifiable independently of the overlap fix.
- Phase 1's outer `rotationEffect(.degrees(goldRotation))` on `body` stays; the inner `PhaseAnimator` wobble composes on top — explicit call-out in Task 10 Step 4 to prevent accidental removal.
- No placeholders, no "add error handling" stubs.
