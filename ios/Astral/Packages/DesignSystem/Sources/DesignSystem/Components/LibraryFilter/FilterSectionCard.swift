import SwiftUI

/// A card-style container used inside filter sheets. Wraps a titled section with consistent styling.
public struct FilterSectionCard<Content: View>: View {
    public let title: String
    public let content: Content

    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(AstralTypography.captionMedium)
                .foregroundStyle(AstralColors.muted)
                .textCase(.uppercase)

            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AstralColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
