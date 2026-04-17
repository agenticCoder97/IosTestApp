# Landing Critical Fixes — Design

- **Date**: 2026-04-17
- **Parent**: [AST-22](https://linear.app/nnetraganti/issue/AST-22) (code review of AST-1 PR #20)
- **Closes**: [AST-23](https://linear.app/nnetraganti/issue/AST-23), [AST-24](https://linear.app/nnetraganti/issue/AST-24), [AST-25](https://linear.app/nnetraganti/issue/AST-25)
- **File**: `ios/Astral/App/RootView.swift` (only)
- **Branch**: `feature/ast-1-landing-animation-redesign` (stacked on top of PR #20; not yet merged)

## Summary

Three fast-follow fixes identified in the AST-22 code review. All touch the same file that PR #20 rewrote; stacking them on the same branch keeps review scope coherent.

Design decisions made autonomously (per user directive "don't wait for user input"):

1. **Land on the same branch / PR** rather than a separate PR off development — PR #20 is still open, and the fixes directly address review feedback on that work.
2. **Three commits, one per critical**, preserving the per-ticket commit hygiene style of AST-1.
3. **Execution order**: AST-24 → AST-25 → AST-23. AST-24 introduces the terminal-state enum that AST-23's `else` branch implicitly relies on (no coupling, but reads better in that order). AST-25 changes function signatures; doing it before AST-23's orb-view refactor avoids back-to-back touches on the orb computed properties.

## Non-goals

- Addressing the 🟡 suggestions (AST-26, AST-27). Those get their own sweep.
- Changing any visual behavior of the animation. Reduce-motion fallback must render identically to the pre-fix version.
- Extracting views into the DesignSystem package. MorphLandingView stays inline.

---

## AST-24 — Extract terminal state

### Problem recap

`applyReducedMotionState()` hand-mirrors Phase 3/4 final values. Drift is silent.

### Design

File-private enum at the top of `RootView.swift` (just below the `WobbleBeat` enum):

```swift
/// Single source of truth for the landing animation's Phase 4 final state.
/// Consumed by both `runPhase3()` and `applyReducedMotionState()`.
private enum LandingTerminalState {
    static let orbSize: CGFloat = 120
    static let goldOffset = CGSize(width: -80, height: 30)
    static let blueOffset = CGSize(width: 80, height: 30)
    static let cornerRadius: CGFloat = 28
    static let glow: Double = 0.3
    static let blobSkew: CGFloat = 1.0
    static let rotation: Double = 0
    static let contentSlide: CGFloat = -5
    static let contentReveal: Double = 1.0
    static let titleScale: CGFloat = 1.0
    static let titleBlur: CGFloat = 0
}
```

Both consumers rewritten to reference `LandingTerminalState.*`. No behavioral change — byte-identical values.

**Not** included in the enum: opacity values (`goldOpacity = 1`, `titleOpacity = 1`, etc.) — they're trivially `1` and not worth a constant. Keep inline.

### Scope change justification

The enum is a type, not a struct instance — no runtime allocation, no `@MainActor` concerns. Constants are `static let`, inlined by the compiler. Zero overhead.

---

## AST-25 — Pass `size` explicitly

### Problem recap

`screenSize: CGSize` is a `@State` that gets written in `onAppear` and read by all phase functions. Fragile ordering assumption + not cleared on disappear.

### Design

1. Delete `@State private var screenSize: CGSize = .zero`.
2. Change `runAnimation()` signature to `runAnimation(in size: CGSize)`.
3. Change `runPhase1()`, `runPhase2()`, `runPhase2MidDrift` was already removed — change remaining `runPhase1`/`runPhase2`/`runPhase3`/`runPhase4` to `(in size: CGSize)`. `runPhase3` and `runPhase4` don't currently read `screenSize` — they still take `size` for signature consistency (makes future changes trivial; ignored inside).
4. Completion closures pass `size` forward: `runPhase2(in: size)` etc.
5. `applyReducedMotionState()` is unchanged — it reads no dimensions.
6. `onAppear` captures `let size = geo.size` once, uses it for both the corner-start offsets and the `runAnimation(in:)` call.

### Scope edge case

`runPhase3` currently doesn't reference `screenSize`. It should still accept `size: CGSize` for uniform signatures — YAGNI says leave it out, but signature uniformity across a tight `runPhaseN` family outweighs YAGNI here. If the reviewer prefers the omission, flag it and skip for runPhase3/runPhase4.

**Decision**: keep signatures uniform `(in size: CGSize)` on all four phase functions.

### Why not an `Environment`-style capture?

Storing `size` in an `@Environment` or view-model object is overkill for four function calls in one file. Parameter passing is direct and obvious.

---

## AST-23 — Gate wobble on `phase == 2`

### Problem recap

`PhaseAnimator(trigger: phase == 2)` fires on any trigger change, including `true → false` when Phase 3 starts, causing a second wobble cycle during the morph.

### Design — chosen approach

Gate the PhaseAnimator behind `if phase == 2`. When false, render `goldOrbBody` directly.

```swift
private var goldOrb: some View {
    Group {
        if phase == 2 {
            PhaseAnimator(WobbleBeat.allCases) { beat in
                goldOrbBody.rotationEffect(.degrees(beat.angle))
            } animation: { _ in .easeInOut(duration: 0.7) }
        } else {
            goldOrbBody
        }
    }
}
```

Same shape for `blueOrb` with `.easeInOut(duration: 0.7).delay(0.15)` in the animation closure.

Removed: the `trigger: phase == 2` argument on the PhaseAnimator (no longer needed — the wrapper's existence IS the trigger).

### Alternatives considered

1. **Explicit withAnimation sequence** — drop PhaseAnimator, use three chained `withAnimation(.delay(...))` calls on a `@State wobbleAngle`. More control but duplicates the wobble mechanic we already built in AST-5; adds state vars. Not worth it unless the `if`-gate approach has visual issues.
2. **`@State wobbleTrigger: UUID`** bumped once in `runPhase2()` — keeps PhaseAnimator trigger-based but only fires once. Works, but adds a state var that only exists to work around PhaseAnimator's edge semantics. Not worth it.

### Risk: view identity churn

When `phase` changes from 2 to 3, the `if` branch flips and SwiftUI could tear down the PhaseAnimator-wrapped view and mount the bare `goldOrbBody`. In theory this causes a frame-skip or animation reset. In practice:

- The outer `.scaleEffect` / `.offset` / `.rotationEffect` / `.opacity` modifiers in `body` are applied to `goldOrb` as a whole — they continue to drive their values through the `Group` boundary.
- The inner wobble rotation reaches 0 on the `.settle` beat before Phase 3 fires (~2.1s wobble duration vs. Phase 2's total ~2.8s window). When the gate flips, inner rotation is already at 0, so the bare body renders at 0° too — no visible pop.
- `goldOrbBody` contents (glow halo, fill, stroke, content VStack) are the same identical subtree either way.

**Fallback if this produces artifacts during verification**: switch to alternative #1 (explicit withAnimation sequence).

---

## Testing

Build + manual simulator verification:

1. `xcodebuild build` succeeds after each commit.
2. Reduce Motion OFF — full sequence plays; Phase 2 wobble fires once, no extra wobble during the Phase 3 morph; final resting state matches pre-fix version.
3. Reduce Motion ON — orbs at terminal state, cross-fade in 0.3s. Verify `LandingTerminalState` values match what Phase 4 would have landed at.
4. Rapid-dismiss during Phase 1/2 — no crash; no state corruption on relaunch.

No unit tests — visual animation, same as AST-1.

## Rollout

- Three commits (`[ios] AST-24 …`, `[ios] AST-25 …`, `[ios] AST-23 …`) on `feature/ast-1-landing-animation-redesign`.
- Push to update PR #20.
- PR body gets an edit to list the new commits and add `Closes AST-23, AST-24, AST-25` lines.
- Linear issues transition to In Review on push.
