import SwiftUI

/// Inter Variable font scale from the Astral design system.
/// Display 34pt bold, Title 22pt semibold, Body 16pt regular, Caption 12pt regular.
/// Dynamic Type compatible.
public enum AstralTypography {
    public static let display = Font.largeTitle.bold()
    public static let title = Font.title2.weight(.semibold)
    public static let titleSmall = Font.headline
    public static let body = Font.body
    public static let bodyMedium = Font.body.weight(.medium)
    public static let caption = Font.caption
    public static let captionMedium = Font.caption.weight(.medium)

    /// Fanfic reader font with user-configurable size (14–22pt)
    public static func readerFont(size: CGFloat, lineHeight: CGFloat = 1.6) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }
}
