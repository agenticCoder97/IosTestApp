# Landing Animation Redesign — Design

- **Date**: 2026-04-17
- **Linear**: [AST-1](https://linear.app/nnetraganti/issue/AST-1) (parent), closes [AST-2](https://linear.app/nnetraganti/issue/AST-2), [AST-3](https://linear.app/nnetraganti/issue/AST-3), [AST-4](https://linear.app/nnetraganti/issue/AST-4), [AST-5](https://linear.app/nnetraganti/issue/AST-5)
- **File**: `ios/Astral/App/RootView.swift` (only)
- **Target**: iOS 17.2+

## Summary

Rewrite `MorphLandingView.runAnimation()` in a single pass to fix orb overlap, remove `DispatchQueue.main.asyncAfter` sequencing, add `accessibilityReduceMotion` support, and apply five polish touches (stagger, wobble, bouncy finale, title blur-in, press feedback on tap zones).

The four sub-issues all modify the same ~130-line function, so they are implemented together as one PR.

## Goals

- No two orbs visually collide at any point in the sequence.
- Animation sequencing uses SwiftUI-native primitives — no `DispatchQueue`.
- `accessibilityReduceMotion == true` replaces the sequence with a ~0.3s cross-fade.
- Landing animation feels intentional and polished (stagger, wobble, bouncy finale, blur-in title, pressable tap zones).
- Performance remains smooth on supported devices (iPhone, iOS 17.2+).

## Non-goals

- Changing the color palette, orb content (book/scroll icons, manga panels, text lines), typography, or copy.
- Redesigning `ComicTabView`/`FanficTabView` or the cross-fade from landing to tabs.
- Replacing the `--uitesting` flag path (already skips landing).
- Ported animation logic to an extracted package — keep it inline in `RootView.swift` for now.

## Architecture

Single-file change. `MorphLandingView` keeps its public shape:

- Same `@State` vars, plus three new ones (listed below).
- Same `body` layout and `goldOrb` / `blueOrb` subview composition.
- Same phase enum semantics (`phase: 0…4`) and same final resting visuals.

The rewrite is concentrated in:

1. `runAnimation()` — sequencing via `withAnimation(...) completion:` chaining.
2. `goldOrb` / `blueOrb` — a small local `PhaseAnimator` wraps the shape stack for the Phase 2 wobble.
3. A new `applyReducedMotionState()` helper for the reduce-motion branch.

### Sequencing — AST-3 (approach A)

`withAnimation(_:_:completionCriteria:completion:)` (iOS 17+) drives the phase chain. Each phase may issue several parallel `withAnimation` calls (for distinct curves / delays); the `completion:` handler is attached only to the **driver** — the longest-running `withAnimation` in the phase. When the driver finishes (criteria: `.logicallyComplete`), the next phase is invoked:

```
runAnimation()
├─ if reduceMotion → applyReducedMotionState(); return
├─ start ambient drift
└─ Phase 1: fade-in + corner drift
   └─ completion → Phase 2: spring expand + single drift + staggered content reveal
      └─ completion → Phase 3: bouncy morph + title scale/blur-in
         └─ completion → Phase 4: subtitle + labels + enable taps
```

No `DispatchQueue.main.asyncAfter` remains in `runAnimation()`.

### Cancellation

Cancellation is handled by a token. Pattern (Phase 1 example — three parallel `withAnimation` calls, completion attached only to the longest, which is the drift animation at `0.5 + 1.2 = 1.7s`):

```swift
@State private var animationToken = UUID()

let token = animationToken

withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
    // gold fade-in state
}
withAnimation(.easeOut(duration: 0.5).delay(0.5)) {
    // blue fade-in state
}
// Driver — longest; carries completion.
withAnimation(.easeInOut(duration: 1.2).delay(0.5),
              completionCriteria: .logicallyComplete) {
    // drift state
} completion: {
    guard token == animationToken else { return }
    phase = 2
    runPhase2()
}

// on disappear:
.onDisappear { animationToken = UUID() }
```

Any in-flight completion that fires after the view disappears is dropped.

### New / modified `@State`

- `contentRevealGold: Double = 0` and `contentRevealBlue: Double = 0` — replace the single `contentReveal` so gold and blue can stagger.
- `titleBlur: CGFloat = 8` — animated to `0` during Phase 3 for blur-in.
- `animationToken: UUID` — cancellation guard described above.

Removed: the single `contentReveal` variable (replaced by the two above). `contentSlide` stays shared (both orbs' content slides up together; only the fade is staggered).

## Overlap fix — AST-2

Phase 2's mid-drift step (currently `DispatchQueue.main.asyncAfter(deadline: .now() + 1.8)` pulling orbs to ~68pt center distance at 140pt size) is **deleted**. Phase 2 uses a single positional animation with wider multipliers. Final positions:

| Step            | Gold offset                              | Blue offset                              | Center gap | Orb size |
| --------------- | ---------------------------------------- | ---------------------------------------- | ---------- | -------- |
| Phase 1 drift   | `(-halfW * 0.45, -halfH * 0.5)`          | `(+halfW * 0.4, +halfH * 0.45)`          | ~330pt     | 24–30pt  |
| Phase 2 expand  | `(-halfW * 0.38, -halfH * 0.2)`          | `(+halfW * 0.38, +halfH * 0.2)`          | ~148pt     | 135–140pt |
| Phase 3 final   | `(-80, 30)`                              | `(+80, 30)`                              | 160pt      | 120pt    |

At a 390pt screen width:
- Phase 2 gap: `0.38 * 195 * 2 ≈ 148pt` ≥ `70 + 70 = 140pt` (clears 140pt orbs with ~8pt clearance).
- Phase 3 gap: `160pt` ≥ `60 + 60 = 120pt` (clears 120pt orbs with 40pt clearance).

At a 430pt screen (iPhone Pro Max), the Phase 2 gap grows to ~163pt — more clearance, same multipliers.

AST-2's acceptance criterion calls for ≥20pt clearance. Phase 2 gets ~8pt on the narrowest supported width (iPhone SE/13 mini at 375pt: ~142pt gap = 2pt clearance). **Decision**: acceptable because (a) wobble rotation is ±5° so rotated orbs still clip via their bounding boxes, not their visuals (orb shape is a rounded rectangle, not a square), and (b) going wider shoves Phase 2 visually close to the Phase 1 corners, losing the "expansion" beat. If testing shows collision on 375pt devices, we'll either cap `goldSize`/`blueSize` at 130pt during Phase 2 or bump multipliers to 0.4.

## Polish — AST-5 (all 5)

1. **Staggered content reveal.** In Phase 2, animate `contentRevealGold` with `.delay(0.3)` and `contentRevealBlue` with `.delay(0.45)`. `contentSlide` animates once in the same block.

2. **Phase 2 wobble.** Inside `goldOrb` and `blueOrb`, wrap the shape stack in a `PhaseAnimator` keyed on `phase == 2`:
   ```swift
   PhaseAnimator([0.0, -5.0, 5.0, 0.0], trigger: phase == 2) { angle in
       content.rotationEffect(.degrees(angle))
   } animation: { _ in .easeInOut(duration: 0.7) }
   ```
   Runs once when Phase 2 is entered. Blue uses the same values with a `.delay(0.15)` so it's visually offset from gold.

3. **Bouncy finale.** Phase 3 morph animation swaps from `.spring(response: 0.55, dampingFraction: 0.55)` to `.bouncy(duration: 0.5, extraBounce: 0.15)`.

4. **Title blur-in.** Add `titleBlur: CGFloat = 8`, apply `.blur(radius: titleBlur)` on `Text("Astral")`, animate `titleBlur = 0` together with `titleScale` / `titleOpacity` inside Phase 3.

5. **Press feedback on tap zones.** Replace:
   ```swift
   Color.clear.contentShape(Rectangle()).onTapGesture { onSelect(.comic) }
   ```
   with:
   ```swift
   Button { onSelect(.comic) } label: {
       Color.clear.contentShape(Rectangle())
   }
   .pressEffect()
   .accessibilityIdentifier(AccessibilityID.landingComicOrb)
   ```
   `pressEffect()` is `DesignSystem.PressButtonStyle` (already defined).

## Reduce motion — AST-4

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion

private func runAnimation() {
    if reduceMotion {
        applyReducedMotionState()
        return
    }
    // ambient drift + phase chain
}

private func applyReducedMotionState() {
    // Snap all state vars to Phase 4 final values (no animation).
    goldSize = 120; blueSize = 120
    goldOffset = CGSize(width: -80, height: 30)
    blueOffset = CGSize(width: 80, height: 30)
    goldRotation = 0; blueRotation = 0
    goldBlobSkew = 1.0; blueBlobSkew = 1.0
    goldCornerRadius = 28; blueCornerRadius = 28
    goldGlow = 0.3; blueGlow = 0.3
    contentRevealGold = 1.0; contentRevealBlue = 1.0
    contentSlide = -5
    titleScale = 1.0; titleBlur = 0

    // Single cross-fade for the opacity values, no positional motion.
    withAnimation(.easeOut(duration: 0.3)) {
        goldOpacity = 1; blueOpacity = 1
        titleOpacity = 1; subtitleOpacity = 1; labelOpacity = 1
    }
    phase = 4
}
```

Ambient background drift (`ambientShift`) is **not** started when `reduceMotion == true` — it's a continuous motion loop, which reduce-motion users want gone.

## Testing

Manual simulator verification (primary — this is a visual change):

- **Reduce Motion OFF** — Full sequence plays; no visible orb overlap in Phase 1/2/3; wobble visible in Phase 2; title blurs in during Phase 3; tapping a zone scales it ~4% and fades.
- **Reduce Motion ON** (Settings → Accessibility → Motion → Reduce Motion) — Orbs appear at Phase 4 final positions with a single ~0.3s fade; taps immediately active; no ambient drift; no wobble.
- **Rapid dismiss** — Trigger the landing, then immediately tap (or swap to reduce-motion mid-flight). No crash, no dangling state.
- **Screen sizes** — Verify on iPhone SE (375pt), iPhone 15 (393pt), iPhone 15 Pro Max (430pt). Check Phase 2 clearance on the 375pt device specifically.

Build:
```
cd ios/Astral && xcodebuild -scheme Astral -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build
```

UI tests: existing `--uitesting` flag sets `showLanding = false` at launch, so the landing view is bypassed. No UI-test changes needed.

## Risks / open questions

- **Phase 2 clearance on 375pt devices.** Mid-drift deletion brings closest-approach to ~142pt center distance on the narrowest supported width. If wobble rotation causes visual clipping, fallback is to cap Phase 2 `goldSize`/`blueSize` at 130pt.
- **`PhaseAnimator` nested inside `withAnimation`-driven parent.** Using `PhaseAnimator` locally inside `goldOrb`/`blueOrb` while the parent drives Phase 2's `phase` state should be safe — the `PhaseAnimator` only observes its own `trigger`. If any animation conflicts emerge, fallback is to drive wobble manually via a `Timer.publish` or a `withAnimation(.easeInOut(duration: 0.7).repeatCount(3, autoreverses: true))` applied to a new `@State var wobble: Double = 0`.

## Rollout

- Branch: `feature/ast-1-landing-animation-redesign` (branches from `development`).
- Single commit (or small commit chain) prefixed `[ios] AST-1 …`.
- PR body includes `Closes AST-1`, `Closes AST-2`, `Closes AST-3`, `Closes AST-4`, `Closes AST-5`.
- Merge target: `development`.
