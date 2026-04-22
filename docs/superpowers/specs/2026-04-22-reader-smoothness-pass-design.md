# Reader smoothness pass — AST-62, AST-63, AST-64, AST-65

Linear issues:
- [AST-62](https://linear.app/nnetraganti/issue/AST-62) — Make comic reader context action appear on press
- [AST-63](https://linear.app/nnetraganti/issue/AST-63) — Fanfic reader top bar context action (bug)
- [AST-64](https://linear.app/nnetraganti/issue/AST-64) — Comic reader page number context action
- [AST-65](https://linear.app/nnetraganti/issue/AST-65) — Refine scroll action to next chapter for comic reader

Branch: `feature/ast-reader-smoothness-pass` (off `origin/development` @ `d5d2d64`)

## Problem

Four related Linear tickets all point at the same surface: the comic and fanfic readers feel inconsistent and slightly janky. The user framed the combined ask as *"make the reader smoother."* Current issues, by ticket:

- **AST-62** — tap-to-reveal chrome fires on touch release (`.onTapGesture`), which feels ~80–120 ms laggy. No description on the ticket; user confirmed the intent is "snappier tap, fire on touch-down."
- **AST-63** — fanfic chrome footprint feels larger than comic's. The real bloat is the floating `chapterFavOverlay` at top-right (58 pt badge + two 44 pt buttons stacked vertically, padded 56 pt from top). User chose the minimal fix: tighten padding in place, no structural rework.
- **AST-64** — the bottom-bar page indicator `"7 / 42"` is static text. No way to jump to a specific page directly (slider exists in paged mode only; webtoon mode has no jump UI at all).
- **AST-65** — the next-chapter scroll trigger on first/last page fires too easily and the progress ring "shows on load" before the user has even seen the edge page.

A code scan (see *Current State* below) also turned up six cross-cutting smoothness issues that span both readers. User elected to fix all six in this pass.

## Goals

1. Chrome reveal is instant on touch-down.
2. Fanfic chrome footprint tightened ~30 pt vertical, no layout churn.
3. Comic page indicator is a tappable `Menu` that jumps directly to any page.
4. Next-chapter trigger is disarmed on first/last page visibility, arms after 0.5 s, strict re-arm on exit/re-entry. Progress ring is invisible until armed.
5. Reader motion, haptics, and scroll-driven state writes are unified across comic and fanfic.

## Non-goals

- Shared `ReaderTopBar` component extraction (user chose C for AST-63; keep current layouts).
- OAuth, MangaDex, or any backend work.
- UI test harness / automation setup.
- Switching AST-64 to a wheel picker or thumbnail scrubber (both are fallback options if `Menu` perf is poor with >200 pages; ship `Menu` first).

## Current state (reference)

### Comic reader (`ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift`)
- Chrome toggle: `.onTapGesture` on center zone @ L495 → `toggleHUD()` @ L530. Animation: hardcoded `.easeInOut(duration: 0.22)` @ L161/174/199.
- Top bar: L546–614. Padding `.top(56)`, `.bottom(12)`, `.horizontal(16)`.
- Bottom bar: L618–674. Contains slider (paged only) and static page indicator `"\(currentPage + 1) / \(pages.count)"` @ L656–661.
- Page tracking: `@State currentPage: Int = 0` @ L34. Bound to `scrolledPageID` via `.scrollPosition(id:)` @ L458–472. `onChange(of: currentPage)` spring-syncs scroll @ L469.
- Webtoon chapter triggers: `PrevChapterTrigger` + `NextChapterTrigger` @ L1222–1310 with `chapterTriggerHeight = 260` @ L1219. Fires inside `GeometryReader.onChange` with `DispatchQueue.main.asyncAfter(0.3)` @ L353/393 — no visibility debounce, no re-arm guard, no initial-load suppression.
- Haptics: raw `UIImpactFeedbackGenerator(style: .medium)` @ L351/391 (only site in the reader).
- Known jank: `.onAppear { currentPage = index }` on every paged view @ L371/380 fires unthrottled during lazy-stack render.

### Fanfic reader (`ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift`)
- Chrome toggle: `.onTapGesture` on whole stack @ L238 → `showReaderBar.toggle()`. Animation: hardcoded `.spring(response: 0.42, dampingFraction: 0.82)` @ L239.
- `fanficTopBar`: L395–417. Padding `.top(56)`, `.bottom(12)`.
- `chapterFavOverlay`: L337–391. Pinned top-right via ZStack alignment, `.padding(.top, 56)`, `.padding(.trailing, 16)`. Contains 58 pt chapter badge circle, 44 pt list button, 44 pt favorite button.
- Reading progress bar: L190–204. `fanfic.scrollOffsetPercent` updated from per-paragraph `onAppear` @ L165 — unthrottled.
- No chapter trigger logic (fanfic uses horizontal paging for chapter nav, no pull-to-next-chapter).

### DesignSystem (`ios/Astral/Packages/DesignSystem/Sources/DesignSystem/AstralAnimations.swift`)
- Provides `AstralAnimation.{snappy,bouncy,smooth,sidebar,micro,quick,standard,stagger}` tokens + `PressButtonStyle`.
- Fanfic's chrome animation `0.42/0.82` is literally `AstralAnimation.smooth` — reader just re-declares it inline instead of using the token.
- No haptics helper. No throttle helper. No press-reveal modifier.

## Design

### Approach

Single feature branch `feature/ast-reader-smoothness-pass` cut from `origin/development`. One PR with four `Fixes AST-XX` lines in the body closes all four tickets atomically. Commits are sliced by sub-topic (see *Implementation order* below).

Shared infrastructure lands in `DesignSystem` first (ordered commits 1–4). Reader changes layer on top.

### New files in DesignSystem

#### 1. `Packages/DesignSystem/Sources/DesignSystem/ReaderMotion.swift`

Reader-specific motion tokens. Separate namespace from `AstralAnimation` so tuning reader feel doesn't affect app-wide UI.

```swift
import SwiftUI

public enum ReaderMotion {
    /// Chrome show/hide — fast, critically damped (no overshoot).
    /// Replaces comic's hardcoded .easeInOut(0.22) and fanfic's 0.42/0.82 spring.
    public static let chrome = Animation.spring(response: 0.28, dampingFraction: 0.88)

    /// Page turn in paged/webtoon mode. Preserves current feel.
    public static let pageTurn = Animation.spring(response: 0.38, dampingFraction: 0.86)

    /// Chapter content crossfade (used with .transition).
    public static let chapterCrossfade = Animation.easeInOut(duration: 0.24)

    /// Trigger ring fade in/out when arming state changes.
    public static let triggerRing = Animation.easeOut(duration: 0.18)
}
```

#### 2. `Packages/DesignSystem/Sources/DesignSystem/Haptics.swift`

Centralized haptic vocabulary. Wraps UIKit generators (preferred over SwiftUI's `.sensoryFeedback` for finer control — the existing trigger code already uses UIKit).

```swift
import UIKit

public enum HapticEvent {
    case chromeToggle   // light + soft: bar reveal/hide
    case pageTurn       // light: slider drag, menu selection
    case chapterNav     // medium: prev/next chapter buttons
    case triggerArmed   // light + soft: arming subtle tick
    case triggerFire    // medium: chapter trigger fires
    case bookmark       // rigid: bookmark toggle
}

public enum Haptics {
    public static func play(_ event: HapticEvent) {
        switch event {
        case .chromeToggle, .triggerArmed:
            let gen = UIImpactFeedbackGenerator(style: .soft)
            gen.impactOccurred(intensity: 0.6)
        case .pageTurn:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .chapterNav, .triggerFire:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .bookmark:
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        }
    }
}
```

#### 3. `Packages/DesignSystem/Sources/DesignSystem/Modifiers/PressReveal.swift`

Touch-down action modifier. Fires closure on first drag event (touch-down) rather than tap release. Guards re-firing with a `didFire` flag; resets on `onEnded`. Uses `.simultaneousGesture` so underlying `ScrollView` and `LongPressGesture` recognizers still receive touches.

```swift
import SwiftUI

public struct PressRevealModifier: ViewModifier {
    let action: () -> Void
    @State private var didFire = false

    public func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { _ in
                    if !didFire {
                        didFire = true
                        action()
                    }
                }
                .onEnded { _ in didFire = false }
        )
    }
}

public extension View {
    /// Fires `action` on touch-down instead of tap release.
    /// Coexists with ScrollView and LongPressGesture.
    func pressReveal(perform action: @escaping () -> Void) -> some View {
        modifier(PressRevealModifier(action: action))
    }
}
```

#### 4. `Packages/DesignSystem/Sources/DesignSystem/Throttle/ThrottledSetter.swift`

Reference-typed throttle for scroll-driven state writes. Keeps last-applied timestamp; drops writes inside the interval.

```swift
import Foundation

public final class ThrottledSetter<T: Equatable> {
    private let interval: TimeInterval
    private var lastApplied: Date = .distantPast
    private let clock: () -> Date

    public init(interval: TimeInterval, clock: @escaping () -> Date = Date.init) {
        self.interval = interval
        self.clock = clock
    }

    private var lastValue: T? = nil

    /// Applies `apply(value)` if enough time has passed since the last application
    /// AND the value has changed. Returns true if the write went through.
    @discardableResult
    public func set(_ value: T, apply: (T) -> Void) -> Bool {
        if lastValue == value { return false }
        let now = clock()
        guard now.timeIntervalSince(lastApplied) >= interval else { return false }
        lastApplied = now
        lastValue = value
        apply(value)
        return true
    }

    /// Force-apply on the next call (used on transitions like chapter change).
    public func reset() {
        lastApplied = .distantPast
        lastValue = nil
    }
}
```

### Per-ticket changes

#### AST-62 — Touch-down chrome reveal

**Comic reader** (`ComicReaderView.swift` @ L476–509, tap zone overlay):
- Replace `.onTapGesture { toggleHUD() }` with `.pressReveal { toggleHUD() }`.
- `toggleHUD()` body: `withAnimation(ReaderMotion.chrome) { showHUD.toggle() }; Haptics.play(.chromeToggle)`.

**Fanfic reader** (`FanficReaderView.swift` @ L238–242):
- Replace `.onTapGesture { withAnimation(...) { showReaderBar.toggle() } }` with `.pressReveal { toggleReaderBar() }`.
- `toggleReaderBar()` body: `withAnimation(ReaderMotion.chrome) { showReaderBar.toggle() }; Haptics.play(.chromeToggle)`.

Both readers remove their hardcoded chrome animation in favor of `ReaderMotion.chrome`.

#### AST-63 — Fanfic top bar padding tighten

**File:** `FanficReaderView.swift`

- `fanficTopBar` @ L395–417:
  - `.padding(.top, 56)` → `.padding(.top, 44)`
  - `.padding(.bottom, 12)` → `.padding(.bottom, 10)`
- `chapterFavOverlay` @ L337–391:
  - Parent `.padding(.top, 56)` @ L222 → `.padding(.top, 44)`
  - Badge circle: 58 pt → 48 pt (L342 `.frame(width:58,height:58)` → 48/48); reduce inner text sizes proportionally (18 → 16, 13 → 12, capsule 22×1.5 → 18×1.5)
  - List button circle: 44 pt → 40 pt (L365)
  - Heart button circle: 44 pt → 40 pt (L382)
  - Inner VStack `spacing: 8` @ L338 → `spacing: 6`
- Comic reader `topBar` padding unchanged.

Net: ~30 pt vertical reduction, no structural changes.

#### AST-64 — Page picker `Menu`

**File:** `ComicReaderView.swift` @ L656–661 (the static page indicator in `bottomBar`).

Replace the `Text("\(currentPage + 1) / \(pages.count)")` block with:

```swift
Menu {
    ForEach(0..<pages.count, id: \.self) { idx in
        Button("Page \(idx + 1)") {
            withAnimation(ReaderMotion.pageTurn) { currentPage = idx }
            Haptics.play(.pageTurn)
        }
    }
} label: {
    HStack(spacing: 4) {
        Text("\(currentPage + 1) / \(pages.count)")
            .font(AstralTypography.captionMedium)
            .foregroundStyle(AstralColors.white)
            .monospacedDigit()
            .contentTransition(.numericText())
        Image(systemName: "chevron.up.chevron.down")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(AstralColors.muted)
    }
    .animation(AstralAnimation.quick, value: currentPage)
}
.menuStyle(.button)
.buttonStyle(PressButtonStyle(scale: 0.94))
```

Existing `onChange(of: currentPage)` @ L469 already scrolls `scrolledPageID` with `ReaderMotion.pageTurn` — selection drives the scroll for free.

Works identically in paged (LTR/RTL) and webtoon modes. In webtoon mode it becomes the primary jump UI (no slider present there).

#### AST-65 — Trigger arming state machine

**File:** `ComicReaderView.swift`

New state on the reader view:

```swift
@State private var topEdgeVisibleSince: Date? = nil
@State private var topEdgeArmedAt: Date? = nil
@State private var bottomEdgeVisibleSince: Date? = nil
@State private var bottomEdgeArmedAt: Date? = nil
@State private var hasCompletedInitialLayout = false
```

Constants (derived from existing + user confirmation):
- `armDelay: TimeInterval = 0.5`
- `chapterTriggerHeight: CGFloat = 260` (unchanged)

**State transitions:**

1. On `.task` / chapter change: reset all five vars. `hasCompletedInitialLayout = false`. First `onChange(of: scrolledPageID)` or first non-zero scroll offset sets `hasCompletedInitialLayout = true`. Edge visibility is not observed until this flag is true — kills the "shows on load" bug.

2. `GeometryReader` in `PrevChapterTrigger` / `NextChapterTrigger` reports visibility (e.g. `frame.minY < screenHeight` for top trigger). On visibility true and `hasCompletedInitialLayout`, set `topEdgeVisibleSince = .now` (if nil). On visibility false, clear `topEdgeVisibleSince` and `topEdgeArmedAt` (strict re-arm per user choice 4a = A).

3. A `.onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect())` checks:
   ```
   if let visibleSince = topEdgeVisibleSince,
      topEdgeArmedAt == nil,
      Date().timeIntervalSince(visibleSince) >= armDelay {
       withAnimation(ReaderMotion.triggerRing) { topEdgeArmedAt = .now }
       Haptics.play(.triggerArmed)
   }
   ```
   Same pattern for bottom edge. Timer is a single `Timer.publish` for the view, not per-trigger.

4. Progress ring view in `PrevChapterTrigger` / `NextChapterTrigger` reads `opacity(armedAt == nil ? 0 : 1)` with `.animation(ReaderMotion.triggerRing, value: armedAt)`. **Invisible until armed.**

5. Pull progress calculation gated: `progress = armedAt == nil ? 0 : min(1.0, pullDistance / chapterTriggerHeight)`. At `progress >= 1.0`: fire `goToNextChapter()` / `goToPrevChapter()`, `Haptics.play(.triggerFire)`. Existing `DispatchQueue.main.asyncAfter(0.3)` flag-reset is replaced by resetting the `armedAt` / `visibleSince` vars inside `.task(id: currentChapter)` on chapter change.

Paged-mode chapter transitions (sentinel pages @ L427/449) are unchanged — this work is webtoon-specific.

### Smoothness pass (items 1, 2, 4, 5, 6)

| # | Scope | Change |
|---|---|---|
| 1 | Both readers | Replace inline `.easeInOut(0.22)` (comic L161/174/199) and `.spring(0.42/0.82)` (fanfic L239) with `ReaderMotion.chrome`. |
| 2 | Comic | `.onAppear { currentPage = index }` @ L371/380 goes through a `ThrottledSetter<Int>(interval: 0.08)` held on the reader view. Same setter used for `scrolledPageID` sync @ L469. |
| 2 | Fanfic | `fanfic.scrollOffsetPercent = ...` write in the per-paragraph `.onAppear` @ L165 goes through a `ThrottledSetter<Double>(interval: 0.08)`. |
| 4 | Both | Wrap chapter-dependent content in `.id(currentChapter.id).transition(.opacity)` + `withAnimation(ReaderMotion.chapterCrossfade)` around chapter nav calls. Add `prefetchNextChapter()` kicked off from `loadChapter()` — warms `CachedAsyncImage` cache for the next chapter's first 2 pages (comic) / next chapter's first paragraph chunk (fanfic). No new cache storage — uses existing `CachedAsyncImage`. |
| 5 | Comic | The ZStack-overlay long-press at `ComicReaderView.swift:408` currently blocks the ScrollView (cf. `feedback_gesture_scroll_conflict` memory). Convert `.onLongPressGesture` → `.simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { ... })`. Audit `pressReveal` + `LongPressGesture` composition — the `simultaneousGesture` in `pressReveal` is designed to coexist. |
| 6 | Both | Wire `Haptics.play(_:)` at: chrome toggle (AST-62), page turn via slider + Menu (AST-64), chapter nav button (existing `goToPrevChapter` / `goToNextChapter`), trigger arm (AST-65), trigger fire (AST-65, replacing raw `UIImpactFeedbackGenerator` calls @ L351/391), bookmark toggle (`bookmarkCurrentChapter()` in both readers). |

## Data flow

Tap on reader → `pressReveal` fires on touch-down → `toggleHUD()` / `toggleReaderBar()` → `withAnimation(ReaderMotion.chrome) { showHUD.toggle() }` + `Haptics.play(.chromeToggle)`. Bar animates in via existing offset/opacity modifiers (now driven by the unified spring).

Scroll event → SwiftUI updates scroll position → `onChange(of: scrolledPageID)` fires → `ThrottledSetter.set(newPage)` — applied only if 80 ms has elapsed since last apply. Unchanged page numbers are no-ops (Equatable check).

First/last page enters viewport → `GeometryReader.onChange` updates `topEdgeVisibleSince`. Timer tick 0.1 s later checks elapsed; on 0.5 s → `topEdgeArmedAt = .now`, ring fades in (`ReaderMotion.triggerRing`), subtle haptic. User pulls past 260 pt → progress 1.0 → chapter nav fires.

Chapter change → `.task(id: currentChapter.id)` — resets all arming state, resets `ThrottledSetter`, triggers crossfade transition, kicks off prefetch for next chapter.

## Error handling

- `Menu` with very long page lists (200+) — if open-latency is felt, swap for the wheel-sheet variant (AST-64 option B, held in reserve). Decided after manual QA.
- `Timer.publish` must be cancelled on view dismissal. Guaranteed by SwiftUI lifecycle (`onReceive` subscription tears down with view).
- `ThrottledSetter` is `final class` (reference semantics) so it survives view body re-renders. Held as `@State private var` on the reader view. Reset on chapter change via `.task`.
- `DragGesture(minimumDistance: 0)` risk: could intercept scroll gestures if priorities wrong. Mitigation: `.simultaneousGesture` (coexists), `didFire` guard (action only fires once per touch), manual QA verifies scroll still works.
- Prefetch failure: `CachedAsyncImage` already handles 404 / network errors silently. Prefetch is fire-and-forget — no error surface.

## Testing

### Unit tests (Swift Testing)

Only one new test file — the rest of the work is UI that Astral has no test harness for:

`Packages/DesignSystem/Tests/DesignSystemTests/ThrottledSetterTests.swift`:
- Writes inside interval are rejected.
- Write after interval is applied.
- `reset()` makes next write apply immediately.
- `Equatable` dedup — same value doesn't consume interval.
- Uses injected `clock:` closure for deterministic timing.

### Manual QA (PR body checklist)

1. Open a comic → tap anywhere → chrome reveals the *instant* finger touches (AST-62). Compare to fanfic — same feel (smoothness #1).
2. Tap the `"7 / 42"` page indicator → `Menu` drops down → pick page 15 → reader animates to page 15, subtle haptic (AST-64).
3. Switch to webtoon → scroll to last page of chapter — **no progress ring visible** on arrival. Wait 0.5 s → pull up ~260 pt → ring appears, fills, fires → next chapter loads with crossfade (AST-65 + smoothness #4).
4. Navigate back and re-enter same edge — timer restarts (strict re-arm).
5. Chapter-change flash — should be a crossfade, not a content swap (smoothness #4).
6. Open a fanfic → tap → top bar visibly tighter (44 pt top padding); chapter badge smaller (48 pt) (AST-63).
7. Scroll a 100 KB fanfic chapter — progress bar updates smoothly, no stutter (smoothness #2).
8. Every chrome toggle, page turn, chapter nav, and trigger fire has a distinct haptic (smoothness #6).
9. Long-press inside a comic still works without blocking scroll (smoothness #5, cf. `feedback_gesture_scroll_conflict` memory).

### Build verification

`cd ios/Astral && xcodebuild -scheme Astral -sdk iphonesimulator -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build`

Test on physical device (iPhone, AppConfig's LAN IP) after simulator passes.

## Implementation order

1. `ReaderMotion.swift` — motion tokens.
2. `Haptics.swift` — haptic vocabulary.
3. `Modifiers/PressReveal.swift` — touch-down modifier.
4. `Throttle/ThrottledSetter.swift` + `ThrottledSetterTests.swift`.
5. Comic reader: adopt `ReaderMotion.chrome`, `pressReveal`, `Haptics` (AST-62, smoothness #1/#6).
6. Comic reader: page `Menu` (AST-64).
7. Comic reader: arming state machine (AST-65).
8. Comic reader: `ThrottledSetter` adoption (smoothness #2).
9. Comic reader: gesture audit (smoothness #5).
10. Comic reader: chapter crossfade + prefetch (smoothness #4).
11. Fanfic reader: padding tighten (AST-63).
12. Fanfic reader: `ReaderMotion.chrome`, `pressReveal`, `Haptics` (smoothness #1/#6).
13. Fanfic reader: `ThrottledSetter` adoption (smoothness #2).
14. Fanfic reader: chapter crossfade + prefetch (smoothness #4).
15. Manual QA pass + PR.

Each numbered step is a separate commit. Prefix: `[ios] AST-62`, `[ios] AST-63`, `[ios] AST-64`, `[ios] AST-65`, `[ios] AST-62 AST-63 AST-64 AST-65` (for infra commits that serve all four).

## Risks

- **Menu render cost at >200 pages** — mitigation: swap to wheel-sheet fallback if manual QA reveals lag.
- **Touch-down modifier swallowing scroll** — mitigation: `.simultaneousGesture` + single-fire guard; verify via manual QA on both reading modes.
- **Strict re-arm feels annoying on re-reads** — mitigation: flip to "arm once per chapter" (4a = B) in a future tweak if user feedback warrants.
- **Prefetch warming wrong chapter** — only prefetch the chapter adjacent to current reading direction; cancel on chapter change.
- **Simulator haptics are silent** — manual QA must happen on physical device to validate feel.

## CHANGELOG

On merge into `development`, prepend to `CHANGELOG.md`:

```
## feature/ast-reader-smoothness-pass — 2026-04-22
- [ios] Reader smoothness pass: touch-down chrome, tappable page menu, armed chapter triggers, unified motion + haptics, throttled scroll writes, chapter crossfade. Closes AST-62, AST-63, AST-64, AST-65.
```
