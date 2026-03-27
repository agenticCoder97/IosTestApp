import SwiftUI

public struct ProgressBarView: View {
    let progress: Double
    let height: CGFloat

    public init(progress: Double, height: CGFloat = 4) {
        self.progress = min(max(progress, 0), 1)
        self.height = height
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(AstralColors.border)

                RoundedRectangle(cornerRadius: height / 2)
                    .fill(AstralColors.gold)
                    .frame(width: geometry.size.width * progress)
            }
        }
        .frame(height: height)
    }
}

#Preview {
    VStack(spacing: 16) {
        ProgressBarView(progress: 0.0)
        ProgressBarView(progress: 0.33)
        ProgressBarView(progress: 0.75)
        ProgressBarView(progress: 1.0)
    }
    .padding()
    .background(AstralColors.background)
}
