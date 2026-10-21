import SwiftUI

/// Small, original reading worlds, drawn at an 84-point artboard inside each orb.
/// Their clipped parallax survives the first part of the inward stretch.
enum IntroIllustrations {
    static let palettes: [[Color]] = [
        [Color(hex: 0xF3CE79), Color(hex: 0xBA853E)],
        [Color(hex: 0x9CD4E5), Color(hex: 0x4F86B5)],
        [Color(hex: 0xD5B6D8), Color(hex: 0x8B70AC)],
        [Color(hex: 0xACD4B7), Color(hex: 0x619A92)],
    ]
    static let paper = Color(hex: 0xFFF2CE)
    static let ink = Color(hex: 0x283D59)

    static func draw(_ index: Int, in context: GraphicsContext, time: Double) {
        var art = context
        let drift = sin(time * 1.8 + Double(index))
        art.translateBy(x: drift * 2, y: cos(time * 1.6 + Double(index)) * 1.5)
        switch index {
        case 0: book(in: art, turn: sin(time * 2.1))
        case 1: comic(in: art, drift: drift)
        case 2: night(in: art, time: time)
        default: manuscript(in: art, time: time)
        }
    }

    private static func book(in context: GraphicsContext, turn: Double) {
        var c = context
        disc(in: c, at: CGPoint(x: -25, y: -27), radius: 24, color: paper.opacity(0.15))
        sparkle(in: c, at: CGPoint(x: 24, y: -23), radius: 5, color: paper)
        sparkle(in: c, at: CGPoint(x: -29, y: 0), radius: 2.5, color: paper.opacity(0.8))
        c.rotate(by: .degrees(-9))
        c.translateBy(x: 0, y: 7)
        var cover = Path()
        cover.move(to: CGPoint(x: -30, y: -20))
        cover.addQuadCurve(to: CGPoint(x: 0, y: -13), control: CGPoint(x: -12, y: -24))
        cover.addQuadCurve(to: CGPoint(x: 30, y: -20), control: CGPoint(x: 12, y: -24))
        cover.addLine(to: CGPoint(x: 30, y: 23))
        cover.addQuadCurve(to: CGPoint(x: 0, y: 29), control: CGPoint(x: 12, y: 20))
        cover.addQuadCurve(to: CGPoint(x: -30, y: 23), control: CGPoint(x: -12, y: 20))
        cover.closeSubpath()
        var shadow = c
        shadow.translateBy(x: 1, y: 4)
        shadow.fill(cover, with: .color(Color(hex: 0x6A4524).opacity(0.28)))
        c.fill(cover, with: .color(Color(hex: 0x805832)))
        for side in [-1.0, 1.0] {
            var page = Path()
            page.move(to: CGPoint(x: 0, y: -16))
            page.addQuadCurve(to: CGPoint(x: side * 27, y: -23), control: CGPoint(x: side * 12, y: -27))
            page.addLine(to: CGPoint(x: side * 27, y: 18))
            page.addQuadCurve(to: CGPoint(x: 0, y: 25), control: CGPoint(x: side * 12, y: 15))
            page.closeSubpath()
            c.fill(page, with: .color(side < 0 ? Color(hex: 0xFFF4D4) : Color(hex: 0xECDDAD)))
            for line in 0..<5 {
                var rule = Path()
                let y = -10.0 + Double(line) * 5.5
                rule.move(to: CGPoint(x: side * 5, y: y))
                rule.addQuadCurve(to: CGPoint(x: side * (line == 4 ? 18 : 23), y: y - 3),
                                  control: CGPoint(x: side * 13, y: y - 4))
                c.stroke(rule, with: .color(Color(hex: 0xA98D58).opacity(0.6)), lineWidth: 1.1)
            }
        }
        var leaf = Path()
        leaf.move(to: CGPoint(x: 0, y: -16))
        leaf.addQuadCurve(to: CGPoint(x: 16 + turn * 3, y: -26), control: CGPoint(x: 3, y: -28))
        leaf.addLine(to: CGPoint(x: 14 + turn * 3, y: 13))
        leaf.addQuadCurve(to: CGPoint(x: 0, y: 25), control: CGPoint(x: 4, y: 15))
        leaf.closeSubpath()
        c.fill(leaf, with: .color(paper.opacity(0.9)))
        var ribbon = Path()
        ribbon.move(to: CGPoint(x: 7, y: 18))
        ribbon.addLines([CGPoint(x: 7, y: 31), CGPoint(x: 10, y: 28), CGPoint(x: 13, y: 31), CGPoint(x: 13, y: 17)])
        ribbon.closeSubpath()
        c.fill(ribbon, with: .color(Color(hex: 0xC06C51)))
    }

    private static func comic(in context: GraphicsContext, drift: Double) {
        var c = context
        c.rotate(by: .degrees(8))
        let sheet = Path(roundedRect: CGRect(x: -31, y: -31, width: 62, height: 64), cornerRadius: 5)
        var shadow = c
        shadow.translateBy(x: 2, y: 4)
        shadow.fill(sheet, with: .color(ink.opacity(0.25)))
        c.fill(sheet, with: .color(Color(hex: 0xF4F4E9)))
        let tall = CGRect(x: -27, y: -27, width: 24, height: 55)
        let upper = CGRect(x: 1, y: -27, width: 26, height: 25)
        let lower = CGRect(x: 1, y: 2, width: 26, height: 26)
        c.fill(Path(tall), with: .color(Color(hex: 0x405D80)))
        var landscape = c
        landscape.clip(to: Path(tall))
        disc(in: landscape, at: CGPoint(x: -12, y: -14), radius: 7, color: Color(hex: 0xF7D990))
        fillPolygon(in: landscape, points: [(-34, 26), (-12 + drift, -8), (5, 26)], color: Color(hex: 0x9DB4C6))
        fillPolygon(in: landscape, points: [(-34, 28), (-24, 5), (-4, 28)], color: Color(hex: 0x627F9C))
        c.fill(Path(upper), with: .color(Color(hex: 0xBDD7DF)))
        for line in 0..<5 {
            stroke(in: c, from: CGPoint(x: 5, y: -23 + Double(line) * 3.7),
                   to: CGPoint(x: 22, y: -26 + Double(line) * 3.7), color: ink.opacity(0.35), width: 0.8)
        }
        let bubble = Path(ellipseIn: CGRect(x: 5, y: -22, width: 18, height: 12))
        c.fill(bubble, with: .color(.white))
        for x in [10.0, 14, 18] { disc(in: c, at: CGPoint(x: x, y: -16), radius: 0.8, color: ink) }
        c.fill(Path(lower), with: .color(Color(hex: 0xE5BA76)))
        var panel = c
        panel.clip(to: Path(lower))
        disc(in: panel, at: CGPoint(x: 13, y: 12), radius: 5, color: ink)
        let figure = Path(roundedRect: CGRect(x: 5, y: 18, width: 17, height: 22), cornerRadius: 7)
        panel.fill(figure, with: .color(ink))
        stroke(in: panel, from: CGPoint(x: 2, y: 6), to: CGPoint(x: 8, y: 9), color: paper, width: 1)
        stroke(in: panel, from: CGPoint(x: 25, y: 5), to: CGPoint(x: 20, y: 9), color: paper, width: 1)
    }

    private static func night(in c: GraphicsContext, time: Double) {
        disc(in: c, at: CGPoint(x: 15, y: -17), radius: 14, color: paper.opacity(0.12))
        disc(in: c, at: CGPoint(x: 15, y: -17), radius: 9, color: Color(hex: 0xFFE5AE))
        disc(in: c, at: CGPoint(x: 18, y: -20), radius: 8, color: Color(hex: 0xB296C5))
        for (i, point) in [CGPoint(x: -23, y: -22), CGPoint(x: -5, y: -30), CGPoint(x: 30, y: 0)].enumerated() {
            sparkle(in: c, at: point, radius: 2 + 0.6 * sin(time * 2 + Double(i)), color: paper.opacity(0.9))
        }
        fillPolygon(in: c, points: [(-48, 40), (-24, -3), (-3, 19), (14, -1), (48, 40)], color: Color(hex: 0x816895))
        fillPolygon(in: c, points: [(-48, 40), (-10, 8), (12, 25), (31, 6), (48, 40)], color: Color(hex: 0x5C5279))
        var hills = Path()
        hills.move(to: CGPoint(x: -45, y: 33))
        hills.addCurve(to: CGPoint(x: 45, y: 26), control1: CGPoint(x: -9, y: 6), control2: CGPoint(x: 17, y: 45))
        hills.addLines([CGPoint(x: 45, y: 48), CGPoint(x: -45, y: 48)])
        hills.closeSubpath()
        c.fill(hills, with: .color(Color(hex: 0x3B405F)))
        // A lit window makes the landscape a place with a story, rather than an icon.
        c.fill(Path(CGRect(x: -16, y: 13, width: 10, height: 14)), with: .color(Color(hex: 0x30384E)))
        fillPolygon(in: c, points: [(-19, 14), (-11, 5), (-3, 14)], color: Color(hex: 0x30384E))
        c.fill(Path(roundedRect: CGRect(x: -13, y: 18, width: 4, height: 6), cornerRadius: 0.8), with: .color(Color(hex: 0xF5CE83)))
        var trail = Path()
        trail.move(to: CGPoint(x: -10, y: 27))
        trail.addQuadCurve(to: CGPoint(x: 10, y: 44), control: CGPoint(x: -15, y: 37))
        c.stroke(trail, with: .color(Color(hex: 0xD1B696).opacity(0.5)), lineWidth: 2)
    }

    private static func manuscript(in context: GraphicsContext, time: Double) {
        var c = context
        c.rotate(by: .degrees(-12))
        let paperRect = CGRect(x: -22, y: -30, width: 43, height: 59)
        var shadow = c
        shadow.translateBy(x: 3, y: 4)
        shadow.fill(Path(roundedRect: paperRect, cornerRadius: 4), with: .color(Color(hex: 0x2D665C).opacity(0.2)))
        c.fill(Path(roundedRect: paperRect, cornerRadius: 4), with: .color(paper))
        c.fill(Path(CGRect(x: -22, y: -30, width: 5, height: 59)), with: .color(Color(hex: 0xDCCBA1)))
        for line in 0..<7 {
            let y = -17.0 + Double(line) * 5
            let width = line == 0 ? 12.0 : (line == 6 ? 17 : 27)
            let write = IntroMotion.smooth(time, 0.3 + Double(line) * 0.07, 0.8 + Double(line) * 0.07)
            stroke(in: c, from: CGPoint(x: -11, y: y), to: CGPoint(x: -11 + width * write, y: y),
                   color: Color(hex: 0x6C8B7C).opacity(line == 0 ? 0.9 : 0.5), width: line == 0 ? 2.5 : 1.3)
        }
        var pen = c
        pen.translateBy(x: 19, y: 4)
        pen.rotate(by: .degrees(27 + sin(time * 1.8) * 4))
        pen.fill(Path(roundedRect: CGRect(x: -3, y: -29, width: 6, height: 37), cornerRadius: 2.5), with: .color(ink))
        pen.fill(Path(CGRect(x: -3, y: -21, width: 6, height: 3)), with: .color(Color(hex: 0xE0BB6A)))
        fillPolygon(in: pen, points: [(-3, 8), (0, 17), (3, 8)], color: Color(hex: 0xD3A44D))
        stroke(in: pen, from: CGPoint(x: 0, y: 10), to: CGPoint(x: 0, y: 15), color: ink, width: 0.7)
        sparkle(in: c, at: CGPoint(x: -31, y: -12), radius: 3, color: paper.opacity(0.8))
    }

    static func sparkle(in c: GraphicsContext, at p: CGPoint, radius r: Double, color: Color) {
        var path = Path()
        path.move(to: CGPoint(x: p.x, y: p.y - r))
        path.addQuadCurve(to: CGPoint(x: p.x + r, y: p.y), control: p)
        path.addQuadCurve(to: CGPoint(x: p.x, y: p.y + r), control: p)
        path.addQuadCurve(to: CGPoint(x: p.x - r, y: p.y), control: p)
        path.addQuadCurve(to: CGPoint(x: p.x, y: p.y - r), control: p)
        c.fill(path, with: .color(color))
    }

    private static func disc(in c: GraphicsContext, at p: CGPoint, radius r: Double, color: Color) {
        c.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(color))
    }

    private static func fillPolygon(in c: GraphicsContext, points: [(Double, Double)], color: Color) {
        var path = Path()
        path.addLines(points.map { CGPoint(x: $0.0, y: $0.1) })
        path.closeSubpath()
        c.fill(path, with: .color(color))
    }

    private static func stroke(in c: GraphicsContext, from a: CGPoint, to b: CGPoint, color: Color, width: Double) {
        var path = Path()
        path.move(to: a)
        path.addLine(to: b)
        c.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }
}
