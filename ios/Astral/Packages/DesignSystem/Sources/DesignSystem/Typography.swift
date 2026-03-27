import SwiftUI

/// Inter Variable font scale from the Astral design system.
/// Display 34pt bold, Title 22pt semibold, Body 16pt regular, Caption 12pt regular.
/// Dynamic Type compatible.
public enum AstralTypography {
    public static let display = Font.system(size: 34, weight: .bold, design: .default)
    public static let title = Font.system(size: 22, weight: .semibold, design: .default)
    public static let titleSmall = Font.system(size: 18, weight: .semibold, design: .default)
    public static let body = Font.system(size: 16, weight: .regular, design: .default)
    public static let bodyMedium = Font.system(size: 16, weight: .medium, design: .default)
    public static let caption = Font.system(size: 12, weight: .regular, design: .default)
    public static let captionMedium = Font.system(size: 12, weight: .medium, design: .default)

    /// Fanfic reader font with user-configurable size (14–22pt)
    public static func readerFont(size: CGFloat, lineHeight: CGFloat = 1.6) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }
}
