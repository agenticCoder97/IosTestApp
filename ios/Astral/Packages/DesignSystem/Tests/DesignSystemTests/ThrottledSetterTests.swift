import Testing
import Foundation
@testable import DesignSystem

@Suite("ThrottledSetter")
struct ThrottledSetterTests {

    /// Mutable clock used by the injected closure.
    final class FakeClock {
        var now: Date = Date(timeIntervalSince1970: 0)
        func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    }

    @Test("first write always applies")
    func firstWriteApplies() {
        let clock = FakeClock()
        let setter = ThrottledSetter<Int>(interval: 0.1, clock: { clock.now })
        var applied: Int?
        let didWrite = setter.set(42) { applied = $0 }
        #expect(didWrite == true)
        #expect(applied == 42)
    }

    @Test("write inside interval is rejected")
    func writeInsideIntervalRejected() {
        let clock = FakeClock()
        let setter = ThrottledSetter<Int>(interval: 0.1, clock: { clock.now })
        var applied: Int?
        _ = setter.set(1) { applied = $0 }
        clock.advance(0.05)
        let didWrite = setter.set(2) { applied = $0 }
        #expect(didWrite == false)
        #expect(applied == 1)
    }

    @Test("write after interval is applied")
    func writeAfterIntervalApplied() {
        let clock = FakeClock()
        let setter = ThrottledSetter<Int>(interval: 0.1, clock: { clock.now })
        var applied: Int?
        _ = setter.set(1) { applied = $0 }
        clock.advance(0.15)
        let didWrite = setter.set(2) { applied = $0 }
        #expect(didWrite == true)
        #expect(applied == 2)
    }

    @Test("same value is a no-op even past interval")
    func sameValueIsNoOp() {
        let clock = FakeClock()
        let setter = ThrottledSetter<Int>(interval: 0.1, clock: { clock.now })
        var callCount = 0
        _ = setter.set(1) { _ in callCount += 1 }
        clock.advance(0.5)
        let didWrite = setter.set(1) { _ in callCount += 1 }
        #expect(didWrite == false)
        #expect(callCount == 1)
    }

    @Test("reset makes the next write apply immediately")
    func resetMakesNextWriteApply() {
        let clock = FakeClock()
        let setter = ThrottledSetter<Int>(interval: 0.1, clock: { clock.now })
        _ = setter.set(1) { _ in }
        setter.reset()
        let didWrite = setter.set(1) { _ in }
        #expect(didWrite == true)
    }

    @Test("works with Double")
    func worksWithDouble() {
        let clock = FakeClock()
        let setter = ThrottledSetter<Double>(interval: 0.1, clock: { clock.now })
        var applied: Double?
        let didWrite = setter.set(3.14) { applied = $0 }
        #expect(didWrite == true)
        #expect(applied == 3.14)
    }
}
