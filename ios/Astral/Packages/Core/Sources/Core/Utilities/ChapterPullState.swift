import Foundation

/// Deliberate edge-pull state, independent of layout and animations. A release
/// fires only if the gesture began at that edge and is still beyond the threshold.
public struct ChapterPullState: Sendable {
    public enum Direction: Int, Sendable { case previous = -1, next = 1 }
    public private(set) var direction: Direction?
    public private(set) var progress: Double = 0
    public let threshold: Double
    public init(threshold: Double = 120) { self.threshold = max(1, threshold) }
    public mutating func begin(atTop: Bool, atBottom: Bool, verticalVelocity: Double) {
        if atTop && !atBottom { direction = .previous }
        else if atBottom && !atTop { direction = .next }
        else { direction = atTop && verticalVelocity > 0 ? .previous : (atBottom && verticalVelocity < 0 ? .next : nil) }
        progress = 0
    }
    public mutating func update(distanceBeyondEdge: Double) {
        guard let direction else { progress = 0; return }
        progress = Double(direction.rawValue) * min(1, max(0, distanceBeyondEdge / threshold))
    }
    public mutating func release(enabled: Bool) -> Direction? {
        let result = enabled && abs(progress) >= 1 ? direction : nil
        cancel()
        return result
    }
    public mutating func cancel() { direction = nil; progress = 0 }
}
