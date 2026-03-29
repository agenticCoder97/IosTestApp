import SwiftUI

/// Always-visible search bar that slides down when activated.
/// Shows a magnifying glass icon in collapsed state, expands to a text field.
public struct AstralSearchBar: View {
    @Binding public var text: String
    @Binding public var isActive: Bool
    var placeholder: String

    public init(text: Binding<String>, isActive: Binding<Bool>, placeholder: String = "Search...") {
        self._text = text
        self._isActive = isActive
        self.placeholder = placeholder
    }

    public var body: some View {
        if isActive {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(AstralColors.muted)

                TextField(placeholder, text: $text)
                    .font(AstralTypography.body)
                    .foregroundStyle(AstralColors.white)
                    .tint(AstralColors.gold)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(AstralColors.muted)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    text = ""
                    withAnimation(AstralAnimation.quick) {
                        isActive = false
                    }
                } label: {
                    Text("Cancel")
                        .font(AstralTypography.caption)
                        .foregroundStyle(AstralColors.gold)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AstralColors.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
