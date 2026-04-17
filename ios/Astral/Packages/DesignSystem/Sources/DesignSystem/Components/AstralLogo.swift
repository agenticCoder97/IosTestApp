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
