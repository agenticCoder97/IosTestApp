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
    /// Must be called on the main actor (UIImpactFeedbackGenerator is UIKit).
    @MainActor
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
