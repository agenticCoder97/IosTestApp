import SwiftUI

public struct ScrapeToast: Equatable {
    public let message: String
    public let isSuccess: Bool
    public init(message: String, isSuccess: Bool) {
        self.message = message
        self.isSuccess = isSuccess
    }
}

public struct ToastView: View {
    public let message: String
    public let isSuccess: Bool

    public init(_ message: String, isSuccess: Bool = true) {
        self.message = message
        self.isSuccess = isSuccess
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(isSuccess ? AstralColors.success : AstralColors.error)
            Text(message)
                .font(AstralTypography.bodyMedium)
                .foregroundStyle(AstralColors.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(AstralColors.border, lineWidth: 0.5))
    }
}
