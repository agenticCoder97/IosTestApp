# Landing Critical Fixes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Address the three critical issues from the AST-22 code review — stale-mirror terminal state (AST-24), fragile screen-size state (AST-25), and the PhaseAnimator double-wobble bug (AST-23) — stacked onto PR #20.

**Architecture:** Single file. Three commits, one per ticket. Execution order AST-24 → AST-25 → AST-23.

**Tech Stack:** SwiftUI, iOS 17.2+, Swift 6.

**Reference spec:** [docs/superpowers/specs/2026-04-17-landing-critical-fixes-design.md](../specs/2026-04-17-landing-critical-fixes-design.md)

**Linear**: [AST-22](https://linear.app/nnetraganti/issue/AST-22) parent; closes AST-23, AST-24, AST-25.
**Branch**: `feature/ast-1-landing-animation-redesign` (already on it).
**PR**: [apps#20](https://github.com/agenticCoder97/IosTestApp/pull/20) open; these commits extend it.

---

## Testing Approach

Same as AST-1 plan: build + simulator verify. No unit tests. User handles visual verification at the end. Each task commits individually.

---

## Task 1: Extract `LandingTerminalState` (AST-24)

**Files:** Modify: `ios/Astral/App/RootView.swift`

- [ ] Add file-private enum `LandingTerminalState` at top of file (just below `WobbleBeat` enum) with static constants for all Phase 4 terminal values.
- [ ] Rewrite `applyReducedMotionState()` to use `LandingTerminalState.*` for every non-opacity assignment.
- [ ] Rewrite `runPhase3()`'s morph-driver `withAnimation` block to use `LandingTerminalState.*` for `goldSize`, `blueSize`, `goldOffset`, `blueOffset`, `goldCornerRadius`, `blueCornerRadius`, `goldRotation`, `blueRotation`, `goldGlow`, `blueGlow`. The content-dissolve and title blocks in `runPhase3` also land on terminal values — update those too.
- [ ] Build + commit `[ios] AST-24 extract LandingTerminalState single source of truth`.

Detailed spec in subagent prompt.

## Task 2: Pass `size` explicitly (AST-25)

**Files:** Modify: `ios/Astral/App/RootView.swift`

- [ ] Delete `@State private var screenSize: CGSize = .zero`.
- [ ] Rewrite `runAnimation()` to `runAnimation(in size: CGSize)`.
- [ ] Rewrite `runPhase1`, `runPhase2`, `runPhase3`, `runPhase4` to take `(in size: CGSize)` uniformly. Inside, use `size.width` / `size.height` instead of `screenSize.*`.
- [ ] Update all completion closures to call `runPhaseN(in: size)`.
- [ ] Update `onAppear` to capture `let size = geo.size` once and pass through.
- [ ] Build + commit `[ios] AST-25 pass size explicitly, remove screenSize @State`.

## Task 3: Gate Phase 2 wobble (AST-23)

**Files:** Modify: `ios/Astral/App/RootView.swift`

- [ ] Rewrite `goldOrb` to `Group { if phase == 2 { PhaseAnimator(...) } else { goldOrbBody } }`.
- [ ] Remove `trigger: phase == 2` from the PhaseAnimator argument (the `if` is now the trigger).
- [ ] Same for `blueOrb` with `.delay(0.15)` preserved.
- [ ] Build + commit `[ios] AST-23 gate Phase 2 wobble to fire exactly once`.

## Task 4: Push to PR #20 + update Linear

- [ ] `git push` on `feature/ast-1-landing-animation-redesign`.
- [ ] Edit PR #20 description to append the three new commits + `Closes AST-23, AST-24, AST-25` lines.
- [ ] Move AST-22, 23, 24, 25 to **In Review** in Linear.
- [ ] Post a summary comment on AST-22 linking the three new SHAs.
