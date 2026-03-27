import SwiftUI

public struct GoldButton: View {
    let title: String
    let icon: String?
    let action: () -> Void

    public init(_ title: String, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(title)
                    .font(AstralTypography.bodyMedium)
            }
            .foregroundStyle(AstralColors.background)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [
                        AstralColors.gold,
                        AstralColors.gold.opacity(0.85),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(spacing: 16) {
        GoldButton("Scrape", icon: "arrow.down.circle") {}
        GoldButton("Retry") {}
    }
    .padding()
    .background(AstralColors.background)
}
