# AST-21 — App Logo and Icon: Design Specification

**Date**: 2026-04-17
**Author**: Design Architect (autonomous agent)
**Status**: Approved for implementation
**Linear**: [AST-21](https://linear.app/nnetraganti/project/astral-8efbeb753255)

---

## Summary

Astral's home-screen icon is a single unstyled 1024×1024 PNG with no light/dark/tinted variants. There is no reusable logo component — the landing screen renders "Astral" as a plain `Text` node. This spec defines:

1. A **monogram icon** direction (stylized "A" on a dark background with gold accent).
2. A **SwiftUI `AstralLogo` component** replacing inline text in the landing view and reusable wherever a brand mark is needed.
3. Three new **palette tokens** (`blue`, `goldDark`, `goldLight`).
4. The **asset pipeline** for generating Light, Dark, and Tinted icon PNGs.

---

## Goals

- Intentional, legible home-screen icon at all sizes (20pt–1024pt).
- Support iOS 18+ Light / Dark / Tinted icon variants.
- Reusable SwiftUI logo component in DesignSystem (no raster image for the wordmark).
- Consistent brand palette — eliminate the lone hardcoded `#5C9DFF` hex in `RootView.swift`.

## Non-Goals

- This PR does not produce final production-ready icon PNGs (see Handoff Dependencies).
- No App Store submission changes in this PR.
- No marketing assets, splash screens beyond the existing landing animation.
- No custom font — system rounded font is intentional.

---

## Icon Design Direction

### Chosen: Monogram "A" on Dark Background

A bold, rounded uppercase "A" centred on `AstralColors.background` (`#0A0A0B`), filled with a vertical gold gradient from `goldLight` (`#E8C96A`) at the top to `goldDark` (`#8A6A28`) at the bottom. A subtle radial glow in gold sits behind the letterform at ~15% opacity.

**Rationale**:
- The landing screen already uses `.system(size:42, weight:.heavy, design:.rounded)` for "Astral". The icon letter mirrors that typographic voice.
- A single letterform reads clearly at 20pt (Notification Centre) and 60pt (Spotlight) — an orb-based mark loses legibility below 40pt.
- Monograms are the dominant pattern for dark-mode-first apps (Linear, Arc, Craft, Bear).
- Requires only one illustrator/Figma session; the form is constrained enough that the user can produce it without a designer.

**Rejected alternative — abstract orb mark**:
The two-orb motif from the landing animation is visually rich but requires careful anti-aliasing at small sizes. Deferred to a future brand refresh if desired.

### Appearance Variants

| Variant | Background | "A" Fill | File name |
|---------|-----------|----------|-----------|
| Light | `#F0F0F8` (white) | Gold gradient (`#8A6A28` → `#E8C96A`) | `app_icon_light_1024.png` |
| Dark | `#0A0A0B` (background) | Gold gradient | `app_icon_dark_1024.png` |
| Tinted | `#000000` solid | White `#FFFFFF` letterform (grayscale template) | `app_icon_tinted_1024.png` |

iOS 18 tinted icons: system overlays the user's chosen tint colour on the grayscale template; the white "A" becomes the lighter region and the black background the darker.

The existing `app_icon_1024.png` becomes the **fallback** (used on iOS < 18 and as the primary universal entry).

---

## Logo Design Direction

### Chosen: SwiftUI `AstralLogo` component in DesignSystem

A code-rendered mark that composes:
1. The word "Astral" in `.system(weight: .heavy, design: .rounded)`.
2. Optional SF Symbol accent or geometric micro-mark (configurable via `showMark` parameter).
3. Size controlled via a `size` parameter (`.small`, `.medium`, `.large`) mapping to font sizes 20 / 32 / 48.
4. Color adapts to `colorScheme` — gold on dark, gold-dark on light.

**Rationale**:
- Zero raster bloat; scales perfectly to any container.
- Already partially expressed in `RootView`'s `Text("Astral")` — this extracts it into a proper, tested, reusable component.
- Animatable: future work can apply `blur`, `scaleEffect`, or `opacity` modifiers without changing the component internals (the landing view's Phase 3 title reveal already does this).
- Tradeoff accepted: screenshots for App Store metadata must be taken from a live simulator run, not from a static file export.

### Sketched SwiftUI Implementation

```swift
// DesignSystem/Components/AstralLogo.swift

import SwiftUI

public enum AstralLogoSize {
    case small   // 20pt — tab bar, About sheet header
    case medium  // 32pt — onboarding, settings header
    case large   // 48pt — landing screen (replaces inline Text("Astral"))

    var fontSize: CGFloat {
        switch self {
        case .small:  return 20
        case .medium: return 32
        case .large:  return 48
        }
    }

    var iconSize: CGFloat { fontSize * 0.85 }
}

/// Brand wordmark for Astral. Code-rendered; no raster asset required.
///
/// Usage:
///   AstralLogo(size: .large)
///   AstralLogo(size: .medium, showMark: false)
public struct AstralLogo: View {
    public let size: AstralLogoSize
    public var showMark: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    public init(size: AstralLogoSize = .medium, showMark: Bool = true) {
        self.size = size
        self.showMark = showMark
    }

    private var textFill: LinearGradient {
        LinearGradient(
            colors: [AstralColors.goldLight, AstralColors.goldDark],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    public var body: some View {
        HStack(spacing: size.fontSize * 0.2) {
            if showMark {
                // Micro star/orb mark — four-pointed using SF Symbol
                Image(systemName: "sparkle")
                    .font(.system(size: size.iconSize, weight: .heavy))
                    .foregroundStyle(textFill)
            }

            Text("Astral")
                .font(.system(size: size.fontSize, weight: .heavy, design: .rounded))
                .foregroundStyle(textFill)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 24) {
        AstralLogo(size: .large)
        AstralLogo(size: .medium)
        AstralLogo(size: .small, showMark: false)
    }
    .padding(32)
    .background(AstralColors.background)
}
```

**Notes on the sketch**:
- The `sparkle` SF Symbol (4-pointed star) echoes the "astral / celestial" theme without requiring custom art.
- `showMark: false` produces a clean wordmark for narrow contexts (nav bars, small headers).
- The gradient is defined inline from tokens; it will automatically pick up any future token changes.
- If the user dislikes `sparkle`, the mark can be swapped to `star.fill`, `moon.stars.fill`, or a custom `Shape` — the parameter isolation means zero other-call-site impact.

---

## Palette Additions

Add to `Colors.swift`:

```swift
// MARK: - Blue Accent (fanfic theme — was hardcoded in RootView)
public static let blue = Color(hex: 0x5C9DFF)

// MARK: - Gold Scale (icon gradient + logo fill)
public static let goldLight = Color(hex: 0xE8C96A)   // ~+25% brightness vs gold
public static let goldDark  = Color(hex: 0x8A6A28)   // ~-35% brightness vs gold
```

`AstralColors.blue` should also replace the inline `Color(hex: 0x5C9DFF)` in `RootView.swift` as a cleanup step.

---

## Icon Asset Pipeline

### Recommended: Figma → PNG export

1. Open Figma. Create a 1024×1024 frame.
2. Set fill to `#0A0A0B` (dark variant). Draw the rounded "A" using Inter Heavy or SF Pro Rounded Bold as the source letterform (outline the text before export).
3. Apply a vertical linear gradient fill: top stop `#E8C96A` (goldLight), bottom stop `#8A6A28` (goldDark).
4. Add a radial gradient circle at letter centroid, radius ~400pt, fill `#C9A84C` at 15% opacity (ambient glow layer).
5. Export three frames as PNG at 1× (1024px):
   - `app_icon_dark_1024.png` — dark background, gold "A"
   - `app_icon_light_1024.png` — `#F0F0F8` background, gold "A"
   - `app_icon_tinted_1024.png` — pure black background, white "A", no gradient

6. Drop all three into `ios/Astral/Resources/Assets.xcassets/AppIcon.appiconset/`.
7. Rename the current `app_icon_1024.png` to `app_icon_fallback_1024.png` or replace it with the dark variant.

### Alternative (not recommended): SF Symbols render script

A Swift script could rasterise an SF Symbol into a PNG at build time. Complexity is disproportionate for a one-time deliverable; Figma is faster and gives pixel-perfect control over the gradient.

---

## AppIcon.appiconset — Contents.json Target Structure

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

Note: The entry without an `appearances` key is the fallback / light variant. iOS 18 picks the matching appearance slot; iOS 17 and below use the fallback.

---

## Dark Mode and Tinted Variant Specs

| Property | Light | Dark | Tinted |
|----------|-------|------|--------|
| Background | `#F0F0F8` | `#0A0A0B` | `#000000` |
| "A" fill | Gold gradient | Gold gradient | `#FFFFFF` (flat, no gradient) |
| Glow layer | None (would wash out on light bg) | `#C9A84C` at 15% | None |
| Corner mask | iOS applies automatically | iOS applies automatically | iOS applies automatically |

---

## Usage — Where AstralLogo Appears

| Location | Size | showMark |
|----------|------|---------|
| Landing screen (Phase 3 title) | `.large` | `true` (optional) |
| About / Settings sheet header | `.medium` | `true` |
| Tab bar branding (if ever added) | `.small` | `false` |
| Onboarding (future) | `.large` | `true` |

The landing screen (`MorphLandingView`) replaces its `Text("Astral")` with `AstralLogo(size: .large, showMark: false)` to preserve the existing blur-in / scale animation (the modifiers attach to `AstralLogo` transparently since it is a plain `View`).

---

## Decisions Made Autonomously

| Decision | Rationale |
|----------|-----------|
| Monogram "A" chosen over orb mark | Better small-size legibility; mirrors existing typographic voice |
| SwiftUI component over SVG/PNG wordmark | Zero raster bloat; animatable; token-driven |
| `sparkle` SF Symbol as micro-mark | On-theme (celestial); no custom art; can be swapped |
| Three palette tokens added | `blue` was already in use unharvested; `goldLight`/`goldDark` required for icon gradient |
| Figma pipeline over build-time script | Simpler; one-time deliverable; predictable output |
| iOS 18 three-variant structure | Future-proof; tinted variant costs one extra PNG |
| Landing text replaced with `AstralLogo` | Consistency; reuse; user to confirm before implementation (step 5 in plan) |
