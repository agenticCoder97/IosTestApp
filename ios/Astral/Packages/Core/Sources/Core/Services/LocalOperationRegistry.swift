import Foundation
import SwiftData
import Observation

@MainActor @Observable
public final class LocalOperationRegistry {
    public static let shared = LocalOperationRegistry()
    private var cancellation: [UUID: () -> Void] = [:]
    private init() {}
    public func register(_ id: UUID, cancel: @escaping () -> Void) { cancellation[id] = cancel }
    public func canCancel(_ id: UUID) -> Bool { cancellation[id] != nil }
    public func cancel(_ id: UUID) { cancellation[id]?() }
    public func finish(_ id: UUID) { cancellation.removeValue(forKey: id) }
}
