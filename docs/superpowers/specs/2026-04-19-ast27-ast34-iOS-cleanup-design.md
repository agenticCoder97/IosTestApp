# AST-27 + AST-34 — iOS Cleanup (Design)

**Date:** 2026-04-19
**Linear:** [AST-27](https://linear.app/nnetraganti/issue/AST-27), [AST-34](https://linear.app/nnetraganti/issue/AST-34)
**Branch:** `feature/ast-27-ast-34-cleanup` (off `development` post-AST-21 merge)
**PR:** Single PR with `Closes AST-27` and `Closes AST-34` magic-word lines so both Linear issues auto-close on merge.

## Why bundled

Both are tiny, iOS-only, no-behavior-change tweaks on different surfaces (landing animation vs fanfic reader). Bundling them into one PR saves a review cycle and matches the "ship a satisfying cleanup" intent.

## Out of scope

- **AST-27 sub-item #1** (move `blueColor` from `RootView.swift:103` to DesignSystem) — already done by AST-21 (PR #27, merged). The token `AstralColors.blue` is in `development` and `RootView.swift` already uses it.
- **AST-34 candidate #4** (collapse "Chapter N" + title into one line when title is short) — adds conditional layout logic and a "short title" definition; risk is disproportionate to the marginal compaction gain. Defer.
- **AST-34 reading-time relocation** — explicitly removed entirely, NOT moved to the HUD or chapter sheet. Chapter length is already visible in the chapter sheet's progress.

## AST-27 — `MorphLandingView` cleanup (3 sub-items)

### Sub-item 2 — Named phase-geometry constants

`ios/Astral/App/RootView.swift` — `MorphLandingView`'s `runPhaseN` functions currently embed magic numbers like `halfW * 0.38`, `halfH * 0.2`, `width: 80`, `height: 30`, repeated across multiple call sites. Extract to a file-private enum near the top of `MorphLandingView`:

```swift
private enum PhaseGeometry {
    /// Phase 1 — orbs drift in from corners while still small.
    static let phase1HorizontalFraction: CGFloat = 0.45
    static let phase1VerticalFraction: CGFloat = 0.5

    /// Phase 2 — widened from 0.25 to fix orb overlap (AST-2). Centers stay ≥148pt apart on 390pt width.
    static let phase2HorizontalFraction: CGFloat = 0.38
    static let phase2VerticalFraction: CGFloat = 0.2

    static let finalOffsetX: CGFloat = 80
    static let finalOffsetY: CGFloat = 30
}
```

Replace all five occurrences in `runPhase1`, `runPhase2`, `runPhase3` (and any others) with the named constants. No numerical change — pure rename.

### Sub-item 3 — Phase 3 driver comment

`ios/Astral/App/RootView.swift:449` — the morph-spring `withAnimation(.bouncy(...), completionCriteria: .logicallyComplete)` is the driver of the Phase 3 → Phase 4 transition even though it completes slightly before the title spring. Future readers shouldn't swap drivers without understanding the timing. Add the comment exactly as the AST-27 ticket specifies:

```swift
// DRIVER: shortest of this phase's three withAnimations. Title spring (~0.8s)
// intentionally overlaps into Phase 4's label fade; this makes the sequence
// feel tighter. Do not swap drivers without updating this comment.
withAnimation(.bouncy(duration: 0.5, extraBounce: 0.15),
              completionCriteria: .logicallyComplete) {
```

### Sub-item 4 — `onDisappear` token-rotation comment

`ios/Astral/App/RootView.swift:210-212` — the `onDisappear { animationToken = UUID() }` block looks defensive but has a specific contract. Add a comment explaining the lifecycle:

```swift
.onDisappear {
    // Rotate token so any in-flight completion closures from the previous
    // animation chain bail out. withAnimation writes are already committed;
    // this only guards runPhaseN() chain re-entry.
    animationToken = UUID()
}
```

## AST-34 — Fanfic reader chapter-header compaction (3 tweaks)

`ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift:77-111` — the in-flow chapter header VStack at the top of every chapter's body. All three tweaks are subtractive — no new fields, no new tokens, no conditional layout.

### Tweak 1 — Shrink title font multiplier

```swift
// Before
.font(fontFamily.boldFont(size: fontSize * 1.4))
// After
.font(fontFamily.boldFont(size: fontSize * 1.2))
```

The chapter title is currently the largest visual element in the header. `1.2` multiplier keeps it clearly larger than the surrounding labels (chapter number at `0.75`, body at `1.0`) while reducing its dominant vertical footprint by ~14%.

### Tweak 2 — Remove the reading-time HStack entirely

```swift
// Delete this entire block (lines ~92-99):
HStack(spacing: 6) {
    Image(systemName: "clock")
        .font(.system(size: fontSize * 0.65))
    Text(readingTimeLabel)
        .font(fontFamily.font(size: fontSize * 0.75))
}
.foregroundStyle(AstralColors.muted.opacity(0.8))
```

`readingTimeLabel` is computed elsewhere in the view; check whether removing this consumer makes the computed property/state unused, and remove the dead computation if so. (Likely needed for the chapter list / HUD — leave the helper if it's referenced anywhere else.)

### Tweak 3 — Tighten spacings (3 numeric edits)

| Current | New | Where |
|---|---|---|
| `VStack(alignment: .leading, spacing: 6)` | `spacing: 4` | header VStack, line ~79 |
| `.padding(.bottom, 8)` | `.padding(.bottom, 4)` | applied to header VStack, line ~101 |
| `.padding(.vertical, 20)` | `.padding(.vertical, 10)` | outer ScrollView content, line ~151 |

The outer `.padding(.vertical, 20)` change is the largest gain — it tightens the top edge by 10pt before the chapter header even renders.

## Acceptance criteria

**AST-27:**
- No bare phase-geometry magic numbers in `runPhaseN` bodies (everything goes through `PhaseGeometry.*`).
- The two doc-comments are present at the lines specified.
- Build passes.
- Landing animation visually unchanged (manual smoke: launch app once, watch the orbs animate).

**AST-34:**
- First paragraph of the chapter is visible further up the screen on iPhone 15/16 simulator without scrolling.
- Chapter number, title, and divider remain clearly readable; the design language (uppercase tracking on the chapter number, serif title, diamond divider) is preserved.
- Reading-time block is gone from the in-flow header (no replacement surface).
- All three reader backgrounds (dark / sepia / paper) verified — no visual regression.
- Font-size slider still scales the header proportionally — no hardcoded point sizes introduced.

**Both:**
- iOS build passes (`xcodebuild -scheme Astral -sdk iphonesimulator … build` returns `** BUILD SUCCEEDED **`).
- PR body includes `Closes AST-27` and `Closes AST-34` on separate lines so Linear auto-closes both on merge.

## File inventory

**Modified:**
- `ios/Astral/App/RootView.swift` — `PhaseGeometry` enum + 5 call-site replacements + 2 doc comments (AST-27)
- `ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift` — 3 numeric edits + 1 block deletion (AST-34)

**Possibly deleted:**
- `readingTimeLabel` helper (or related state) in `FanficReaderView.swift` if it has no other consumers after the HStack removal.

**No new files. No design tokens. No new dependencies.**

## Build sequence (TDD-style is overkill here — just commit after each verification)

1. Branch from `development`.
2. AST-27 sub-item 2 (PhaseGeometry enum + 5 replacements). Build. Smoke-test landing animation. Commit `[ios] AST-27 extract MorphLandingView phase-geometry constants`.
3. AST-27 sub-item 3 (Phase 3 driver comment). Build. Commit `[ios] AST-27 document Phase 3 spring driver in MorphLandingView`.
4. AST-27 sub-item 4 (onDisappear comment). Build. Commit `[ios] AST-27 document animation token rotation in MorphLandingView.onDisappear`.
5. AST-34 tweak 1 (title multiplier). Build. Commit `[ios] AST-34 shrink fanfic reader chapter title from 1.4× to 1.2× fontSize`.
6. AST-34 tweak 2 (drop reading-time HStack + clean any orphan helper). Build. Commit `[ios] AST-34 remove reading-time block from in-flow chapter header`.
7. AST-34 tweak 3 (spacing tightening — VStack/header padding/outer ScrollView padding). Build. Smoke-test fanfic reader in dark+sepia+paper backgrounds. Commit `[ios] AST-34 tighten chapter header and outer ScrollView spacings`.
8. Final iOS build. Open PR with `Closes AST-27` + `Closes AST-34`.

## Risks

- **AST-27 sub-item 2 fraction values** — the comment in the existing code mentions Phase 2 width was widened to fix overlap (AST-2). Make sure the extracted values keep that geometry correct. Pure rename — no math change.
- **AST-34 tweak 2 dead code** — if `readingTimeLabel` is computed lazily as a `var`, removing the only consumer in this file is fine. If it's a `@State`-backed value used elsewhere (HUD?), leave the computation intact and just remove the rendering. Verify before deleting any helper.
- **AST-34 tweak 3 reader backgrounds** — the outer padding change is the most visible. Sepia and paper modes have different perceived contrast vs dark mode, so make sure the divider line still reads correctly in all three.

## References

- Linear: [AST-27](https://linear.app/nnetraganti/issue/AST-27), [AST-34](https://linear.app/nnetraganti/issue/AST-34)
- Parent context: AST-22 code review (where AST-27 originated as bundled cleanup); AST-8 (floating back button — explicit non-goal of AST-34)
- Adjacent merged work: AST-21 (PR #27) added `AstralColors.blue` and removed AST-27 sub-item #1 from this PR's scope.
