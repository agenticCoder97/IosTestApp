# AST-8 — Reader back button: context-click visibility + fanfic parity

Linear: [AST-8](https://linear.app/nnetraganti/issue/AST-8/reader-floating-back-button-has-awkward-padding-and-shows-at-wrong)
Branch: `fix/ast-8-floating-back-button` (off `origin/development`)

## Problem

Both comic and fanfic readers render a persistent floating back button in the top-left with `.padding(.leading, 16) + .padding(.top, 54)`. Two issues:

1. Visibility is inverted — the button is visible while the reader HUD is **hidden**, and disappears when the user taps to reveal reader controls.
2. In the comic reader, the button is redundant with an existing `topBar` back chevron that appears with the HUD. Two separate back affordances toggle opposite each other.

The fanfic reader has no `topBar` equivalent — its only HUD element is `chapterFavOverlay`, a vertical column pinned top-right (chapter badge, chapter list, favorite).

## Goal

Exactly one back button per reader, visible only when the user taps the screen to reveal the HUD / reader controls.

## Design

### Comic reader

**Delete** the floating back button at `ComicReaderView.swift:154-172`. No replacement.

`topBar` at lines 566-634 already contains a chevron back button at line 568, mounted in a `VStack { topBar; Spacer() }` with:
- `.offset(y: showHUD ? 0 : -110)`
- `.opacity(showHUD ? 1 : 0)`

This becomes the sole back affordance. No other changes to the comic reader.

### Fanfic reader

**Delete** the floating back button at `FanficReaderView.swift:197-215`.

**Introduce** a new `fanficTopBar` private computed subview. Shape and behavior mirror `ComicReaderView.topBar` (lines 566-634), minus the chapter/list/bookmark/settings controls (those already live in `chapterFavOverlay` on the top-right).

**`fanficTopBar` body**:

```swift
private var fanficTopBar: some View {
    HStack(spacing: 12) {
        Button { dismiss() } label: {
            Image(systemName: "chevron.left")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AstralColors.white)
        }
        .buttonStyle(PressButtonStyle(scale: 0.88))

        Text(fanfic.title)
            .font(AstralTypography.bodyMedium)
            .foregroundStyle(AstralColors.white)
            .lineLimit(1)
            .truncationMode(.tail)

        Spacer()
    }
    .padding(.horizontal, 16)
    .padding(.top, 56)
    .padding(.bottom, 12)
    .background(.ultraThinMaterial)
}
```

**Mount point**: in the overlay `ZStack` inside `FanficReaderView.body`, add a sibling of `chapterFavOverlay` with the same slide-down pattern comic uses:

```swift
VStack(spacing: 0) {
    fanficTopBar
    Spacer()
}
.offset(y: showReaderBar ? 0 : -110)
.opacity(showReaderBar ? 1 : 0)
.animation(.easeInOut(duration: 0.22), value: showReaderBar)
.allowsHitTesting(showReaderBar)
```

Mount it before `chapterFavOverlay` in the ZStack so `chapterFavOverlay`'s top-right column stacks above `fanficTopBar`'s visual background (no hit-test conflict since each anchors to its own edge).

**Typography decision**: comic uses `AstralTypography.caption` + `AstralColors.muted` for `comic.title` because the primary line is the chapter label. Fanfic's `fanficTopBar` has no chapter label, so the title is the primary identifier — use `AstralTypography.bodyMedium` + `AstralColors.white` (matches comic's chapter-label treatment) to give the title appropriate weight.

**Dismiss wiring**: the existing floating button at lines 197-215 already invokes `dismiss()` (via `@Environment(\.dismiss)`). Reuse the same environment value in the new `fanficTopBar` button.

### Shared behavior

- Back action on both readers: dismiss the reader (reuse the existing dismiss closure currently wired to the floating buttons).
- Design tokens (colors, typography) come from the DesignSystem package — no hardcoded hex.

## Out of scope

- No refactor of `chapterFavOverlay` or its contents.
- No chapter label, progress meter, or additional controls in `fanficTopBar` — just back + title.
- No shared abstraction between `ComicReaderView.topBar` and `fanficTopBar`. Both remain local subviews in their respective reader views. Parity is structural, not code-shared.
- No changes to `readerSettingsBar` (bottom bar) in fanfic reader.
- No migration / persistence changes.

## Files touched

- `ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift` — delete lines 154-172.
- `ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift` — delete lines 197-215, add new `fanficTopBar` subview and mount it inside the existing `if showReaderBar { ... }` overlay block.

## Acceptance

- Comic reader: no floating back button in normal reading; tapping the screen reveals HUD with `topBar` chevron; tapping chevron dismisses reader.
- Fanfic reader: no floating back button in normal reading; tapping the screen reveals `readerBar` + new `fanficTopBar` at the top; `fanficTopBar` shows chevron and fanfic title; tapping chevron dismisses reader.
- `chapterFavOverlay` continues to appear top-right with `showReaderBar` as today; no layout overlap with `fanficTopBar`.
- Exactly one back button is ever visible in either reader at any given moment.

## Verification plan

- Build succeeds via `xcodebuild -scheme Astral -sdk iphonesimulator`.
- Manual in simulator:
  - Open a comic; tap to toggle HUD several times; confirm chevron visibility matches HUD state.
  - Open a fanfic; tap to toggle readerBar; confirm `fanficTopBar` slides in/out with readerBar; confirm chapterFavOverlay still appears on the top-right without overlap.
  - Tap back in each reader; confirm dismiss still works.
  - Verify long scroll in both readers does not conflict with the overlay (gesture regression check).

## Risks

- Layout overlap between `fanficTopBar` (top-left) and `chapterFavOverlay` (top-right) on narrow screens if the fanfic title is long — mitigated by `.lineLimit(1)` + `.truncationMode(.tail)` and by giving `chapterFavOverlay` explicit trailing anchor.
- `.ultraThinMaterial` background behind dark reader content may look slightly different from the comic reader due to different underlying page color. Verify visually; if needed, tune opacity.
