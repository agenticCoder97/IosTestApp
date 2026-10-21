import SwiftUI

/// A single timeline keeps the illustrated circles and the assembled mark in sync.
public struct AstralIntroView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var startedAt = Date()
    private let onComplete: () -> Void

    public init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
    }

    private var previewTime: Double? {
        #if DEBUG
        for argument in ProcessInfo.processInfo.arguments where argument.hasPrefix("--intro-time=") {
            return Double(argument.dropFirst("--intro-time=".count))
        }
        #endif
        return nil
    }

    public var body: some View {
        TimelineView(.animation(paused: reduceMotion || previewTime != nil || scenePhase != .active)) { timeline in
            let time = previewTime ?? (reduceMotion ? 3.4 : max(0, timeline.date.timeIntervalSince(startedAt)))
            IntroArtwork(time: time)
        }
        .background(AstralColors.background.ignoresSafeArea())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Astral")
        .accessibilityIdentifier("launch.intro")
        .task(id: "\(scenePhase)-\(reduceMotion)") {
            guard scenePhase == .active, previewTime == nil else { return }
            startedAt = Date()
            do { try await Task.sleep(for: .seconds(reduceMotion ? 0.25 : 4)) }
            catch { return }
            onComplete()
        }
    }
}

private struct IntroArtwork: View {
    let time: Double
    private let colors: [Color] = [
        Color(red: 0.92, green: 0.72, blue: 0.32),
        Color(red: 0.46, green: 0.67, blue: 0.88),
        Color(red: 0.71, green: 0.57, blue: 0.82),
        Color(red: 0.88, green: 0.82, blue: 0.65),
    ]
    private let symbols = ["book.closed.fill", "text.alignleft", "scroll.fill", "book.pages.fill"]

    var body: some View {
        GeometryReader { geometry in
            let scale = min(1, max(0.5, (geometry.size.width - 48) / 300))
            let reveal = progress(2.55, 3.2)
            ZStack {
                Canvas { context, size in
                    let origin = CGPoint(x: size.width / 2, y: size.height / 2)
                    context.translateBy(x: origin.x, y: origin.y)
                    context.scaleBy(x: scale, y: scale)
                    context.translateBy(x: -90 * progress(2.45, 3.15), y: 0)
                    context.rotate(by: .degrees(-12 * (1 - progress(2.05, 2.6))))
                    for index in 0..<4 {
                        drawPetal(index, context: context)
                    }
                } symbols: {
                    ForEach(0..<4) { index in
                        Image(systemName: symbols[index])
                            .font(.system(size: 32, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                            .tag(index)
                    }
                }
                Text("Astral")
                    .font(.system(size: 48, weight: .heavy, design: .rounded))
                    .foregroundStyle(AstralColors.goldLight)
                    .frame(width: 156, alignment: .leading)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: 156 * reveal)
                    }
                    .offset(x: 28, y: 2)
                    .scaleEffect(scale)
                    .opacity(reveal)
            }
        }
    }

    private func drawPetal(_ index: Int, context: GraphicsContext) {
        let morph = progress(1.55 + Double(index) * 0.06, 2.38 + Double(index) * 0.06)
        let expansion = progress(Double(index) * 0.055, 0.5 + Double(index) * 0.055)
        let drift = progress(0.35, 1.55)
        let angle = Double(index) * .pi / 2 - .pi / 2
        let radius = 72 + 17 * sin(drift * .pi)
        let center = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
        let orbRadius = 31 * expansion
        let path = petalPath(center: center, radius: orbRadius, index: index, morph: morph)
        var layer = context
        layer.fill(path, with: .color(colors[index]))
        // The illustration disappears inside the narrowing shape as it becomes the mark.
        layer.clip(to: path)
        layer.opacity = 1 - progress(1.55, 2.05)
        if let illustration = layer.resolveSymbol(id: index) {
            layer.draw(illustration, at: CGPoint(x: center.x, y: center.y + 5 * sin(drift * .pi)))
        }
        var gold = context
        gold.opacity = progress(2.15, 2.65)
        gold.fill(path, with: .linearGradient(
            Gradient(colors: [AstralColors.goldLight, AstralColors.goldDark]),
            startPoint: CGPoint(x: 0, y: -48), endPoint: CGPoint(x: 0, y: 48)))
    }

    /// Each circle uses the same four cubic segments as its final star arm.
    /// Interpolating their control points produces continuous silhouettes throughout.
    private func petalPath(center: CGPoint, radius: Double, index: Int, morph: Double) -> Path {
        let circle: [CGPoint] = [
            CGPoint(x: center.x, y: center.y - radius),
            CGPoint(x: center.x + radius, y: center.y),
            CGPoint(x: center.x, y: center.y + radius),
            CGPoint(x: center.x - radius, y: center.y),
        ]
        let tips = [CGPoint(x: 0, y: -32), CGPoint(x: 8, y: -8), .zero, CGPoint(x: -8, y: -8)]
        let rotation = Double(index) * .pi / 2
        let star = tips.map { point in
            CGPoint(x: point.x * cos(rotation) - point.y * sin(rotation),
                    y: point.x * sin(rotation) + point.y * cos(rotation))
        }
        let k = radius * 0.55228475
        let tangents = [CGPoint(x: k, y: 0), CGPoint(x: 0, y: k),
                        CGPoint(x: -k, y: 0), CGPoint(x: 0, y: -k)]
        // Stretch along the inward trajectory before the arm contracts into place.
        let stretch = sin(morph * .pi) * 0.75
        func deform(_ point: CGPoint) -> CGPoint {
            let xScale = index.isMultiple(of: 2) ? 1 - stretch * 0.5 : 1 + stretch
            let yScale = index.isMultiple(of: 2) ? 1 + stretch : 1 - stretch * 0.5
            return CGPoint(x: center.x + (point.x - center.x) * xScale,
                           y: center.y + (point.y - center.y) * yScale)
        }
        var path = Path()
        path.move(to: mix(deform(circle[0]), star[0], morph))
        for i in 0..<4 {
            let next = (i + 1) % 4
            let c1 = CGPoint(x: circle[i].x + tangents[i].x, y: circle[i].y + tangents[i].y)
            let c2 = CGPoint(x: circle[next].x - tangents[next].x, y: circle[next].y - tangents[next].y)
            path.addCurve(to: mix(deform(circle[next]), star[next], morph),
                          control1: mix(deform(c1), mix(star[i], star[next], 1.0 / 3), morph),
                          control2: mix(deform(c2), mix(star[i], star[next], 2.0 / 3), morph))
        }
        path.closeSubpath()
        return path
    }

    private func progress(_ start: Double, _ end: Double) -> Double {
        let value = min(1, max(0, (time - start) / (end - start)))
        return value * value * (3 - 2 * value)
    }

    private func mix(_ a: CGPoint, _ b: CGPoint, _ amount: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * amount, y: a.y + (b.y - a.y) * amount)
    }
}

#Preview("Assembled intro") {
    IntroArtwork(time: 3.4).background(AstralColors.background)
}
