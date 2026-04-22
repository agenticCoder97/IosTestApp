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
