import Testing
import Foundation
@testable import DesignSystem

@Suite("Intro choreography")
struct IntroMotionTests {
    @Test("Illustrated worlds stay separated before the deliberate convergence")
    func worldsHaveRoom() {
        for frame in 0...220 {
            let motion = IntroMotion(time: Double(frame) / 120)
            let orbs = (0..<4).map(motion.orb)
            for a in 0..<4 {
                for b in (a + 1)..<4 {
                    let distance = hypot(orbs[a].center.x - orbs[b].center.x, orbs[a].center.y - orbs[b].center.y)
                    #expect(distance > orbs[a].radius + orbs[b].radius + 8)
                }
            }
        }
    }

    @Test("All morph control points stay finite and inside the composition")
    func morphStaysBounded() {
        for frame in 0...540 {
            let motion = IntroMotion(time: Double(frame) / 120)
            for index in 0..<4 {
                for curve in motion.orb(index).contour {
                    for point in [curve.start, curve.control1, curve.control2, curve.end] {
                        #expect(point.x.isFinite && point.y.isFinite)
                        #expect(abs(point.x) < 180 && abs(point.y) < 180)
                    }
                }
            }
        }
    }

    @Test("Final petals join exactly into the seamless exterior")
    func finalJoins() {
        let motion = IntroMotion(time: IntroMotion.duration)
        for index in 0..<4 {
            let arm = motion.orb(index).contour
            let next = motion.orb((index + 1) % 4).contour
            #expect(hypot(arm[0].end.x - next[3].start.x, arm[0].end.y - next[3].start.y) < 0.000001)
            #expect(motion.orb(index).morph == 1)
        }
        #expect(motion.letter(5) == 1)
        #expect(motion.wordmarkTravel == 1)
    }
}

@Suite("Intro playback")
struct IntroPlaybackTests {
    @Test("Inactive time does not advance or restart the choreography")
    func pausesAcrossInterruptions() {
        let start = Date(timeIntervalSince1970: 0)
        var clock = IntroPlaybackClock()
        clock.resume(at: start)
        clock.pause(at: start.addingTimeInterval(1.2))
        #expect(abs(clock.elapsed(at: start.addingTimeInterval(25)) - 1.2) < 0.000001)
        clock.resume(at: start.addingTimeInterval(30))
        clock.resume(at: start.addingTimeInterval(30.5))
        #expect(abs(clock.elapsed(at: start.addingTimeInterval(31)) - 2.2) < 0.000001)
        #expect(clock.elapsed(at: start.addingTimeInterval(40)) == IntroMotion.duration)
    }
}
