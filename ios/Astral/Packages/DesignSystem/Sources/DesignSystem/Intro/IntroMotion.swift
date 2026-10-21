import Foundation
import CoreGraphics

/// Deterministic choreography shared by the live intro and frame previews.
struct IntroMotion {
    static let duration = 4.5
    let time: Double

    var wordmarkTravel: Double { Self.smooth(time, 2.9, 3.5) }
    var ornamentOpacity: Double { Self.smooth(time, 0.1, 0.8) * (1 - Self.smooth(time, 1.7, 2.7)) }
    var markRotation: Double { -0.16 * (1 - Self.smooth(time, 2.7, 3.2)) }
    var markScale: Double { 1 + 0.1 * exp(-7 * max(0, time - 2.8)) * sin(12 * max(0, time - 2.8)) }

    func orb(_ index: Int) -> IntroOrb {
        let delay = Double(index) * 0.065
        let arrival = Self.spring(Self.unit(time, delay, 0.62 + delay))
        let orbit = Self.smooth(time, 0.35, 1.95)
        let anticipation = sin(Self.unit(time, 1.65, 2.2) * .pi) * 9
        let distance = 72 + 31 * Self.smooth(time, 0.05, 0.75) + sin(orbit * .pi) * 11 + anticipation
        let angle = Double(index) * .pi / 2 - .pi / 2 + 0.18 + orbit * 0.24
        let morph = Self.smoother(time, 1.93 + delay, 2.89 + delay)
        return IntroOrb(
            index: index,
            center: CGPoint(x: cos(angle) * distance, y: sin(angle) * distance),
            radius: 39 * arrival,
            morph: morph,
            illustrationOpacity: 1 - Self.smooth(time, 2.08 + delay, 2.58 + delay),
            tilt: -0.12 + sin(orbit * .pi + Double(index)) * 0.1,
            goldBlend: Self.smooth(time, 2.55 + delay, 3.08)
        )
    }

    func letter(_ index: Int) -> Double {
        Self.smooth(time, 3.04 + Double(index) * 0.055, 3.48 + Double(index) * 0.055)
    }

    static func unit(_ time: Double, _ start: Double, _ end: Double) -> Double {
        min(1, max(0, (time - start) / (end - start)))
    }

    static func smooth(_ time: Double, _ start: Double, _ end: Double) -> Double {
        let p = unit(time, start, end)
        return p * p * (3 - 2 * p)
    }

    static func smoother(_ time: Double, _ start: Double, _ end: Double) -> Double {
        let p = unit(time, start, end)
        return p * p * p * (p * (p * 6 - 15) + 10)
    }

    private static func spring(_ p: Double) -> Double {
        guard p < 1 else { return 1 }
        return 1 - exp(-7 * p) * cos(10 * p)
    }
}

struct IntroOrb {
    let index: Int
    let center: CGPoint
    let radius: Double
    let morph: Double
    let illustrationOpacity: Double
    let tilt: Double
    let goldBlend: Double

    /// Circle → stretched droplet → one concave quadrant of the final sparkle.
    /// Matching cubic topology avoids the silhouette switching partway through.
    var contour: [IntroCurve] {
        let k = radius * 0.5522847498
        let circle = [CGPoint(x: 0, y: -radius), CGPoint(x: radius, y: 0),
                      CGPoint(x: 0, y: radius), CGPoint(x: -radius, y: 0)]
        let tangents = [CGPoint(x: k, y: 0), CGPoint(x: 0, y: k),
                        CGPoint(x: -k, y: 0), CGPoint(x: 0, y: -k)]
        // Two concave outer edges give the assembled star a drawn, curved profile.
        let star = [CGPoint(x: 0, y: -31), CGPoint(x: 9, y: -9), .zero, CGPoint(x: -9, y: -9)]
        let handles: [(CGPoint, CGPoint)] = [
            (CGPoint(x: 2, y: -20), CGPoint(x: 3, y: -13)),
            (CGPoint(x: 6, y: -6), CGPoint(x: 3, y: -3)),
            (CGPoint(x: -3, y: -3), CGPoint(x: -6, y: -6)),
            (CGPoint(x: -3, y: -13), CGPoint(x: -2, y: -20)),
        ]
        return (0..<4).map { i in
            let next = (i + 1) % 4
            return IntroCurve(
                start: mix(deform(circle[i]), rotate(star[i])),
                control1: mix(deform(circle[i] + tangents[i]), rotate(handles[i].0)),
                control2: mix(deform(circle[next] - tangents[next]), rotate(handles[i].1)),
                end: mix(deform(circle[next]), rotate(star[next]))
            )
        }
    }

    private func deform(_ point: CGPoint) -> CGPoint {
        let radial = CGVector(dx: center.x, dy: center.y)
        let length = max(1, hypot(radial.dx, radial.dy))
        let ux = radial.dx / length
        let uy = radial.dy / length
        let stretch = sin(morph * .pi) * 0.9
        let along = (point.x * ux + point.y * uy) * (1 + stretch)
        let across = (-point.x * uy + point.y * ux) * (1 - stretch * 0.48)
        return CGPoint(x: center.x + along * ux - across * uy,
                       y: center.y + along * uy + across * ux)
    }

    private func rotate(_ point: CGPoint) -> CGPoint {
        let angle = Double(index) * .pi / 2
        return CGPoint(x: point.x * cos(angle) - point.y * sin(angle),
                       y: point.x * sin(angle) + point.y * cos(angle))
    }

    private func mix(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * morph, y: a.y + (b.y - a.y) * morph)
    }
}

struct IntroCurve {
    let start: CGPoint
    let control1: CGPoint
    let control2: CGPoint
    let end: CGPoint
}

private extension CGPoint {
    static func + (lhs: Self, rhs: Self) -> Self { CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y) }
    static func - (lhs: Self, rhs: Self) -> Self { CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }
}

/// Active viewing time only; a notification or app switch must not replay the film.
struct IntroPlaybackClock {
    private(set) var resumedAt: Date?
    private var accumulated = 0.0

    func elapsed(at date: Date) -> Double {
        let running = resumedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0
        return min(IntroMotion.duration, accumulated + running)
    }

    mutating func resume(at date: Date) {
        if resumedAt == nil { resumedAt = date }
    }

    mutating func pause(at date: Date) {
        accumulated = elapsed(at: date)
        resumedAt = nil
    }
}
