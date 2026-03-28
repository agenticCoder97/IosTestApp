import SwiftUI

public struct ProgressBarView: View {
    let progress: Double
    let height: CGFloat

    @State private var animatedProgress: Double = 0

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
                    .fill(
                        LinearGradient(
                            colors: [AstralColors.gold, AstralColors.gold.opacity(0.75)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * animatedProgress)
            }
        }
        .frame(height: height)
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.85).delay(0.12)) {
                animatedProgress = progress
            }
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                animatedProgress = newValue
            }
        }
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
