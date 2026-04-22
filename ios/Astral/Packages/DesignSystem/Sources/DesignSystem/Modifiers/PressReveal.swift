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
