import Foundation

public enum TimeFilter: CaseIterable {
    case all, last5m, last15m, last1h, last24h

    public var label: String {
        switch self {
        case .all: "All"
        case .last5m: "5 min"
        case .last15m: "15 min"
        case .last1h: "1 hour"
        case .last24h: "24 hours"
        }
    }

    public var cutoffDate: Date {
        switch self {
        case .all: .distantPast
        case .last5m: Date().addingTimeInterval(-5 * 60)
        case .last15m: Date().addingTimeInterval(-15 * 60)
        case .last1h: Date().addingTimeInterval(-3600)
        case .last24h: Date().addingTimeInterval(-86400)
        }
    }
}
