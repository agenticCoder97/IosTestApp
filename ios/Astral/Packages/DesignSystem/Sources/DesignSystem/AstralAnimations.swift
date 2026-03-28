import SwiftUI

// MARK: - Animation Vocabulary

/// Named animation constants for Astral — the single source of truth for timing and spring physics.
/// Import DesignSystem and reference these rather than hardcoding .easeInOut(duration: x) throughout the codebase.
public enum AstralAnimation {

    // MARK: Springs

    /// Fast, decisive snap for toggles and binary state flips.
    /// Use: sidebar rows, icon toggles, quick boolean changes.
    public static let snappy = Animation.spring(response: 0.3, dampingFraction: 0.7)

    /// Satisfying overshoot for delightful moments — hearts, badges, confirmations.
    /// The slight bounce communicates "something good happened."
    public static let bouncy = Animation.spring(response: 0.35, dampingFraction: 0.55)

    /// Smooth spring for content transitions and structural changes.
    /// Use: section expand/collapse, panel slides, content swaps.
    public static let smooth = Animation.spring(response: 0.42, dampingFraction: 0.82)

    /// Sidebar overlay spring — preserves the established navigation feel.
    public static let sidebar = Animation.spring(duration: 0.35, bounce: 0.15)

    // MARK: Easing

    /// Sub-200ms HUD and reader micro-interactions.
    public static let micro = Animation.easeInOut(duration: 0.15)

    /// Standard short interaction response.
    public static let quick = Animation.easeInOut(duration: 0.2)

    /// Content appear / gentle transitions.
    public static let standard = Animation.easeOut(duration: 0.3)

    // MARK: Stagger

    /// Per-item delay for list or grid stagger animations.
    /// Caps at `index % 6` so items scrolled to later don't wait an eternity.
    public static func stagger(index: Int, base: Double = 0.045) -> Animation {
        .easeOut(duration: 0.32).delay(Double(index % 6) * base)
    }
}

// MARK: - Press Button Style

/// Applies scale and opacity press feedback — the universal interactive feel.
/// Replace `.buttonStyle(.plain)` with this wherever tactile feedback is desired.
public struct PressButtonStyle: ButtonStyle {
    let scale: CGFloat

    public init(scale: CGFloat = 0.96) {
        self.scale = scale
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(AstralAnimation.snappy, value: configuration.isPressed)
    }
}

// MARK: - Stagger Appear Modifier

/// Stagger-aware fade-up appearance for list and grid items.
/// Use `.staggeredAppear(index: index)` inside a ForEach to cascade items in.
struct StaggeredAppearModifier: ViewModifier {
    let index: Int
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 14)
            .onAppear {
                withAnimation(AstralAnimation.stagger(index: index)) {
                    appeared = true
                }
            }
    }
}

// MARK: - View Extensions

public extension View {
    /// Applies scale + opacity press feedback via PressButtonStyle.
    func pressEffect(scale: CGFloat = 0.96) -> some View {
        buttonStyle(PressButtonStyle(scale: scale))
    }

    /// Staggered fade-up appear animation for list/grid items. Pass the ForEach index.
    func staggeredAppear(index: Int) -> some View {
        modifier(StaggeredAppearModifier(index: index))
    }
}
