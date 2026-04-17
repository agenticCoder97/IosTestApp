import SwiftUI

/// A labelled text field styled with AstralColors for use inside filter sheets.
public struct FilterTextField: View {
    public let label: String
    public let placeholder: String
    @Binding public var text: String

    public init(_ label: String, placeholder: String = "", text: Binding<String>) {
        self.label = label
        self.placeholder = placeholder
        self._text = text
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !label.isEmpty {
                Text(label)
                    .font(AstralTypography.caption)
                    .foregroundStyle(AstralColors.muted)
            }
            TextField(placeholder, text: $text)
                .font(AstralTypography.body)
                .foregroundStyle(AstralColors.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(AstralColors.elevated)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AstralColors.border, lineWidth: 1)
                )
        }
    }
}
