import SwiftUI

public struct StatusBadge: View {
    let text: String
    let color: Color

    public init(_ text: String, color: Color = AstralColors.gold) {
        self.text = text
        self.color = color
    }

    public var body: some View {
        Text(text)
            .font(AstralTypography.captionMedium)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }
}

public extension StatusBadge {
    static func downloaded() -> StatusBadge {
        StatusBadge("Downloaded", color: AstralColors.success)
    }

    static func partial() -> StatusBadge {
        StatusBadge("Partial", color: AstralColors.warning)
    }

    static func failed() -> StatusBadge {
        StatusBadge("Failed", color: AstralColors.error)
    }

    static func scraping() -> StatusBadge {
        StatusBadge("Scraping...", color: AstralColors.gold)
    }

    static func savedToDevice() -> StatusBadge {
        StatusBadge("Saved", color: Color(hex: 0x5C9DFF))
    }
}

#Preview {
    HStack {
        StatusBadge.downloaded()
        StatusBadge.partial()
        StatusBadge.failed()
        StatusBadge.scraping()
    }
    .padding()
    .background(AstralColors.background)
}
