# DesignSystem Package

> Color tokens, typography, animations, and reusable UI components. Depends on Core.

## Entities

### Design Tokens

| Name | Type | File | Description |
|------|------|------|-------------|
| AstralColors | Static colors | `Packages/DesignSystem/.../Colors.swift` | background #0A0A0B, surface #141416, elevated #1E1E22, border #2A2A30, muted #6B6B7A, body #C8C8D4, white #F0F0F8, gold #C9A84C, error (red) |
| AstralTypography | Font scale | `Packages/DesignSystem/.../Typography.swift` | Inter Variable font. display 34pt, title 22pt, headline 18pt, body 16pt, caption 12pt |
| AstralAnimations | Motion presets | `Packages/DesignSystem/.../AstralAnimations.swift` | Sidebar spring, tab crossfade, reader HUD, pulse animation |

### Components

| Name | File | Description |
|------|------|-------------|
| GoldButton | `Components/GoldButton.swift` | Primary CTA with gold gradient background |
| ProgressBarView | `Components/ProgressBarView.swift` | Reading progress indicator bar |
| EmptyStateView | `Components/EmptyStateView.swift` | Empty library placeholder (icon + title + subtitle) |
| ToastView | `Components/ToastView.swift` | Transient notification overlay (success/error) |
| AstralSearchBar | `Components/AstralSearchBar.swift` | Custom search input with clear button |
| BackendStatusBanner | `Components/BackendStatusBanner.swift` | Offline/unreachable warning banner with retry |
| PlaceholderThumbnail | `Components/PlaceholderThumbnail.swift` | Generic thumbnail when no image available |
| StatusBadge | `Components/StatusBadge.swift` | Colored status indicator (complete, partial, failed) |
| StoryThumbnail | `Components/StoryThumbnail.swift` | Async thumbnail using AppConfig.staticBaseURL + path |
| DebugConsoleView | `Components/DebugConsoleView.swift` | Debug overlay for development |
| ContentBlocker | `ContentBlocker.swift` | WKContentRuleList for ad blocking in WKWebView |

### Modifiers

| Name | File | Description |
|------|------|-------------|
| CardModifier | `Modifiers/CardModifier.swift` | Card styling: elevated background, rounded corners, border |

## Design Principles

- **Dark-first**: All colors designed for dark backgrounds (#0A0A0B base)
- **Gold accent**: Primary actions and highlights use #C9A84C gold
- **Token-only**: No hardcoded hex values in feature modules — all colors from AstralColors
- **Inter font**: Variable weight Inter loaded from bundle Resources
