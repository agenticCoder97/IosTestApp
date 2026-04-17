import SwiftUI

/// A toggle button for switching between ascending and descending sort order.
public struct FilterSortDirectionToggle: View {
    @Binding public var ascending: Bool

    public init(ascending: Binding<Bool>) {
        self._ascending = ascending
    }

    public var body: some View {
        Button {
            ascending.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: ascending ? "arrow.up" : "arrow.down")
                    .font(.caption.weight(.semibold))
                Text(ascending ? "Ascending" : "Descending")
                    .font(AstralTypography.caption)
            }
            .foregroundStyle(AstralColors.gold)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(AstralColors.gold.opacity(0.15))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(AstralColors.gold, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
