import SwiftUI

public struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    @State private var appeared = false

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
                .scaleEffect(appeared ? 1 : 0.5)
                .opacity(appeared ? 1 : 0)

            Text(title)
                .font(AstralTypography.title)
                .foregroundStyle(AstralColors.white)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)

            Text(message)
                .font(AstralTypography.body)
                .foregroundStyle(AstralColors.muted)
                .multilineTextAlignment(.center)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)
        }
        .padding(40)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.72).delay(0.08)) {
                appeared = true
            }
        }
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
