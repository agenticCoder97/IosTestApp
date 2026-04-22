# Reader Smoothness Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land AST-62, AST-63, AST-64, AST-65 and a six-item smoothness pass in a single reader polish branch. Unify reader motion and haptics across comic + fanfic, make chrome reveal on touch-down, turn the comic page indicator into a tappable Menu, arm the next-chapter trigger after 0.5 s of edge visibility, tighten fanfic chrome padding, throttle scroll-driven state writes, crossfade chapter content, and audit gesture priorities.

**Architecture:** Shared infrastructure lands in `DesignSystem` first (motion tokens, haptics vocabulary, press-reveal modifier, throttle helper with Swift Testing tests). Both readers then adopt the shared infra in a consistent order — comic reader first (it carries AST-62/64/65 plus the trigger arming machine), fanfic reader second (AST-63 padding tighten plus motion/haptic/throttle adoption). One PR closes all four tickets via `Fixes AST-XX` lines.

**Tech Stack:** SwiftUI, Swift 6.0, Swift Testing (`@Suite`, `@Test`), UIKit haptics (`UIImpactFeedbackGenerator`), SwiftData, iOS 17.2+ deployment target.

**Spec:** [docs/superpowers/specs/2026-04-22-reader-smoothness-pass-design.md](../specs/2026-04-22-reader-smoothness-pass-design.md)

**Branch:** `feature/ast-reader-smoothness-pass` (off `origin/development` @ `d5d2d64`, already checked out; spec commit `9cffbd9` on top)

**Testing note:** Only the `ThrottledSetter` helper gets unit tests (Swift Testing, injected clock). Reader UI changes are verified by (a) `xcodebuild` compile checks after each task and (b) a consolidated manual QA pass at the end (Task 15). Astral has no UI test harness — we don't try to fake one.

---

## File Structure

### New files

- `ios/Astral/Packages/DesignSystem/Sources/DesignSystem/ReaderMotion.swift` — reader-specific animation tokens (chrome, pageTurn, chapterCrossfade, triggerRing)
- `ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Haptics.swift` — `HapticEvent` enum + `Haptics.play(_:)` dispatch
- `ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Modifiers/PressReveal.swift` — `PressRevealModifier` + `.pressReveal { ... }` view extension (touch-down tap)
- `ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Throttle/ThrottledSetter.swift` — reference-typed `ThrottledSetter<T: Equatable>` with injected clock
- `ios/Astral/Packages/DesignSystem/Tests/DesignSystemTests/ThrottledSetterTests.swift` — Swift Testing suite with deterministic clock (first test target for DesignSystem)

### Modified files

- `ios/Astral/Packages/DesignSystem/Package.swift` — add `.testTarget(name: "DesignSystemTests")`
- `ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift` — AST-62 (tap→pressReveal), AST-64 (page Menu), AST-65 (arming state machine), smoothness #1 (ReaderMotion.chrome), #2 (ThrottledSetter adoption), #4 (chapter crossfade + prefetch), #5 (gesture audit), #6 (Haptics wiring)
- `ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift` — AST-63 (padding tighten), smoothness #1, #2, #4, #6 adoption

### Unchanged files

- `ios/Astral/Packages/DesignSystem/Sources/DesignSystem/AstralAnimations.swift` — existing tokens stay; reader introduces its own namespace

---

### Task 1: Add `ThrottledSetter` with Swift Testing suite

**Why first:** TDD-testable helper used by both readers. Also establishes the DesignSystem test target.

**Files:**
- Modify: `ios/Astral/Packages/DesignSystem/Package.swift`
- Create: `ios/Astral/Packages/DesignSystem/Tests/DesignSystemTests/ThrottledSetterTests.swift`
- Create: `ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Throttle/ThrottledSetter.swift`

- [ ] **Step 1: Add the test target to the DesignSystem package**

Edit `Package.swift` — after the existing `.target(name: "DesignSystem", dependencies: ["Core"])` entry, extend the `targets:` array with a test target.

Replace the full contents of `Package.swift` with:

```swift
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DesignSystem",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
    ],
    dependencies: [
        .package(path: "../Core"),
    ],
    targets: [
        .target(name: "DesignSystem", dependencies: ["Core"]),
        .testTarget(
            name: "DesignSystemTests",
            dependencies: ["DesignSystem"],
            path: "Tests/DesignSystemTests"
        ),
    ]
)
```

- [ ] **Step 2: Write the failing test suite**

Create `ios/Astral/Packages/DesignSystem/Tests/DesignSystemTests/ThrottledSetterTests.swift` with:

```swift
import Testing
import Foundation
@testable import DesignSystem

@Suite("ThrottledSetter")
struct ThrottledSetterTests {

    /// Mutable clock used by the injected closure.
    final class FakeClock {
        var now: Date = Date(timeIntervalSince1970: 0)
        func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    }

    @Test("first write always applies")
    func firstWriteApplies() {
        let clock = FakeClock()
        let setter = ThrottledSetter<Int>(interval: 0.1, clock: { clock.now })
        var applied: Int?
        let didWrite = setter.set(42) { applied = $0 }
        #expect(didWrite == true)
        #expect(applied == 42)
    }

    @Test("write inside interval is rejected")
    func writeInsideIntervalRejected() {
        let clock = FakeClock()
        let setter = ThrottledSetter<Int>(interval: 0.1, clock: { clock.now })
        var applied: Int?
        _ = setter.set(1) { applied = $0 }
        clock.advance(0.05) // half the interval
        let didWrite = setter.set(2) { applied = $0 }
        #expect(didWrite == false)
        #expect(applied == 1) // still the first value
    }

    @Test("write after interval is applied")
    func writeAfterIntervalApplied() {
        let clock = FakeClock()
        let setter = ThrottledSetter<Int>(interval: 0.1, clock: { clock.now })
        var applied: Int?
        _ = setter.set(1) { applied = $0 }
        clock.advance(0.15) // past the interval
        let didWrite = setter.set(2) { applied = $0 }
        #expect(didWrite == true)
        #expect(applied == 2)
    }

    @Test("same value is a no-op even past interval")
    func sameValueIsNoOp() {
        let clock = FakeClock()
        let setter = ThrottledSetter<Int>(interval: 0.1, clock: { clock.now })
        var callCount = 0
        _ = setter.set(1) { _ in callCount += 1 }
        clock.advance(0.5)
        let didWrite = setter.set(1) { _ in callCount += 1 }
        #expect(didWrite == false)
        #expect(callCount == 1) // apply closure only invoked once
    }

    @Test("reset makes the next write apply immediately")
    func resetMakesNextWriteApply() {
        let clock = FakeClock()
        let setter = ThrottledSetter<Int>(interval: 0.1, clock: { clock.now })
        _ = setter.set(1) { _ in }
        setter.reset()
        let didWrite = setter.set(1) { _ in } // same value, but reset clears lastValue too
        #expect(didWrite == true)
    }

    @Test("works with Double")
    func worksWithDouble() {
        let clock = FakeClock()
        let setter = ThrottledSetter<Double>(interval: 0.1, clock: { clock.now })
        var applied: Double?
        let didWrite = setter.set(3.14) { applied = $0 }
        #expect(didWrite == true)
        #expect(applied == 3.14)
    }
}
```

- [ ] **Step 3: Verify the tests fail (no implementation yet)**

Run:

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem" && swift build 2>&1 | tail -20
```

Expected output includes: error messages like `cannot find 'ThrottledSetter' in scope` and build fails.

- [ ] **Step 4: Implement `ThrottledSetter`**

Create the directory and file. Create `ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Throttle/ThrottledSetter.swift` with:

```swift
import Foundation

/// Drops writes that arrive within `interval` of the previous applied write,
/// OR whose value is unchanged from the last applied value. Reference-typed
/// so a single instance can be held as `@State` on a SwiftUI view and shared
/// across body re-renders.
public final class ThrottledSetter<T: Equatable> {
    private let interval: TimeInterval
    private let clock: () -> Date
    private var lastApplied: Date = .distantPast
    private var lastValue: T? = nil

    public init(interval: TimeInterval, clock: @escaping () -> Date = Date.init) {
        self.interval = interval
        self.clock = clock
    }

    /// Applies `apply(value)` if enough time has passed since the last applied
    /// write AND the value has changed. Returns `true` if the write went through.
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

    /// Clears both last-applied timestamp and last value so the next `set` applies.
    /// Use on view transitions (e.g. chapter change) where the throttle should reset.
    public func reset() {
        lastApplied = .distantPast
        lastValue = nil
    }
}
```

- [ ] **Step 5: Run the tests — expect PASS**

Run:

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem" && swift test 2>&1 | tail -20
```

Expected: `Test Suite 'ThrottledSetter' passed` with 6 tests passing.

- [ ] **Step 6: Commit**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp" && \
git add ios/Astral/Packages/DesignSystem/Package.swift \
        ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Throttle/ThrottledSetter.swift \
        ios/Astral/Packages/DesignSystem/Tests/DesignSystemTests/ThrottledSetterTests.swift && \
git commit -m "$(cat <<'EOF'
[ios] AST-62 AST-63 AST-64 AST-65 add ThrottledSetter helper + tests

Reference-typed throttle for scroll-driven state writes. Drops writes
inside the interval or with unchanged values. Used by both readers to
tame unthrottled onAppear-driven state updates during scroll.

Also adds the first test target to the DesignSystem package.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Add `ReaderMotion` tokens

**Files:**
- Create: `ios/Astral/Packages/DesignSystem/Sources/DesignSystem/ReaderMotion.swift`

- [ ] **Step 1: Create the reader-motion token namespace**

Create `ios/Astral/Packages/DesignSystem/Sources/DesignSystem/ReaderMotion.swift` with:

```swift
import SwiftUI

/// Reader-specific motion vocabulary. Kept separate from `AstralAnimation`
/// so tuning the reader's feel (chrome, page turns, chapter transitions,
/// trigger ring) doesn't ripple into app-wide UI motion.
public enum ReaderMotion {

    /// Chrome show/hide — fast, critically damped (no overshoot).
    /// Replaces comic's hardcoded `.easeInOut(0.22)` and fanfic's
    /// `.spring(response: 0.42, dampingFraction: 0.82)`.
    public static let chrome = Animation.spring(response: 0.28, dampingFraction: 0.88)

    /// Page turn in paged and webtoon modes. Preserves the current feel
    /// so the Menu-driven jump animation matches the existing spring.
    public static let pageTurn = Animation.spring(response: 0.38, dampingFraction: 0.86)

    /// Chapter content crossfade. Used with `.id(chapter.id).transition(.opacity)`.
    public static let chapterCrossfade = Animation.easeInOut(duration: 0.24)

    /// Trigger ring fade in/out when the arming state changes.
    public static let triggerRing = Animation.easeOut(duration: 0.18)
}
```

- [ ] **Step 2: Verify the package still builds**

Run:

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem" && swift build 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp" && \
git add ios/Astral/Packages/DesignSystem/Sources/DesignSystem/ReaderMotion.swift && \
git commit -m "$(cat <<'EOF'
[ios] AST-62 AST-63 AST-64 AST-65 add ReaderMotion token namespace

Reader-specific animation tokens separate from AstralAnimation. Lets us
tune chrome, page turn, chapter crossfade, and trigger ring motion
without affecting app-wide UI.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Add `Haptics` helper

**Files:**
- Create: `ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Haptics.swift`

- [ ] **Step 1: Create the haptic-event vocabulary**

Create `ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Haptics.swift` with:

```swift
import UIKit

/// Semantic haptic events used across the reader. Callers play events by name
/// rather than choosing a generator style — so swapping feel is a one-line change.
public enum HapticEvent {
    case chromeToggle   // reader bar reveal / hide
    case pageTurn       // slider drag step, Menu page selection
    case chapterNav     // prev/next chapter button press
    case triggerArmed   // subtle tick when the chapter trigger arms
    case triggerFire    // chapter trigger fires
    case bookmark       // bookmark toggle
}

public enum Haptics {
    /// Plays the haptic feedback for the given semantic event.
    /// Safe to call from any thread — `UIImpactFeedbackGenerator` handles dispatch.
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

- [ ] **Step 2: Verify the package still builds**

Run:

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem" && swift build 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp" && \
git add ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Haptics.swift && \
git commit -m "$(cat <<'EOF'
[ios] AST-62 AST-63 AST-64 AST-65 add semantic Haptics helper

Centralized HapticEvent enum + Haptics.play(_:) dispatch. Replaces raw
UIImpactFeedbackGenerator calls scattered through the reader and gives
a single place to tune haptic feel.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Add `PressReveal` modifier (touch-down action)

**Files:**
- Create: `ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Modifiers/PressReveal.swift`

- [ ] **Step 1: Create the modifier**

Create `ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Modifiers/PressReveal.swift` with:

```swift
import SwiftUI

/// Fires `action` on touch-down (first gesture event) rather than tap release.
/// Built on `DragGesture(minimumDistance: 0)` with a single-fire guard so it
/// behaves like `.onTapGesture` but ~80–120 ms earlier. Uses
/// `.simultaneousGesture` so underlying `ScrollView` and `LongPressGesture`
/// recognizers still receive touches.
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
    /// Coexists with ScrollView scrolling and LongPressGesture recognizers.
    func pressReveal(perform action: @escaping () -> Void) -> some View {
        modifier(PressRevealModifier(action: action))
    }
}
```

- [ ] **Step 2: Verify the package still builds**

Run:

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem" && swift build 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp" && \
git add ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Modifiers/PressReveal.swift && \
git commit -m "$(cat <<'EOF'
[ios] AST-62 add pressReveal modifier for touch-down actions

DragGesture(minimumDistance: 0) with a single-fire guard. Fires the
action the instant a finger lands, then resets on touch-up. Uses
simultaneousGesture so it coexists with ScrollView and LongPressGesture.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Comic reader — adopt `ReaderMotion.chrome`, `pressReveal`, `Haptics`

**What this lands:** AST-62 (touch-down chrome reveal), smoothness #1 (unified chrome animation), smoothness #6 (haptics on chrome toggle).

**Files:**
- Modify: `ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift`

- [ ] **Step 1: Update `toggleHUD` to drive animation + haptic in one place**

Find the existing `toggleHUD()` at lines 529–532:

```swift
private func toggleHUD() {
    showHUD.toggle()
    if !showHUD { showSettings = false }
}
```

Replace with:

```swift
private func toggleHUD() {
    withAnimation(ReaderMotion.chrome) {
        showHUD.toggle()
        if !showHUD { showSettings = false }
    }
    Haptics.play(.chromeToggle)
}
```

- [ ] **Step 2: Replace the center-zone `.onTapGesture` with `.pressReveal`**

Find the tap zones at lines 484–511 (the `tapZoneOverlay` computed property). The middle rectangle currently uses `.onTapGesture { toggleHUD() }` at line 495.

Replace the full `tapZoneOverlay` body with:

```swift
private var tapZoneOverlay: some View {
    GeometryReader { geo in
        HStack(spacing: 0) {
            Rectangle()
                .fill(.clear)
                .frame(width: geo.size.width / 3)
                .onTapGesture { handleLeftTap() }

            Rectangle()
                .fill(.clear)
                .frame(width: geo.size.width / 3)
                .pressReveal { toggleHUD() }

            Rectangle()
                .fill(.clear)
                .frame(width: geo.size.width / 3)
                .onTapGesture { handleRightTap() }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                longPressedPage = pages[safe: currentPage]
                showPageActions = true
            }
        )
    }
    .allowsHitTesting(true)
}
```

Only the middle rectangle changed: `.onTapGesture { toggleHUD() }` → `.pressReveal { toggleHUD() }`. Left and right stay on `.onTapGesture` because they toggle paging in paged modes and don't need to fire on touch-down.

- [ ] **Step 3: Swap the three hardcoded chrome animations to `ReaderMotion.chrome`**

At line 161 (top HUD), line 174 (chapter overlay), and line 199 (bottom HUD), replace three identical instances of:

```swift
.animation(.easeInOut(duration: 0.22), value: showHUD)
```

with:

```swift
.animation(ReaderMotion.chrome, value: showHUD)
```

Use `Edit` with `replace_all: false` three times, once per site (each line's surrounding context is distinct: top HUD has `.offset(y: showHUD ? 0 : -110)` immediately before; chapter overlay has `.padding(.trailing, 16)` two lines before; bottom HUD has `.offset(y: showHUD ? 0 : 130)` immediately before). If in doubt, include 2–3 lines of surrounding context in the `old_string`.

- [ ] **Step 4: Swap the two webtoon-mode long-press `toggleHUD` haptic sites later (out of scope here)**

Nothing to do in this step — the webtoon trigger's raw `UIImpactFeedbackGenerator` calls at lines 351/391 are migrated to `Haptics.play(.triggerFire)` in Task 7 (AST-65 state machine). Left here as an explicit no-op to remind the engineer not to migrate them yet — the trigger logic still uses the old flag-based system at this step.

- [ ] **Step 5: Verify the app builds**

Run:

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral" && xcodebuild -scheme Astral -sdk iphonesimulator -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build 2>&1 | tail -5
```

Expected output ends with: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp" && \
git add ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift && \
git commit -m "$(cat <<'EOF'
[ios] AST-62 comic reader chrome on touch-down + unified motion

Center tap zone now uses .pressReveal so chrome reveals the instant a
finger lands. Chrome animation standardized on ReaderMotion.chrome
(replaces hardcoded .easeInOut(0.22)). toggleHUD fires
Haptics.play(.chromeToggle) for subtle feedback.

Closes AST-62. Part of smoothness items #1 and #6.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Comic reader — page `Menu` jump UI (AST-64)

**Files:**
- Modify: `ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift`

- [ ] **Step 1: Replace the static page indicator with a `Menu`**

Find the static page indicator in `bottomBar` at lines 656–661:

```swift
Text("\(currentPage + 1) / \(pages.count)")
    .font(AstralTypography.captionMedium)
    .foregroundStyle(AstralColors.white)
    .monospacedDigit()
    .contentTransition(.numericText())
    .animation(AstralAnimation.quick, value: currentPage)
```

Replace with:

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
.disabled(pages.isEmpty)
```

The existing `.onChange(of: currentPage)` binding at line 469 already scrolls `scrolledPageID` with a spring — picking a page from the Menu drives the scroll for free.

- [ ] **Step 2: Verify the app builds**

Run:

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral" && xcodebuild -scheme Astral -sdk iphonesimulator -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build 2>&1 | tail -5
```

Expected output ends with: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp" && \
git add ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift && \
git commit -m "$(cat <<'EOF'
[ios] AST-64 tappable page Menu for comic reader bottom bar

The bottom-bar page indicator is now a SwiftUI Menu. Tapping it drops
down a scrollable list of pages; selecting one drives currentPage and
the existing onChange spring scrolls the reader to that page with a
light haptic tick.

Works in paged and webtoon modes. In webtoon it becomes the primary
page-jump UI (no slider present there).

Closes AST-64.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Comic reader — AST-65 arming state machine for chapter triggers

**Why it's the biggest task:** this replaces the entire trigger-fires-on-load hazard with a time-gated armed / disarmed state machine. Touches the reader's state surface, the webtoon reader body, and both trigger subviews.

**Files:**
- Modify: `ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift`

- [ ] **Step 1: Add arming state to the reader**

Find the block of `@State` declarations on `ComicReaderView` starting around line 32. Immediately after the existing line `@State private var prevChapterTriggered = false` at line 53, insert five new state vars:

Find this (lines 52–54):

```swift
    @State private var prevChapterPull: CGFloat = 0
    @State private var prevChapterTriggered = false
    @State private var showChapterList = false
```

Replace with:

```swift
    @State private var prevChapterPull: CGFloat = 0
    @State private var prevChapterTriggered = false
    // AST-65 arming: edge-visibility timestamps drive a 0.5s arm delay.
    // nil = edge not visible. Once armed, pull can fire the trigger.
    @State private var topEdgeVisibleSince: Date? = nil
    @State private var topEdgeArmedAt: Date? = nil
    @State private var bottomEdgeVisibleSince: Date? = nil
    @State private var bottomEdgeArmedAt: Date? = nil
    @State private var hasCompletedInitialLayout = false
    @State private var showChapterList = false
```

- [ ] **Step 2: Expose the `armDelay` constant next to the existing `chapterTriggerHeight`**

Find the existing private file-scope constant at line 1219:

```swift
private let chapterTriggerHeight: CGFloat = 260
```

Replace with:

```swift
private let chapterTriggerHeight: CGFloat = 260
private let chapterArmDelay: TimeInterval = 0.5
```

- [ ] **Step 3: Rewrite `PrevChapterTrigger` to observe visibility and gate progress on `armedAt`**

Find the existing `PrevChapterTrigger` struct at lines 1222–1262. Replace the entire struct with:

```swift
/// Placed at the top of webtoon scroll content — scroll up to load previous chapter.
/// Reports its visibility and pull progress upward; progress is gated on arming.
private struct PrevChapterTrigger: View {
    let onVisibilityChange: (Bool) -> Void
    let onProgressChange: (CGFloat) -> Void
    let progress: CGFloat
    let isArmed: Bool

    var body: some View {
        GeometryReader { geo in
            let frame = geo.frame(in: .global)
            let visible = max(0, frame.maxY)
            let pct = min(visible / chapterTriggerHeight, 1.0)
            let isVisible = visible > 0
            Color.clear
                .onChange(of: isVisible) { _, new in onVisibilityChange(new) }
                .onChange(of: pct) { _, new in
                    // Only forward progress when the trigger is armed.
                    // Reports 0 otherwise so the parent resets any cached pull.
                    onProgressChange(isArmed ? new : 0)
                }
        }
        .frame(height: chapterTriggerHeight)
        .overlay {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(AstralColors.muted.opacity(0.3), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(AstralColors.gold, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.1), value: progress)

                    Image(systemName: progress >= 1.0 ? "checkmark" : "chevron.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(progress >= 1.0 ? AstralColors.gold : AstralColors.muted)
                }
                .frame(width: 28, height: 28)

                Text(progress >= 1.0 ? "Loading prev..." : "Previous chapter")
                    .font(AstralTypography.caption)
                    .foregroundStyle(AstralColors.muted)
            }
            .opacity(isArmed ? (progress > 0.02 ? 1 : 0.3) : 0)
            .animation(ReaderMotion.triggerRing, value: isArmed)
        }
    }
}
```

- [ ] **Step 4: Rewrite `NextChapterTrigger` the same way**

Find the existing `NextChapterTrigger` struct at lines 1265–1305. Replace the entire struct with:

```swift
/// Placed at the bottom of webtoon scroll content — scroll down to load next chapter.
private struct NextChapterTrigger: View {
    let onVisibilityChange: (Bool) -> Void
    let onProgressChange: (CGFloat) -> Void
    let progress: CGFloat
    let isArmed: Bool

    var body: some View {
        GeometryReader { geo in
            let frame = geo.frame(in: .global)
            let screenH = UIScreen.main.bounds.height
            let visible = max(0, screenH - frame.minY)
            let pct = min(visible / chapterTriggerHeight, 1.0)
            let isVisible = visible > 0
            Color.clear
                .onChange(of: isVisible) { _, new in onVisibilityChange(new) }
                .onChange(of: pct) { _, new in
                    onProgressChange(isArmed ? new : 0)
                }
        }
        .frame(height: chapterTriggerHeight)
        .overlay {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(AstralColors.muted.opacity(0.3), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(AstralColors.gold, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.1), value: progress)

                    Image(systemName: progress >= 1.0 ? "checkmark" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(progress >= 1.0 ? AstralColors.gold : AstralColors.muted)
                }
                .frame(width: 28, height: 28)

                Text(progress >= 1.0 ? "Loading next..." : "Next chapter")
                    .font(AstralTypography.caption)
                    .foregroundStyle(AstralColors.muted)
            }
            .opacity(isArmed ? (progress > 0.02 ? 1 : 0.3) : 0)
            .animation(ReaderMotion.triggerRing, value: isArmed)
        }
    }
}
```

- [ ] **Step 5: Update the webtoon reader to pass the new callbacks and gate on `hasCompletedInitialLayout`**

Find the webtoon reader body at lines 341–411. The two existing `PrevChapterTrigger` / `NextChapterTrigger` call sites currently only pass `onProgressChange` + `progress`. Also the on-progress closures currently wrap the fire logic — this has to change.

Replace the full `webtoonReader` body with:

```swift
private var webtoonReader: some View {
    ScrollView(.vertical, showsIndicators: false) {
        LazyVStack(spacing: 0) {
            // Previous chapter pull trigger at top of scroll content
            if !isFirstChapter {
                PrevChapterTrigger(
                    onVisibilityChange: { visible in
                        guard hasCompletedInitialLayout else { return }
                        if visible {
                            topEdgeVisibleSince = .now
                        } else {
                            topEdgeVisibleSince = nil
                            topEdgeArmedAt = nil
                            prevChapterPull = 0
                        }
                    },
                    onProgressChange: { progress in
                        prevChapterPull = progress
                        if progress >= 1.0 && !prevChapterTriggered {
                            prevChapterTriggered = true
                            Haptics.play(.triggerFire)
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(300))
                                goToPrevChapter()
                                prevChapterTriggered = false
                                prevChapterPull = 0
                            }
                        }
                    },
                    progress: prevChapterPull,
                    isArmed: topEdgeArmedAt != nil
                )
            }

            if let localURLs = localPageURLs, !localURLs.isEmpty {
                // Device-saved pages — load from local files
                ForEach(Array(localURLs.enumerated()), id: \.offset) { index, url in
                    ZoomablePageView {
                        LocalPageView(fileURL: url)
                    }
                    .id(index)
                    .onAppear {
                        hasCompletedInitialLayout = true
                        currentPage = index
                    }
                }
            } else {
                // Network pages
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                    ZoomablePageView {
                        ComicPageView(page: page)
                    }
                    .id(index)
                    .onAppear {
                        hasCompletedInitialLayout = true
                        currentPage = index
                    }
                }
            }

            // Next chapter pull trigger at bottom of scroll content
            if !isLastChapter {
                NextChapterTrigger(
                    onVisibilityChange: { visible in
                        guard hasCompletedInitialLayout else { return }
                        if visible {
                            bottomEdgeVisibleSince = .now
                        } else {
                            bottomEdgeVisibleSince = nil
                            bottomEdgeArmedAt = nil
                            nextChapterPull = 0
                        }
                    },
                    onProgressChange: { progress in
                        nextChapterPull = progress
                        if progress >= 1.0 && !nextChapterTriggered {
                            nextChapterTriggered = true
                            Haptics.play(.triggerFire)
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(300))
                                goToNextChapter()
                                nextChapterTriggered = false
                                nextChapterPull = 0
                            }
                        }
                    },
                    progress: nextChapterPull,
                    isArmed: bottomEdgeArmedAt != nil
                )
            }
        }
    }
    .simultaneousGesture(
        LongPressGesture(minimumDuration: 0.5).onEnded { _ in
            toggleHUD()
        }
    )
    .modifier(AutoScrollModifier(isActive: autoScrollActive, speed: autoScrollSpeed))
    .task(id: topEdgeVisibleSince) {
        guard let since = topEdgeVisibleSince else { return }
        try? await Task.sleep(for: .milliseconds(UInt64(chapterArmDelay * 1000)))
        guard topEdgeVisibleSince == since, topEdgeArmedAt == nil else { return }
        withAnimation(ReaderMotion.triggerRing) { topEdgeArmedAt = .now }
        Haptics.play(.triggerArmed)
    }
    .task(id: bottomEdgeVisibleSince) {
        guard let since = bottomEdgeVisibleSince else { return }
        try? await Task.sleep(for: .milliseconds(UInt64(chapterArmDelay * 1000)))
        guard bottomEdgeVisibleSince == since, bottomEdgeArmedAt == nil else { return }
        withAnimation(ReaderMotion.triggerRing) { bottomEdgeArmedAt = .now }
        Haptics.play(.triggerArmed)
    }
}
```

Key changes vs the original:
- Removed the two raw `UIImpactFeedbackGenerator` calls at former lines 351/391 — replaced by `Haptics.play(.triggerFire)`.
- Removed the `DispatchQueue.main.asyncAfter` calls — replaced by `Task.sleep` inside `Task { @MainActor in ... }` for Swift 6 concurrency cleanliness.
- Added two `.task(id:)` blocks that drive the 0.5 s arm delay. Cancellation is automatic when `topEdgeVisibleSince` changes (exit + re-entry = strict re-arm).
- Page `onAppear` now sets `hasCompletedInitialLayout = true` — first real page render unlocks visibility observation.
- Trigger visibility callbacks are no-ops until `hasCompletedInitialLayout` is `true`, killing the "shows on load" bug.

- [ ] **Step 6: Reset arming state on chapter change**

Find the existing `.task(id: currentChapterIndex)` at line 205:

```swift
.task(id: currentChapterIndex) { await loadPages() }
```

Replace with:

```swift
.task(id: currentChapterIndex) {
    // Reset arming state so new chapter starts disarmed.
    topEdgeVisibleSince = nil
    topEdgeArmedAt = nil
    bottomEdgeVisibleSince = nil
    bottomEdgeArmedAt = nil
    hasCompletedInitialLayout = false
    prevChapterPull = 0
    nextChapterPull = 0
    prevChapterTriggered = false
    nextChapterTriggered = false
    await loadPages()
}
```

- [ ] **Step 7: Verify the app builds**

Run:

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral" && xcodebuild -scheme Astral -sdk iphonesimulator -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build 2>&1 | tail -5
```

Expected output ends with: `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp" && \
git add ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift && \
git commit -m "$(cat <<'EOF'
[ios] AST-65 armed next/prev chapter triggers with 0.5s delay

Trigger is disarmed on chapter load and on edge exit. A 0.5s visibility
timer arms the trigger — at which point the progress ring fades in and
the pull-past-260pt action works. Strict re-arm: leaving the edge and
returning restarts the timer.

hasCompletedInitialLayout gate kills the "shows on load" bug — first
real page .onAppear is what unlocks visibility observation. Raw
UIImpactFeedbackGenerator calls replaced by Haptics.play semantic events.

Closes AST-65.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Comic reader — adopt `ThrottledSetter` for scroll-driven writes

**What this lands:** smoothness #2 (throttled scroll writes).

**Files:**
- Modify: `ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift`

- [ ] **Step 1: Add the throttled setter as reader state**

Find the `@State private var hasCompletedInitialLayout = false` line (inserted in Task 7). Immediately after it, add:

```swift
    @State private var pageThrottle = ThrottledSetter<Int>(interval: 0.08)
```

- [ ] **Step 2: Route webtoon-mode page `onAppear` writes through the throttle**

Find the two `.onAppear` blocks inside `webtoonReader` (added/edited in Task 7 Step 5). Both currently look like:

```swift
.onAppear {
    hasCompletedInitialLayout = true
    currentPage = index
}
```

Replace both occurrences (local-URL ForEach and network-pages ForEach) with:

```swift
.onAppear {
    hasCompletedInitialLayout = true
    pageThrottle.set(index) { currentPage = $0 }
}
```

- [ ] **Step 3: Reset the throttle on chapter change**

In the `.task(id: currentChapterIndex)` block edited in Task 7 Step 6, add `pageThrottle.reset()` before `await loadPages()`. Replace:

```swift
.task(id: currentChapterIndex) {
    // Reset arming state so new chapter starts disarmed.
    topEdgeVisibleSince = nil
    topEdgeArmedAt = nil
    bottomEdgeVisibleSince = nil
    bottomEdgeArmedAt = nil
    hasCompletedInitialLayout = false
    prevChapterPull = 0
    nextChapterPull = 0
    prevChapterTriggered = false
    nextChapterTriggered = false
    await loadPages()
}
```

with:

```swift
.task(id: currentChapterIndex) {
    // Reset arming state so new chapter starts disarmed.
    topEdgeVisibleSince = nil
    topEdgeArmedAt = nil
    bottomEdgeVisibleSince = nil
    bottomEdgeArmedAt = nil
    hasCompletedInitialLayout = false
    prevChapterPull = 0
    nextChapterPull = 0
    prevChapterTriggered = false
    nextChapterTriggered = false
    pageThrottle.reset()
    await loadPages()
}
```

- [ ] **Step 4: Verify the app builds**

Run:

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral" && xcodebuild -scheme Astral -sdk iphonesimulator -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build 2>&1 | tail -5
```

Expected output ends with: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp" && \
git add ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift && \
git commit -m "$(cat <<'EOF'
[ios] AST-65 throttle webtoon scroll-driven currentPage writes

Per-page .onAppear writes to currentPage now go through a
ThrottledSetter<Int>(interval: 0.08). Kills the per-frame re-render
chatter on long chapters. Reset on chapter change.

Smoothness pass item #2.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: Comic reader — gesture audit

**What this lands:** smoothness #5 (gesture conflict cleanup). Confirms both long-press sites (tap zone + webtoon body) use `simultaneousGesture` — which is already true after Task 5. This task is a read-only verification plus adding one more haptic site.

**Files:**
- Modify: `ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift`

- [ ] **Step 1: Verify the two long-press sites already use `simultaneousGesture`**

Run:

```bash
grep -nE "LongPressGesture|onLongPressGesture" "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift"
```

Expected hits (line numbers may have drifted by a few after Tasks 5–8):
- `simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in longPressedPage = ...; showPageActions = true })` — tap-zone site
- `simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in toggleHUD() })` — webtoon body site
- `simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in toggleHUD() })` — paged-reader site

If any line shows `.onLongPressGesture` instead of `.simultaneousGesture(LongPressGesture...)`, convert it (but per the exploration in the design spec, all three are already correct). If all three already use `.simultaneousGesture(LongPressGesture(...))`, skip the conversion.

- [ ] **Step 2: Wire `Haptics.play(.bookmark)` into `bookmarkCurrentChapter`**

Find `bookmarkCurrentChapter()` at lines 859–876. Replace the whole function with:

```swift
private func bookmarkCurrentChapter() {
    guard let chapter = currentChapter else { return }
    if let existing = bookmarks.first(where: { $0.chapterNumber == chapter.chapterNumber }) {
        modelContext.delete(existing)
        AstralLogger.info("Bookmark removed: ch \(chapter.chapterNumber)", context: "ComicReader")
    } else {
        let bookmark = LocalBookmark(
            contentType: "comic",
            storyId: comic.id,
            chapterNumber: chapter.chapterNumber,
            pageNumber: currentPage + 1,
            heading: chapter.title ?? "Chapter \(Int(chapter.chapterNumber))"
        )
        modelContext.insert(bookmark)
        AstralLogger.info("Bookmark added: ch \(chapter.chapterNumber) page \(currentPage + 1)", context: "ComicReader")
    }
    try? modelContext.save()
    Haptics.play(.bookmark)
}
```

- [ ] **Step 3: Wire `Haptics.play(.chapterNav)` into `goToPrevChapter` and `goToNextChapter`**

Find `goToPrevChapter()` at line 821 and `goToNextChapter()` at line 829. Replace both functions with:

```swift
private func goToPrevChapter() {
    guard !isFirstChapter else { return }
    Haptics.play(.chapterNav)
    withAnimation(AstralAnimation.quick) {
        currentChapterIndex -= 1
        currentPage = 0
    }
}

private func goToNextChapter() {
    guard !isLastChapter else { return }
    Haptics.play(.chapterNav)
    withAnimation(AstralAnimation.quick) {
        currentChapterIndex += 1
        currentPage = 0
    }
}
```

- [ ] **Step 4: Wire `Haptics.play(.pageTurn)` into the bottom-bar slider**

Find the bottom-bar slider inside `bottomBar` at lines 627–635. Replace the `Slider(value:)` init with:

```swift
Slider(
    value: Binding(
        get: { Double(currentPage) },
        set: { newValue in
            let newPage = Int(newValue.rounded())
            if newPage != currentPage {
                currentPage = newPage
                Haptics.play(.pageTurn)
            }
        }
    ),
    in: 0...Double(pages.count - 1),
    step: 1
)
.tint(AstralColors.gold)
```

- [ ] **Step 5: Verify the app builds**

Run:

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral" && xcodebuild -scheme Astral -sdk iphonesimulator -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build 2>&1 | tail -5
```

Expected output ends with: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp" && \
git add ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift && \
git commit -m "$(cat <<'EOF'
[ios] AST-62 AST-65 comic reader gesture audit + haptic wiring

Wires Haptics.play semantic events at bookmark toggle, chapter nav
buttons, and slider page drag. Verifies existing long-press sites use
simultaneousGesture so the ScrollView keeps receiving scroll events.

Smoothness pass items #5 and #6 (comic reader half).

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: Comic reader — chapter crossfade + prefetch

**What this lands:** smoothness #4 (chapter transition crossfade + prefetch).

**Files:**
- Modify: `ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift`

- [ ] **Step 1: Wrap the `pageContent` call site in a crossfade transition**

Find the `pageContent` call site inside `body` at line 109:

```swift
} else {
    pageContent
}
```

Replace with:

```swift
} else {
    pageContent
        .id(currentChapterIndex)
        .transition(.opacity.animation(ReaderMotion.chapterCrossfade))
}
```

The `.id(currentChapterIndex)` forces a view-identity swap on chapter change, which the `.transition(.opacity)` then crossfades instead of hard-swapping.

- [ ] **Step 2: Add a `prefetchNextChapter` helper**

Find the `loadPages()` function at line 890. Immediately **before** `private func loadPages() async {`, insert a new helper:

```swift
/// Kicks off a best-effort network fetch of the next chapter's page list
/// and warms URLSession's cache with the first two page images. Silent on
/// failure — CachedAsyncImage handles the "never actually fetched" case.
private func prefetchNextChapter() async {
    guard currentChapterIndex + 1 < chapters.count else { return }
    let nextChapter = chapters[currentChapterIndex + 1]
    do {
        let response: PagesResponse = try await APIClient.shared.request(
            .comicPages(comicId: comic.id, chapterId: nextChapter.id)
        )
        let urls = response.pages.prefix(2).compactMap { URL(string: AppConfig.staticBaseURL + $0.filePath) }
        for url in urls {
            // Fire a raw URLSession fetch — result goes into URLCache, which
            // CachedAsyncImage reads from when the user navigates here.
            _ = try? await URLSession.shared.data(from: url)
        }
    } catch {
        // Prefetch is best-effort — no surface.
    }
}
```

**Note:** this helper references `PagesResponse`, `APIClient`, `AppConfig`, and the `.comicPages` endpoint. Before using them here, verify they exist in the repo by running:

```bash
grep -rn "PagesResponse\|case comicPages\|staticBaseURL" "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/Networking/Sources/Networking/" | head -10
```

If `PagesResponse` or `.comicPages` don't exist under those exact names, grep for the actual types the existing `loadPages()` uses (same file, same reader, around line 890+) and substitute the right names into the helper. The purpose is unchanged: fetch the next chapter's page list and prime the first two image URLs in URLCache.

- [ ] **Step 3: Kick off the prefetch at the end of `loadPages()`**

Find the last line of `loadPages()` — it ends `isLoading = false` (at the return path). Find the final `isLoading = false` line of the function (the one that actually runs when pages load successfully). Immediately after it, add:

```swift
        Task.detached(priority: .background) { await prefetchNextChapter() }
```

The detached background task keeps prefetch off the reader's main actor and lets the page render immediately.

- [ ] **Step 4: Verify the app builds**

Run:

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral" && xcodebuild -scheme Astral -sdk iphonesimulator -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build 2>&1 | tail -5
```

Expected output ends with: `** BUILD SUCCEEDED **`.

If the build fails on `.comicPages` or `PagesResponse`, stop and grep for the correct type names as noted in Step 2. Fix the helper to use the real type names, then re-run the build.

- [ ] **Step 5: Commit**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp" && \
git add ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift && \
git commit -m "$(cat <<'EOF'
[ios] AST-65 chapter crossfade + next-chapter page prefetch

pageContent is stamped with .id(currentChapterIndex) and given an
opacity transition — chapter swaps crossfade over 0.24s instead of hard
content-swap. A background prefetch warms URLCache with the first two
page images of the next chapter after the current one finishes loading.

Smoothness pass item #4 (comic reader half).

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 11: Fanfic reader — padding tighten (AST-63)

**Files:**
- Modify: `ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift`

- [ ] **Step 1: Tighten `fanficTopBar` padding**

Find the `fanficTopBar` padding block at lines 413–415:

```swift
.padding(.horizontal, 16)
.padding(.top, 56)
.padding(.bottom, 12)
```

Replace with:

```swift
.padding(.horizontal, 16)
.padding(.top, 44)
.padding(.bottom, 10)
```

- [ ] **Step 2: Tighten the `chapterFavOverlay` container padding**

Find the overlay container at lines 218–226 (the `if showReaderBar { chapterFavOverlay ... }` block). Currently:

```swift
if showReaderBar {
    chapterFavOverlay
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.top, 56)
        .padding(.trailing, 16)
        .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .topTrailing)))
        .allowsHitTesting(showReaderBar)
}
```

Change `.padding(.top, 56)` → `.padding(.top, 44)`. Final:

```swift
if showReaderBar {
    chapterFavOverlay
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.top, 44)
        .padding(.trailing, 16)
        .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .topTrailing)))
        .allowsHitTesting(showReaderBar)
}
```

- [ ] **Step 3: Shrink the `chapterFavOverlay` internals (badge circle + buttons)**

Find the `chapterFavOverlay` body at lines 337–391. Replace the full body with:

```swift
private var chapterFavOverlay: some View {
    VStack(spacing: 6) {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 48, height: 48)
            VStack(spacing: 1) {
                Text(chapterDisplayNum)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AstralColors.white)
                    .monospacedDigit()
                Capsule()
                    .fill(AstralColors.muted)
                    .frame(width: 18, height: 1.5)
                    .rotationEffect(.degrees(-45))
                Text("\(fanfic.totalChapters)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AstralColors.muted)
                    .monospacedDigit()
            }
        }

        Button {
            showChapterList = true
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 40, height: 40)
                Image(systemName: "list.bullet")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AstralColors.white)
            }
        }
        .buttonStyle(PressButtonStyle(scale: 0.88))

        Button {
            withAnimation(AstralAnimation.bouncy) {
                fanfic.isFavorite.toggle()
                try? modelContext.save()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 40, height: 40)
                Image(systemName: fanfic.isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(fanfic.isFavorite ? AstralColors.error : AstralColors.white)
                    .symbolEffect(.bounce, value: fanfic.isFavorite)
            }
        }
        .buttonStyle(PressButtonStyle(scale: 0.88))
    }
}
```

Deltas vs original:
- Outer `VStack(spacing: 8)` → `VStack(spacing: 6)`
- Chapter badge circle 58 → 48
- Chapter number font 18 → 16
- Capsule 22×1.5 → 18×1.5
- Total chapters font 13 → 12
- List / favorite buttons 44 → 40
- Icon fonts in list/favorite buttons 18 → 16

- [ ] **Step 4: Verify the app builds**

Run:

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral" && xcodebuild -scheme Astral -sdk iphonesimulator -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build 2>&1 | tail -5
```

Expected output ends with: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp" && \
git add ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift && \
git commit -m "$(cat <<'EOF'
[ios] AST-63 tighten fanfic reader chrome padding

fanficTopBar top padding 56→44, bottom 12→10. chapterFavOverlay top
padding 56→44; badge circle 58→48; list + favorite buttons 44→40;
spacing 8→6. No structural change — the top-right overlay stays; just
less visual weight.

Closes AST-63.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 12: Fanfic reader — adopt `ReaderMotion.chrome`, `pressReveal`, `Haptics`

**What this lands:** smoothness #1 and #6 on the fanfic side — matches what Task 5 did for comic.

**Files:**
- Modify: `ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift`

- [ ] **Step 1: Replace the whole-view `.onTapGesture` with `.pressReveal`**

Find the `.onTapGesture` at lines 238–242:

```swift
.onTapGesture {
    withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
        showReaderBar.toggle()
    }
}
```

Replace with:

```swift
.pressReveal {
    withAnimation(ReaderMotion.chrome) {
        showReaderBar.toggle()
    }
    Haptics.play(.chromeToggle)
}
```

- [ ] **Step 2: Swap the top-bar slide animation to `ReaderMotion.chrome`**

Find the top bar slide block at lines 208–216:

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

Replace `.animation(.easeInOut(duration: 0.22), value: showReaderBar)` with `.animation(ReaderMotion.chrome, value: showReaderBar)`. Final:

```swift
// Top bar — slides in from above with reader bar
VStack(spacing: 0) {
    fanficTopBar
    Spacer()
}
.offset(y: showReaderBar ? 0 : -110)
.opacity(showReaderBar ? 1 : 0)
.animation(ReaderMotion.chrome, value: showReaderBar)
.allowsHitTesting(showReaderBar)
```

- [ ] **Step 3: Wire `Haptics.play(.bookmark)` into the bookmark-sheet save handler**

Find the bookmark sheet `onSave` closure at lines 292–303 inside the `.sheet(isPresented: $showBookmarkSheet)` block. The closure currently inserts a `LocalBookmark` and saves the context. Immediately after `try? modelContext.save()` inside that closure, add:

```swift
Haptics.play(.bookmark)
```

Final:

```swift
.sheet(isPresented: $showBookmarkSheet) {
    FanficBookmarkSheet(
        paragraphText: bookmarkParagraphIndex.flatMap { paragraphs.indices.contains($0) ? paragraphs[$0] : nil } ?? "",
        chapterTitle: currentChapter.title,
        chapterNumber: currentChapter.chapterNumber,
        wordOffset: bookmarkParagraphIndex.flatMap { wordOffsetForParagraph($0) } ?? 0,
        onSave: { selectedText, heading, wordOffset in
            let bookmark = LocalBookmark(
                contentType: "fanfic",
                storyId: fanfic.id,
                chapterNumber: currentChapter.chapterNumber,
                wordOffset: wordOffset,
                selectedText: selectedText,
                heading: heading
            )
            modelContext.insert(bookmark)
            try? modelContext.save()
            Haptics.play(.bookmark)
        }
    )
    .presentationDetents([.medium])
}
```

- [ ] **Step 4: Wire `Haptics.play(.chapterNav)` into the chapter navigation footer buttons**

Find the `chapterNavigationFooter` (grep for `chapterNavigationFooter` in `FanficReaderView.swift`). Two `Button` blocks navigate to previous / next chapter via `navigateTo(...)`. Add `Haptics.play(.chapterNav)` inside each button's action, immediately before the `navigateTo` call.

Run this grep first to locate exact lines:

```bash
grep -n "chapterNavigationFooter\|navigateTo(" "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift"
```

At each `Button { ... navigateTo(target) ... }` that represents a chapter-nav button (skip any inside `horizontalPage` scroll observers), insert `Haptics.play(.chapterNav)` as the first line of the action closure.

If `chapterNavigationFooter` does not exist (grep returns zero hits), the footer is inlined under a different name — search for `previousChapter` and `nextChapter` button call sites in the same file and add the haptic there.

- [ ] **Step 5: Verify the app builds**

Run:

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral" && xcodebuild -scheme Astral -sdk iphonesimulator -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build 2>&1 | tail -5
```

Expected output ends with: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp" && \
git add ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift && \
git commit -m "$(cat <<'EOF'
[ios] AST-62 AST-63 fanfic reader touch-down chrome + unified motion

Whole-view tap migrates to .pressReveal so chrome reveals on touch-down.
Chrome animation standardized on ReaderMotion.chrome (replaces inline
0.42/0.82 spring and 0.22s easeInOut). Haptics wired at chrome toggle,
bookmark save, and chapter nav buttons.

Smoothness pass items #1 and #6 (fanfic half).

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 13: Fanfic reader — adopt `ThrottledSetter` for `scrollOffsetPercent`

**Files:**
- Modify: `ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift`

- [ ] **Step 1: Add the throttled setter as reader state**

Find the block of `@State` declarations. Immediately after `@State private var horizontalPage: String? = "current"` at line 40, add:

```swift
    @State private var scrollPercentThrottle = ThrottledSetter<Double>(interval: 0.08)
```

- [ ] **Step 2: Route per-paragraph `onAppear` writes through the throttle**

Find the per-paragraph `.onAppear` block at lines 125–130:

```swift
.onAppear {
    guard hasRestoredScroll else { return }
    if paragraphs.count > 1 {
        fanfic.scrollOffsetPercent = Double(index) / Double(paragraphs.count - 1)
    }
}
```

Replace with:

```swift
.onAppear {
    guard hasRestoredScroll else { return }
    if paragraphs.count > 1 {
        let pct = Double(index) / Double(paragraphs.count - 1)
        scrollPercentThrottle.set(pct) { fanfic.scrollOffsetPercent = $0 }
    }
}
```

- [ ] **Step 3: Reset the throttle on chapter change**

Find the `.task(id: currentChapter.id)` block at line 243:

```swift
.task(id: currentChapter.id) { await loadChapter() }
```

Replace with:

```swift
.task(id: currentChapter.id) {
    scrollPercentThrottle.reset()
    hasRestoredScroll = false
    await loadChapter()
}
```

Note: `hasRestoredScroll = false` is already handled elsewhere for scroll restore, but setting it here ensures the restore path re-runs for the new chapter. If a build error flags duplicate assignment, remove this line.

- [ ] **Step 4: Verify the app builds**

Run:

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral" && xcodebuild -scheme Astral -sdk iphonesimulator -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build 2>&1 | tail -5
```

Expected output ends with: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp" && \
git add ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift && \
git commit -m "$(cat <<'EOF'
[ios] AST-65 throttle fanfic per-paragraph scroll progress writes

Per-paragraph .onAppear writes to fanfic.scrollOffsetPercent now go
through a ThrottledSetter<Double>(interval: 0.08). Kills progress-bar
write chatter on long chapters. Reset on chapter change.

Smoothness pass item #2 (fanfic half).

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 14: Fanfic reader — chapter crossfade + prefetch

**Files:**
- Modify: `ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift`

- [ ] **Step 1: Add `id + transition` to the horizontal chapter pager's current chapter view**

Find the current-chapter `ScrollViewReader` block at lines 75–166 inside the horizontal paging `LazyHStack`. The outer `ScrollViewReader { ... }.containerRelativeFrame([.horizontal, .vertical]).id("current")` wraps the whole vertical chapter content.

Immediately **after** `.id("current")` (line 166), add:

```swift
.id(currentChapter.id)
.transition(.opacity.animation(ReaderMotion.chapterCrossfade))
```

Note: the outer `LazyHStack` already uses `.id("current")` for `scrollPosition` tracking. The extra `.id(currentChapter.id)` sits on the same view and drives SwiftUI identity for the crossfade. Both work — the inner paging identity stays `"current"`; the view-render identity becomes the chapter ID.

If SwiftUI complains about duplicate `.id` calls (it shouldn't — they're chained modifiers, not Hashable conflicts), split the inner `ScrollViewReader { ... }` content: wrap it in `Group { ... }.id(currentChapter.id).transition(.opacity.animation(ReaderMotion.chapterCrossfade))` before the `.containerRelativeFrame` + `.id("current")`.

- [ ] **Step 2: Add a `prefetchAdjacentChapters` helper**

Find `loadChapter()` at line 555. Immediately **before** `private func loadChapter() async {`, insert:

```swift
/// Kicks off background fetches of the immediately-previous and
/// immediately-next chapter content. Success primes the HTTP cache;
/// failures are silent (prefetch is best-effort).
private func prefetchAdjacentChapters() async {
    let candidates = [previousChapter, nextChapter].compactMap { $0 }
    await withTaskGroup(of: Void.self) { group in
        for chapter in candidates {
            group.addTask {
                let _: FanficChapterResponse? = try? await APIClient.shared.request(
                    .fanficChapter(fanficId: fanfic.id, chapterId: chapter.id)
                )
            }
        }
    }
}
```

**Note:** this references `FanficChapterResponse` and `.fanficChapter(fanficId:chapterId:)`. These already exist — `loadChapter()` uses them directly (see line 589). Type names should drop in correctly.

- [ ] **Step 3: Kick off the prefetch at the end of `loadChapter()`**

Find the successful load path in `loadChapter()`. The function sets `isLoading = false` in multiple branches (local file, network success). Find the final common exit path — there's a line in the network path where `isLoading = false` executes after content is assigned.

At the **bottom of the function body** (just before the final closing brace of `loadChapter()`), add:

```swift
    Task.detached(priority: .background) { await prefetchAdjacentChapters() }
```

This fires regardless of which branch succeeded (local file or network). If `loadChapter()` has an early return for `previewContent`, the prefetch shouldn't fire there — verify by running the function top-to-bottom. If any `return` path skips this line, move the prefetch call up to each successful exit point individually.

Simpler alternative if the control flow is messy: add the prefetch inside the `onAppear` handler of the reader body, guarded by `!isLoading`. But the preferred place is at the bottom of `loadChapter()`.

- [ ] **Step 4: Verify the app builds**

Run:

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral" && xcodebuild -scheme Astral -sdk iphonesimulator -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build 2>&1 | tail -5
```

Expected output ends with: `** BUILD SUCCEEDED **`.

If the build fails on `.fanficChapter`, grep for the actual endpoint name:

```bash
grep -rn "case fanficChapter" "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/Networking/"
```

Adjust the helper to match.

- [ ] **Step 5: Commit**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp" && \
git add ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift && \
git commit -m "$(cat <<'EOF'
[ios] AST-65 fanfic chapter crossfade + adjacent-chapter prefetch

Current chapter view gets a chapter-id-keyed .transition so chapter
swaps crossfade over 0.24s instead of hard-swapping text content.
Background task prefetches the adjacent (prev + next) chapters' text
after the current chapter loads — primes the HTTP cache for instant
chapter nav.

Smoothness pass item #4 (fanfic half).

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 15: Manual QA pass + CHANGELOG + PR

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Run the final full build**

Run:

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral" && xcodebuild -scheme Astral -sdk iphonesimulator -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 2: Run the DesignSystem tests one more time**

Run:

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem" && swift test 2>&1 | tail -10
```

Expected: all 6 ThrottledSetter tests pass.

- [ ] **Step 3: Manual QA on simulator**

Open the project in Xcode: `open "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Astral.xcodeproj"`. Run the Astral target on the simulator. Walk the following script and confirm each step.

1. Open a comic → tap the center third → chrome reveals the instant your cursor/finger presses, before release. (AST-62)
2. Tap the `"N / M"` page indicator in the bottom bar → a dropdown Menu appears with every page number. Select page 15 → reader animates to page 15 with a light haptic. (AST-64)
3. Switch the reader to webtoon mode via settings. Scroll to the last page. Observe the ring is **not** visible immediately. Wait 0.5 s → subtle haptic tick + ring fades in. Pull past ~260 pt → ring fills, medium haptic, chapter advances with a crossfade. (AST-65 + smoothness #4)
4. Back one chapter. Scroll *past* the first page (so top edge leaves viewport). Then scroll back up. The 0.5 s arm timer should restart (strict re-arm). Confirm the ring stays hidden for 0.5 s on the re-entry.
5. Open a fanfic. Tap anywhere. The top bar should be visibly tighter vertically than before; the chapter badge on the top-right should be a 48 pt circle (previously 58 pt). (AST-63)
6. In the fanfic, scroll a long chapter. The golden progress bar at the top should update smoothly without stutter. (Smoothness #2)
7. In the fanfic, tap Next Chapter in the footer. Content should crossfade, not hard-swap. (Smoothness #4)
8. Confirm haptic feedback fires on: chrome toggle, page Menu selection, slider page drag, bookmark save, chapter nav button, trigger arm, trigger fire. (Smoothness #6 — run on a physical device if possible; simulator haptics are silent.)
9. In webtoon mode, long-press anywhere in the page content — scroll should still work immediately after the long-press completes (no gesture deadlock). (Smoothness #5)

If any step fails, fix the relevant file and re-commit with a `[ios] fix:` prefix referencing the ticket(s) affected. Re-run the build before returning to QA.

- [ ] **Step 4: Add a CHANGELOG entry**

Open `CHANGELOG.md` at the repo root. The file is ordered most-recent-first. Immediately after the top-of-file header (find the first `## ` heading — the most recent release section), insert a new entry:

```markdown
## feature/ast-reader-smoothness-pass — 2026-04-22

- [ios] Reader smoothness pass: touch-down chrome reveal, tappable page Menu, armed next-chapter trigger with 0.5s delay, unified reader motion + haptics, throttled scroll writes, chapter crossfade + prefetch, tightened fanfic chrome padding. Closes AST-62, AST-63, AST-64, AST-65.
```

Exact placement depends on the current top of `CHANGELOG.md`. Read the first 30 lines and place the new entry at the correct most-recent-first position.

- [ ] **Step 5: Commit the CHANGELOG**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp" && \
git add CHANGELOG.md && \
git commit -m "$(cat <<'EOF'
[ios] AST-62 AST-63 AST-64 AST-65 add CHANGELOG entry

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 6: Push the branch and open the PR**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp" && \
git push -u origin feature/ast-reader-smoothness-pass
```

Then create the PR (body uses four `Fixes` lines so all four Linear issues auto-close on merge):

```bash
gh pr create \
  --base development \
  --head feature/ast-reader-smoothness-pass \
  --title "[ios] Reader smoothness pass — AST-62 AST-63 AST-64 AST-65" \
  --body "$(cat <<'EOF'
## Summary

- Touch-down chrome reveal in both readers (AST-62)
- Fanfic reader chrome padding tightened, matches comic density (AST-63)
- Tappable page Menu replaces static indicator in comic reader (AST-64)
- Armed next-chapter trigger state machine — 0.5s delay, strict re-arm, no "shows on load" bug (AST-65)
- Six-item smoothness pass: unified motion tokens, centralized haptics, throttled scroll writes, chapter crossfade + prefetch, gesture audit

Spec: [docs/superpowers/specs/2026-04-22-reader-smoothness-pass-design.md](docs/superpowers/specs/2026-04-22-reader-smoothness-pass-design.md)

Fixes AST-62
Fixes AST-63
Fixes AST-64
Fixes AST-65

## Test plan

- [ ] Simulator build passes (verified in CI)
- [ ] DesignSystem package tests pass (`swift test` — 6 ThrottledSetter tests)
- [ ] Comic reader: center tap reveals chrome on touch-down
- [ ] Comic reader: page Menu drops down, jumps to selected page
- [ ] Comic reader webtoon: trigger ring hidden on load; arms after 0.5s edge visibility; strict re-arm on re-entry
- [ ] Fanfic reader: top bar padding visibly tighter; chapter badge 48pt
- [ ] Both readers: chrome motion identical across tabs
- [ ] Both readers: chapter transitions crossfade, don't flash
- [ ] Physical device: haptic feedback fires at all six sites (chrome toggle, page turn, chapter nav, trigger arm, trigger fire, bookmark)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Return the PR URL in the final status message.

---

## Self-Review

**Spec coverage:**
- AST-62 touch-down chrome reveal → Task 4 (modifier), Task 5 (comic), Task 12 (fanfic) ✓
- AST-63 fanfic padding tighten → Task 11 ✓
- AST-64 page Menu → Task 6 ✓
- AST-65 arming state machine → Task 7 (core logic), Task 8 (throttle), Task 10 (crossfade + prefetch on comic), Task 14 (fanfic half) ✓
- Smoothness #1 unified chrome motion → Task 2 (token), Task 5 (comic adoption), Task 12 (fanfic adoption) ✓
- Smoothness #2 throttled scroll writes → Task 1 (helper + tests), Task 8 (comic), Task 13 (fanfic) ✓
- Smoothness #3 tap latency → covered by AST-62 Task 5/12 ✓
- Smoothness #4 chapter crossfade + prefetch → Task 10 (comic), Task 14 (fanfic) ✓
- Smoothness #5 gesture audit → Task 9 (comic verify + haptic wiring) + already-correct fanfic paragraph long-press (kept as-is) ✓
- Smoothness #6 haptics → Task 3 (helper), Task 5 (chrome), Task 9 (comic — bookmark/chapter nav/slider), Task 12 (fanfic — chrome/bookmark/chapter nav) ✓
- Manual QA + PR → Task 15 ✓

**Placeholder scan:** No TBD / TODO / "similar to" references. Each task shows exact before/after code.

**Type consistency:** `ThrottledSetter<T: Equatable>` used with `<Int>` (Task 8) and `<Double>` (Task 13) — both satisfied. `HapticEvent` cases `.chromeToggle / .pageTurn / .chapterNav / .triggerArmed / .triggerFire / .bookmark` — all six referenced in subsequent tasks. `ReaderMotion.chrome / .pageTurn / .chapterCrossfade / .triggerRing` — all four referenced. `PrevChapterTrigger` / `NextChapterTrigger` get matching new params `onVisibilityChange` + `isArmed` in Task 7; call sites updated in the same task. `pressReveal` modifier used in Task 5 (comic) and Task 12 (fanfic). `prefetchNextChapter` (comic, Task 10) and `prefetchAdjacentChapters` (fanfic, Task 14) — distinct names, no collision.

**Known fuzzy spots to flag for the implementer:**
- Task 10 Step 2: `PagesResponse` / `.comicPages` type names aren't confirmed. Verification step included.
- Task 12 Step 4: `chapterNavigationFooter` may be inlined under a different name; grep provided to locate.
- Task 14 Step 3: `loadChapter()` has multiple success paths; implementer needs to place prefetch correctly — fallback guidance provided.

---

**Plan complete and saved to `docs/superpowers/plans/2026-04-22-reader-smoothness-pass.md`.**
