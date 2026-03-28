import Foundation
import os

/// Centralized logger for Astral. Uses Apple's os.Logger (visible in Xcode Console
/// and Console.app) with an in-memory ring buffer for the in-app debug console.
///
/// Usage:
///   AstralLogger.network("GET /comics → 200 (45ms)")
///   AstralLogger.error("fetchComics failed: \(error)")
///   AstralLogger.info("Library loaded 42 comics")
public final class AstralLogger: @unchecked Sendable {
    public static let shared = AstralLogger()

    private let osLogger = Logger(subsystem: "com.astral.reader", category: "app")
    private let networkLogger = Logger(subsystem: "com.astral.reader", category: "network")

    /// Ring buffer of recent log entries for the debug console.
    private let lock = NSLock()
    private var _entries: [LogEntry] = []
    private let maxEntries = 300

    private init() {}

    // MARK: - Public API

    public static func info(_ message: String, context: String = "") {
        shared.log(.info, message, context: context)
    }

    public static func warning(_ message: String, context: String = "") {
        shared.log(.warning, message, context: context)
    }

    public static func error(_ message: String, context: String = "") {
        shared.log(.error, message, context: context)
    }

    public static func network(_ message: String) {
        shared.log(.network, message, context: "")
    }

    /// All buffered entries, newest first.
    public var entries: [LogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return _entries.reversed()
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        _entries.removeAll()
    }

    // MARK: - Internal

    private func log(_ level: LogLevel, _ message: String, context: String) {
        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            message: message,
            context: context
        )

        // os.Logger output (visible in Xcode + Console.app)
        switch level {
        case .info:
            osLogger.info("\(message, privacy: .public)")
        case .warning:
            osLogger.warning("⚠️ \(message, privacy: .public)")
        case .error:
            osLogger.error("❌ \(message, privacy: .public)")
        case .network:
            networkLogger.info("🌐 \(message, privacy: .public)")
        }

        // Ring buffer for in-app console
        lock.lock()
        _entries.append(entry)
        if _entries.count > maxEntries {
            _entries.removeFirst(_entries.count - maxEntries)
        }
        lock.unlock()
    }
}

// MARK: - Log Entry

public struct LogEntry: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let level: LogLevel
    public let message: String
    public let context: String
}

public enum LogLevel: String, Sendable {
    case info
    case warning
    case error
    case network

    public var emoji: String {
        switch self {
        case .info: "ℹ️"
        case .warning: "⚠️"
        case .error: "❌"
        case .network: "🌐"
        }
    }
}
