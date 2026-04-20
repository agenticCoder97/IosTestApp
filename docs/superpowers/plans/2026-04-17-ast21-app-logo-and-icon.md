# AST-21 — App Logo and Icon: Implementation Plan

**Date**: 2026-04-17
**Spec**: `docs/superpowers/specs/2026-04-17-ast21-app-logo-and-icon-design.md`
**Branch**: `feature/ast-21-app-logo-and-icon`
**Linear**: AST-21

---

## Prerequisite (Handoff — User Action Required)

Before steps 3–4 can be completed, the user must produce three 1024×1024 PNG files in Figma following the spec:

- `app_icon_light_1024.png` — `#F0F0F8` background, gold gradient "A"
- `app_icon_dark_1024.png` — `#0A0A0B` background, gold gradient "A", radial glow
- `app_icon_tinted_1024.png` — `#000000` background, white "A" (flat, no gradient)

Drop them into:
`ios/Astral/Resources/Assets.xcassets/AppIcon.appiconset/`

Steps 1, 2, 5, 6 can be done without the PNGs.

---

## Tasks

### Task 1 — Extend `AstralColors` with three new tokens

**File**: `ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Colors.swift`

Add inside the `AstralColors` enum:

```swift
// MARK: - Blue Accent
public static let blue = Color(hex: 0x5C9DFF)

// MARK: - Gold Scale
public static let goldLight = Color(hex: 0xE8C96A)
public static let goldDark  = Color(hex: 0x8A6A28)
```

Also update `RootView.swift` to replace:
```swift
private let blueColor = Color(hex: 0x5C9DFF)
```
with:
```swift
private let blueColor = AstralColors.blue
```

**Commit**: `[ios] AST-21 add blue, goldLight, goldDark tokens to AstralColors`

---

### Task 2 — Create `AstralLogo` SwiftUI component

**File** (new): `ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/AstralLogo.swift`

Implement `AstralLogo` exactly as sketched in the spec:
- `AstralLogoSize` enum (`.small` / `.medium` / `.large`)
- `showMark: Bool` parameter
- `foregroundStyle` using `LinearGradient` from `AstralColors.goldLight` to `AstralColors.goldDark`
- `sparkle` SF Symbol when `showMark == true`
- `#Preview` showing all three sizes on dark background

No XcodeGen changes needed — the file goes into the existing `Components/` directory which is already swept by the package source glob.

**Commit**: `[ios] AST-21 add AstralLogo SwiftUI component to DesignSystem`

---

### Task 3 — Add icon PNG assets (USER HANDOFF)

**Action**: User places the three Figma-exported PNGs into:
```
ios/Astral/Resources/Assets.xcassets/AppIcon.appiconset/
  app_icon_light_1024.png
  app_icon_dark_1024.png
  app_icon_tinted_1024.png
```

The existing `app_icon_1024.png` is kept in place as fallback (or replaced by `app_icon_light_1024.png` if the user prefers to clean up).

**Blocker**: Agent cannot produce raster art. User must complete this step.

---

### Task 4 — Update `AppIcon.appiconset/Contents.json`

**File**: `ios/Astral/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`

Replace current content with the three-variant structure from the spec:

```json
{
  "images": [
    {
      "filename": "app_icon_dark_1024.png",
      "idiom": "universal",
      "platform": "ios",
      "size": "1024x1024",
      "appearances": [
        { "appearance": "luminosity", "value": "dark" }
      ]
    },
    {
      "filename": "app_icon_tinted_1024.png",
      "idiom": "universal",
      "platform": "ios",
      "size": "1024x1024",
      "appearances": [
        { "appearance": "luminosity", "value": "tinted" }
      ]
    },
    {
      "filename": "app_icon_light_1024.png",
      "idiom": "universal",
      "platform": "ios",
      "size": "1024x1024"
    }
  ],
  "info": {
    "author": "xcode",
    "version": 1
  }
}
```

**Depends on**: Task 3 (PNGs must exist before Xcode will build cleanly).

**Commit**: `[ios] AST-21 update AppIcon Contents.json for light/dark/tinted variants`

---

### Task 5 — Replace inline Text("Astral") in landing view with AstralLogo (CONFIRM WITH USER)

**File**: `ios/Astral/App/RootView.swift`

In `MorphLandingView.body`, replace:
```swift
Text("Astral")
    .font(.system(size: 42, weight: .heavy, design: .rounded))
    .foregroundStyle(AstralColors.white)
    .blur(radius: titleBlur)
    .scaleEffect(titleScale)
    .opacity(titleOpacity)
```
with:
```swift
AstralLogo(size: .large, showMark: false)
    .blur(radius: titleBlur)
    .scaleEffect(titleScale)
    .opacity(titleOpacity)
```

The `blur`, `scaleEffect`, and `opacity` modifiers attach to `AstralLogo` as a `View` — the Phase 3 animation sequence is unchanged.

**Note**: `AstralLogoSize.large` uses `fontSize: 48`. The current inline text uses size 42. The difference is intentional (48 is more impactful at the landing stage). If the user prefers the 42pt size, add a custom size or adjust the `.large` constant before committing.

**Confirm with user before implementing** — the landing animation is sensitive and this changes visible output.

**Commit**: `[ios] AST-21 replace inline Astral title text with AstralLogo component`

---

### Task 6 — Manual Verification

Verify on Simulator (iOS 17.2 minimum) and physical device:

- [ ] Landing screen renders `AstralLogo` correctly — gold gradient visible, blur-in animation plays as before.
- [ ] Reduced-motion path (`applyReducedMotionState`) still works (no crash, logo appears instantly).
- [ ] Home screen icon shows the new dark variant on dark wallpaper.
- [ ] On iOS 18 device/simulator: toggle Settings > Accessibility > Display & Text Size > App Icon Shape to confirm tinted variant is picked up.
- [ ] Light mode icon variant correct under Settings > Display & Brightness > Light.
- [ ] No build warnings about missing icon sizes (Xcode 16 only needs the 1024 entry for modern targets).

---

## Estimated Effort

| Task | Owner | Effort |
|------|-------|--------|
| 1 — Palette tokens | Agent | 15 min |
| 2 — AstralLogo component | Agent | 30 min |
| 3 — Icon PNGs | User (Figma) | 1–2 hrs |
| 4 — Contents.json | Agent | 10 min |
| 5 — Landing wire-in | Agent (confirm first) | 15 min |
| 6 — Manual QA | User | 30 min |

---

## Files Touched

```
ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Colors.swift
ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/AstralLogo.swift   (new)
ios/Astral/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json
ios/Astral/Resources/Assets.xcassets/AppIcon.appiconset/app_icon_light_1024.png     (user adds)
ios/Astral/Resources/Assets.xcassets/AppIcon.appiconset/app_icon_dark_1024.png      (user adds)
ios/Astral/Resources/Assets.xcassets/AppIcon.appiconset/app_icon_tinted_1024.png    (user adds)
ios/Astral/App/RootView.swift                                                        (after confirm)
```
