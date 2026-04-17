# AST-8 Reader Back Button Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One back button per reader, visible only when the user taps to reveal the HUD / reader bar.

**Architecture:** Delete the redundant floating back button from both comic and fanfic readers. Comic reader's existing `topBar` chevron remains as the sole back affordance. Fanfic reader gets a new `fanficTopBar` subview that mirrors comic's `topBar` layout pattern (slide-down with `.offset` + `.opacity`) and contains just a back chevron + fanfic title.

**Tech Stack:** SwiftUI, `@Environment(\.dismiss)`, `.ultraThinMaterial`, `AstralColors`/`AstralTypography`/`PressButtonStyle` from `DesignSystem`/`Core` packages.

**Spec:** [docs/superpowers/specs/2026-04-17-ast-8-reader-back-button-design.md](../specs/2026-04-17-ast-8-reader-back-button-design.md)

**Branch:** `fix/ast-8-floating-back-button` (off `origin/development`, already checked out)

**Testing note:** There are no unit tests for these SwiftUI reader views in the repo. Verification is manual in the iOS Simulator. Each task that touches code runs `xcodebuild` to catch compile regressions; Task 5 is the manual UX verification pass.

---

### Task 1: Delete comic reader floating back button

**Files:**
- Modify: `ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:154-172`

- [ ] **Step 1: Remove the floating back button block**

Find and delete the following block at lines 154-172 (the `// Floating back button — always visible as escape hatch` comment and the `VStack { HStack { Button { dismiss() } ... } }` that follows it, through the closing `.allowsHitTesting(!showHUD)` line):

```swift
// Floating back button — always visible as escape hatch
VStack {
    HStack {
        Button { dismiss() } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityIdentifier(AccessibilityID.readerBackButton)
        .padding(.leading, 16)
        .padding(.top, 54)
        .opacity(showHUD ? 0 : 0.6)
        Spacer()
    }
    Spacer()
}
.allowsHitTesting(!showHUD)
```

Replace with: nothing. Delete the block entirely, including the preceding blank line if it leaves two consecutive blank lines.

- [ ] **Step 2: Verify the build**

Run:

```bash
cd ios/Astral && xcodebuild -scheme Astral -sdk iphonesimulator -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build 2>&1 | tail -5
```

Expected output ends with: `** BUILD SUCCEEDED **`

If build fails, read the error (likely an unused `AccessibilityID.readerBackButton` reference somewhere else, or a dangling trailing comma). Fix before continuing.

- [ ] **Step 3: Commit**

```bash
git add ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift
git commit -m "[ios] AST-8 remove redundant floating back button from comic reader

The topBar chevron at line 568 already provides the back affordance
and is visible with the HUD. The floating button was visible only
when the HUD was hidden, creating two back buttons that toggled
opposite each other."
```

---

### Task 2: Add `fanficTopBar` computed subview to `FanficReaderView`

**Files:**
- Modify: `ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift`

- [ ] **Step 1: Locate insertion point**

Open `FanficReaderView.swift` and find the existing `chapterFavOverlay` computed property (around lines 362-416). Immediately after its closing brace, add the new `fanficTopBar` computed property.

- [ ] **Step 2: Add the `fanficTopBar` subview**

Insert this code after `chapterFavOverlay`:

```swift
// MARK: - Top Bar

private var fanficTopBar: some View {
    HStack(spacing: 12) {
        Button { dismiss() } label: {
            Image(systemName: "chevron.left")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AstralColors.white)
        }
        .buttonStyle(PressButtonStyle(scale: 0.88))
        .accessibilityIdentifier(AccessibilityID.readerBackButton)

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

Notes:
- `dismiss` is already declared on line 22 of the file (`@Environment(\.dismiss) private var dismiss`). Reuse it.
- `AccessibilityID.readerBackButton` is the same identifier the old floating button used — preserves UI test coverage if any exists.
- `PressButtonStyle`, `AstralColors`, `AstralTypography` are already imported in this file (used elsewhere — see `PressButtonStyle(scale: 0.88)` at line 396).
- `fanfic.title` is a property on the view's `LocalFanfic` model. If the compiler complains that `fanfic` is not a stored property, scan the `struct FanficReaderView` declaration for the actual fanfic binding name (likely `@Bindable var fanfic: LocalFanfic` or similar) and substitute.

- [ ] **Step 3: Verify the build**

Run:

```bash
cd ios/Astral && xcodebuild -scheme Astral -sdk iphonesimulator -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

The view is defined but not yet mounted in the ZStack — Swift still compiles fine because it's an unused computed property. **Do not commit yet.** Proceed to Task 3.

---

### Task 3: Mount `fanficTopBar` in the overlay `ZStack`

**Files:**
- Modify: `ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift` around lines 234-242 (before `chapterFavOverlay` mount)

- [ ] **Step 1: Locate the `chapterFavOverlay` mount block**

In `FanficReaderView.body`, find this block (around lines 234-242):

```swift
// Chapter + favourite overlay — top right
if showReaderBar {
    chapterFavOverlay
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.top, 56)
        .padding(.trailing, 16)
        .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .topTrailing)))
        .allowsHitTesting(showReaderBar)
}
```

- [ ] **Step 2: Insert the `fanficTopBar` mount immediately BEFORE that block**

Add this code as a new sibling in the `ZStack`, before the `// Chapter + favourite overlay — top right` comment:

```swift
// Top bar — slides in from above with reader bar
VStack(spacing: 0) {
    fanficTopBar
    Spacer()
}
.offset(y: showReaderBar ? 0 : -110)
.opacity(showReaderBar ? 1 : 0)
.animation(.easeInOut(duration: 0.22), value: showReaderBar)
.allowsHitTesting(showReaderBar)

```

This follows the exact pattern comic reader uses at `ComicReaderView.swift:174-182`.

- [ ] **Step 3: Verify the build**

```bash
cd ios/Astral && xcodebuild -scheme Astral -sdk iphonesimulator -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

**Do not commit yet.** Task 4 completes the fanfic side by removing the old floating button, and they commit together as one logical change.

---

### Task 4: Delete fanfic reader floating back button

**Files:**
- Modify: `ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift:197-215`

- [ ] **Step 1: Remove the floating back button block**

Find and delete the following block at lines 197-215 in `FanficReaderView.body` (the `// Floating back button — always visible as escape hatch` comment and the `VStack { HStack { Button { dismiss() } ... } }` through the closing `.allowsHitTesting(!showReaderBar)` line):

```swift
// Floating back button — always visible as escape hatch
VStack {
    HStack {
        Button { dismiss() } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityIdentifier(AccessibilityID.readerBackButton)
        .padding(.leading, 16)
        .padding(.top, 54)
        .opacity(showReaderBar ? 0 : 0.6)
        Spacer()
    }
    Spacer()
}
.allowsHitTesting(!showReaderBar)
```

Replace with: nothing. Delete entirely, including the preceding blank line if it leaves two consecutive blank lines.

- [ ] **Step 2: Verify the build**

```bash
cd ios/Astral && xcodebuild -scheme Astral -sdk iphonesimulator -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit fanfic changes together**

```bash
git add ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift
git commit -m "[ios] AST-8 add fanficTopBar, remove floating back button in fanfic reader

New fanficTopBar subview mirrors ComicReaderView.topBar's slide-down
pattern (.offset + .opacity with showReaderBar). Contains chevron
back + fanfic title only — chapterFavOverlay still handles chapter
badge/list/favorite on the top-right. Floating back button at former
lines 197-215 is removed as it was only visible with HUD hidden."
```

---

### Task 5: Manual verification in iOS Simulator

No automated tests exist for these reader views. Run the app and verify the acceptance criteria by hand.

- [ ] **Step 1: Launch the app in the simulator**

```bash
cd ios/Astral && xcodebuild -scheme Astral -sdk iphonesimulator -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build 2>&1 | tail -5
open -a Simulator
# Then from Xcode: Cmd+R to run, OR:
xcrun simctl install 8FF2D1FB-E342-4E2A-BFB6-F608B18609DF ~/Library/Developer/Xcode/DerivedData/Astral-*/Build/Products/Debug-iphonesimulator/Astral.app
xcrun simctl launch 8FF2D1FB-E342-4E2A-BFB6-F608B18609DF com.astral.reader
```

- [ ] **Step 2: Comic reader acceptance check**

  1. Navigate to the Comic tab → open any downloaded or scraped comic → tap a chapter.
  2. In reader with HUD **hidden** (default after a moment): confirm there is **no** visible back button anywhere.
  3. Tap the screen to reveal the HUD: confirm the `topBar` slides down with a chevron-left back button on the leading edge, and the title + chapter label are visible.
  4. Tap the chevron: confirm the reader dismisses back to the comic detail / library.
  5. Re-open the chapter. Tap to toggle HUD on, then tap again to toggle off. Confirm there is never a moment with two back buttons visible.

- [ ] **Step 3: Fanfic reader acceptance check**

  1. Navigate to the Fanfic tab → open any fanfic → tap a chapter.
  2. In reader with `readerBar` **hidden** (default after a moment): confirm there is **no** visible back button anywhere.
  3. Tap the screen to reveal `readerBar`: confirm
     - `fanficTopBar` slides down from the top with chevron on the leading edge + fanfic title
     - `chapterFavOverlay` appears on the top-right with its three circular buttons
     - The two do not overlap or collide at typical screen widths (iPhone 15 / iPad in portrait)
  4. Tap the chevron in `fanficTopBar`: confirm the reader dismisses back to the fanfic detail / library.
  5. Re-open. Tap to toggle `readerBar` off, then on. Confirm the slide animations feel smooth (≈220ms ease-in-out, matching comic).
  6. Scroll the reader content up and down while `readerBar` is hidden — confirm the overlay is not blocking scroll gestures.

- [ ] **Step 4: Edge case — long fanfic title**

Find or temporarily edit a fanfic so its title exceeds 60 characters, or use an existing long title. Open it in the reader and toggle `readerBar` on.

Expected: the title truncates with a tail ellipsis and does not push the chevron off screen or overlap `chapterFavOverlay`. If it does, add `.layoutPriority(1)` to the `Spacer()` or reduce title's `.frame(maxWidth:)` — but do not ship a fix that regresses the animation.

- [ ] **Step 5: If any check fails**

Stop. Record the exact symptom (screenshot + reproduction steps) and return to the appropriate task to fix. Do **not** proceed to Task 6 until all checks above pass.

---

### Task 6: Open pull request to `development`

- [ ] **Step 1: Push branch**

```bash
git push -u origin fix/ast-8-floating-back-button
```

(The branch was pushed already when the spec commit landed; this step is a no-op if `git status` shows `Your branch is up to date with 'origin/fix/ast-8-floating-back-button'`. If commits from Tasks 1 and 4 are ahead, this push ships them.)

- [ ] **Step 2: Open PR**

```bash
gh pr create --base development --title "[ios] AST-8 reader back button context-click visibility + fanfic parity" --body "$(cat <<'EOF'
## Summary

- Remove redundant floating back button from comic reader (the `topBar` chevron is the sole back affordance now).
- Add new `fanficTopBar` subview to fanfic reader mirroring comic's `topBar` slide-down pattern; contains chevron + fanfic title only.
- Remove redundant floating back button from fanfic reader.

Closes [AST-8](https://linear.app/nnetraganti/issue/AST-8/reader-floating-back-button-has-awkward-padding-and-shows-at-wrong).

Spec: `docs/superpowers/specs/2026-04-17-ast-8-reader-back-button-design.md`

## Test plan

- [x] Build succeeds: `xcodebuild -scheme Astral -sdk iphonesimulator build`
- [x] Comic reader: no floating back button; HUD toggle reveals/hides `topBar` with chevron; dismiss works
- [x] Fanfic reader: no floating back button; readerBar toggle reveals/hides `fanficTopBar` with chevron + title; `chapterFavOverlay` unchanged; dismiss works
- [x] No two back buttons ever visible at once in either reader
- [x] Long fanfic title truncates with ellipsis; no overlap with `chapterFavOverlay`
- [x] Scroll gestures in reader still work when overlay is hidden

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: Report the PR URL back to the user**

Print the URL returned by `gh pr create` so the user can review and merge.

---

## Self-review notes

**Spec coverage:**
- Delete comic floating button → Task 1 ✓
- Fanfic: delete floating + add `fanficTopBar` with exact code from spec → Tasks 2+3+4 ✓
- Mount point before `chapterFavOverlay` in ZStack → Task 3 ✓
- Slide-down pattern with `.offset` + `.opacity` + matching animation duration → Task 3 ✓
- Acceptance: one back button only, visible only on context click, dismiss works → Task 5 steps 2-3 ✓
- Risk: title overflow + overlap with `chapterFavOverlay` → Task 5 step 4 ✓

**Placeholder scan:** none — all steps have concrete code blocks or exact commands.

**Type consistency:** `dismiss`, `fanfic.title`, `AstralColors.white`, `AstralTypography.bodyMedium`, `PressButtonStyle(scale: 0.88)`, `AccessibilityID.readerBackButton`, `showReaderBar` — all verified against existing declarations in the same file or nearby files.

**Potential gotcha flagged:** Task 2 step 2 note — if `fanfic` is not the binding name, engineer scans `FanficReaderView` declaration and substitutes. This is explicit, not a placeholder.
