import SwiftUI

public struct AstralCardModifier: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .background(AstralColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(AstralColors.border, lineWidth: 0.5)
            )
    }
}

public extension View {
    func astralCard() -> some View {
        modifier(AstralCardModifier())
    }
}

public struct OfflineBannerModifier: ViewModifier {
    let isOffline: Bool

    public func body(content: Content) -> some View {
        VStack(spacing: 0) {
            if isOffline {
                HStack {
                    Image(systemName: "wifi.slash")
                    Text("You're offline — showing downloaded content only")
                        .font(AstralTypography.caption)
                }
                .foregroundStyle(AstralColors.warning)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(AstralColors.warning.opacity(0.1))
            }
            content
        }
    }
}

public extension View {
    func offlineBanner(isOffline: Bool) -> some View {
        modifier(OfflineBannerModifier(isOffline: isOffline))
    }
}
