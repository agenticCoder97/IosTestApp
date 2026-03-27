import SwiftUI

public struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    public init(icon: String, title: String, message: String) {
        self.icon = icon
        self.title = title
        self.message = message
    }

    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(AstralColors.muted)

            Text(title)
                .font(AstralTypography.title)
                .foregroundStyle(AstralColors.white)

            Text(message)
                .font(AstralTypography.body)
                .foregroundStyle(AstralColors.muted)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}

#Preview {
    EmptyStateView(
        icon: "book.closed",
        title: "No Comics Yet",
        message: "Browse a source and scrape your first comic to get started."
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(AstralColors.background)
}
