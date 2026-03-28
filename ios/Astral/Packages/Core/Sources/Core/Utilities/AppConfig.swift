import Foundation

public enum AppConfig {
    #if DEBUG
    public static let apiBaseURL = "http://localhost:8000/api/v1"
    public static let staticBaseURL = "http://localhost:8000/static/"
    #else
    public static let apiBaseURL = "https://astral-reader.duckdns.org/api/v1"
    public static let staticBaseURL = "https://astral-reader.duckdns.org/static/"
    #endif

    public static let downloadLimitPerTabBytes: Int64 = 5 * 1024 * 1024 * 1024 // 5GB

    public static let progressDebounceSeconds: TimeInterval = 5.0

    public static let cookieCacheTTLSeconds: TimeInterval = 86400 // 24h
}
