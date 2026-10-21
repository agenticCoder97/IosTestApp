import SwiftUI

struct IntroArtwork: View {
    let time: Double
    private var motion: IntroMotion { IntroMotion(time: time) }
    private let letters = Array("Astral").map(String.init)

    var body: some View {
        GeometryReader { geometry in
            let scale = min(1.12, max(0.4, min((geometry.size.width - 48) / 310, (geometry.size.height - 64) / 340)))
            ZStack {
                atmosphere
                Canvas { context, size in
                    context.translateBy(x: size.width / 2, y: size.height / 2 - 12)
                    context.scaleBy(x: scale, y: scale)
                    drawConstellation(in: context)
                    var mark = context
                    mark.translateBy(x: -84 * motion.wordmarkTravel, y: 0)
                    mark.rotate(by: .radians(motion.markRotation))
                    mark.scaleBy(x: motion.markScale, y: motion.markScale)
                    for index in 0..<4 { drawOrb(motion.orb(index), in: mark) }
                    if time >= 3.1 { drawUnifiedMark(in: mark) }
                    drawAssemblyLight(in: mark)
                }
                wordmark
                    .scaleEffect(scale)
                    .offset(x: (37 + 84 * (1 - motion.wordmarkTravel)) * scale, y: -12)
            }
        }
        .accessibilityHidden(true)
    }

    private var atmosphere: some View {
        RadialGradient(
            colors: [Color(hex: 0x66502D).opacity(0.16), Color(hex: 0x242035).opacity(0.07), .clear],
            center: .center, startRadius: 0, endRadius: 260
        )
        .opacity(0.4 + 0.6 * IntroMotion.smooth(time, 0, 0.6))
    }

    private var wordmark: some View {
        HStack(spacing: -0.8) {
            ForEach(letters.indices, id: \.self) { index in
                let reveal = motion.letter(index)
                let shine = exp(-pow((time - 3.78 - Double(index) * 0.048) / 0.14, 2))
                Text(letters[index])
                    .font(.system(size: 50, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient(
                        colors: [Color(hex: 0xFAE6AC), AstralColors.goldLight, Color(hex: 0xB38B43)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay { Color.white.opacity(shine * 0.38).mask(Text(letters[index]).font(.system(size: 50, weight: .heavy, design: .rounded))) }
                    .offset(y: 13 * (1 - reveal))
                    .blur(radius: 4 * (1 - reveal))
                    .opacity(reveal)
            }
        }
        .fixedSize()
        .frame(width: 170, height: 72, alignment: .leading)
    }

    private func drawOrb(_ orb: IntroOrb, in context: GraphicsContext) {
        guard orb.radius > 0.1 else { return }
        let path = orbPath(orb)
        let palette = IntroIllustrations.palettes[orb.index]
        let extent = orb.radius
        var body = context
        body.opacity = 1 - IntroMotion.smooth(time, 3.1, 3.16)
        body.fill(path, with: .linearGradient(
            Gradient(colors: palette),
            startPoint: CGPoint(x: orb.center.x - extent, y: orb.center.y - extent),
            endPoint: CGPoint(x: orb.center.x + extent, y: orb.center.y + extent)))
        var art = body
        art.clip(to: path)
        art.opacity *= orb.illustrationOpacity
        art.translateBy(x: orb.center.x, y: orb.center.y)
        art.rotate(by: .radians(orb.tilt))
        art.scaleBy(x: orb.radius / 42, y: orb.radius / 42)
        IntroIllustrations.draw(orb.index, in: art, time: time)
        drawOrbFinish(path, orb: orb, in: body)
        var gold = body
        gold.opacity *= orb.goldBlend
        gold.fill(path, with: goldShading)
    }

    private func drawOrbFinish(_ path: Path, orb: IntroOrb, in context: GraphicsContext) {
        var rim = context
        rim.opacity *= (1 - orb.morph) * 0.55
        rim.stroke(path, with: .linearGradient(
            Gradient(colors: [.white.opacity(0.6), .white.opacity(0.03), .black.opacity(0.14)]),
            startPoint: CGPoint(x: orb.center.x, y: orb.center.y - orb.radius),
            endPoint: CGPoint(x: orb.center.x, y: orb.center.y + orb.radius)), lineWidth: 0.7)
    }

    private var goldShading: GraphicsContext.Shading {
        .linearGradient(Gradient(colors: [Color(hex: 0xFFF0BD), Color(hex: 0xE1BA62), Color(hex: 0x9C7435)]),
                        startPoint: CGPoint(x: -15, y: -31), endPoint: CGPoint(x: 17, y: 31))
    }

    private func drawUnifiedMark(in context: GraphicsContext) {
        // One exterior contour removes the four antialiased joins after assembly.
        var path = Path()
        for index in 0..<4 {
            let curves = motion.orb(index).contour
            let next = motion.orb((index + 1) % 4).contour
            if index == 0 { path.move(to: curves[0].start) }
            path.addCurve(to: curves[0].end, control1: curves[0].control1, control2: curves[0].control2)
            path.addCurve(to: next[0].start, control1: next[3].control1, control2: next[3].control2)
        }
        path.closeSubpath()
        context.fill(path, with: goldShading)
        var light = context
        light.opacity = exp(-pow((time - 3.18) / 0.18, 2)) * 0.55
        light.stroke(path, with: .color(Color(hex: 0xFFF5D2)), lineWidth: 0.6)
    }

    private func drawAssemblyLight(in context: GraphicsContext) {
        let pulse = exp(-pow((time - 2.96) / 0.16, 2))
        guard pulse > 0.005 else { return }
        var glow = context
        glow.blendMode = .plusLighter
        glow.opacity = pulse * 0.18
        glow.fill(Path(ellipseIn: CGRect(x: -45, y: -45, width: 90, height: 90)), with: .radialGradient(
            Gradient(colors: [Color(hex: 0xFFE6A1), .clear]), center: .zero, startRadius: 0, endRadius: 45))
    }

    private func drawConstellation(in context: GraphicsContext) {
        guard motion.ornamentOpacity > 0 else { return }
        let points: [CGPoint] = [
            CGPoint(x: -47, y: -124), CGPoint(x: 78, y: -94), CGPoint(x: 133, y: 28),
            CGPoint(x: 57, y: 130), CGPoint(x: -80, y: 103), CGPoint(x: -137, y: -26),
        ]
        for (index, point) in points.enumerated() {
            var star = context
            star.opacity = motion.ornamentOpacity * (0.35 + 0.15 * sin(time * 2 + Double(index)))
            let pull = 1 - IntroMotion.smooth(time, 1.8, 2.8) * 0.7
            let p = CGPoint(x: point.x * pull, y: point.y * pull)
            if index.isMultiple(of: 3) {
                IntroIllustrations.sparkle(in: star, at: p, radius: 2.7, color: Color(hex: 0xF3DDA4))
            } else {
                star.fill(Path(ellipseIn: CGRect(x: p.x, y: p.y, width: 1.7, height: 1.7)), with: .color(Color(hex: 0xD7C7A0)))
            }
        }
    }

    private func orbPath(_ orb: IntroOrb) -> Path {
        var path = Path()
        let curves = orb.contour
        path.move(to: curves[0].start)
        for curve in curves {
            path.addCurve(to: curve.end, control1: curve.control1, control2: curve.control2)
        }
        path.closeSubpath()
        return path
    }
}

#Preview("Illustrated worlds") { IntroArtwork(time: 1.3).background(AstralColors.background) }
#Preview("Assembled wordmark") { IntroArtwork(time: 4.2).background(AstralColors.background) }
