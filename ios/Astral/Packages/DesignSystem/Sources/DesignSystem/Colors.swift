import SwiftUI

/// Token-based color palette from the Astral design system.
/// Dark theme with metallic gold accents.
public enum AstralColors {
    // MARK: - Backgrounds
    public static let background = Color(hex: 0x0A0A0B)
    public static let surface = Color(hex: 0x141416)
    public static let elevated = Color(hex: 0x1E1E22)

    // MARK: - Borders & Muted
    public static let border = Color(hex: 0x2A2A30)
    public static let muted = Color(hex: 0x6B6B7A)

    // MARK: - Text
    public static let body = Color(hex: 0xC8C8D4)
    public static let white = Color(hex: 0xF0F0F8)

    // MARK: - Accent
    public static let gold = Color(hex: 0xC9A84C)

    // MARK: - Reader Backgrounds
    public static let readerDark = Color(hex: 0x0A0A0B)
    public static let readerSepia = Color(hex: 0x2C1810)
    public static let readerPaper = Color(hex: 0xF5F0E8)

    // MARK: - Status
    public static let success = Color(hex: 0x4CAF50)
    public static let warning = Color(hex: 0xFFA726)
    public static let error = Color(hex: 0xEF5350)
}

public extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }
}
