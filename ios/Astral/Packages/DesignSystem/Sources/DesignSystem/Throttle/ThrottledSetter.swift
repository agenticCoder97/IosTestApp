import Foundation

/// Drops writes that arrive within `interval` of the previous applied write,
/// OR whose value is unchanged from the last applied value. Reference-typed
/// so a single instance can be held as `@State` on a SwiftUI view and shared
/// across body re-renders.
public final class ThrottledSetter<T: Equatable> {
    private let interval: TimeInterval
    private let clock: () -> Date
    private var lastApplied: Date = .distantPast
    private var lastValue: T? = nil

    public init(interval: TimeInterval, clock: @escaping () -> Date = Date.init) {
        self.interval = interval
        self.clock = clock
    }

    /// Applies `apply(value)` if enough time has passed since the last applied
    /// write AND the value has changed. Returns `true` if the write went through.
    @discardableResult
    public func set(_ value: T, apply: (T) -> Void) -> Bool {
        if lastValue == value { return false }
        let now = clock()
        guard now.timeIntervalSince(lastApplied) >= interval else { return false }
        lastApplied = now
        lastValue = value
        apply(value)
        return true
    }

    /// Clears both last-applied timestamp and last value so the next `set` applies.
    /// Use on view transitions (e.g. chapter change) where the throttle should reset.
    public func reset() {
        lastApplied = .distantPast
        lastValue = nil
    }
}
