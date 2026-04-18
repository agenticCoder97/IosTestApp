import Foundation

public enum AppConfig {
    // Resolved at build time:
    //   Simulator → localhost (Docker on Mac)
    //   Physical device → Mac's WiFi IP (Docker on Mac, same network)
    //   Release → production server
    #if DEBUG
        #if targetEnvironment(simulator)
        public static let apiBaseURL = "http://localhost:8000/api/v1"
        public static let staticBaseURL = "http://localhost:8000/static/"
        #else
        // Physical device — set to your Mac's local IP.
        // Find it with: ipconfig getifaddr en0
        public static let apiBaseURL = "http://192.168.0.108:8000/api/v1"
        public static let staticBaseURL = "http://192.168.0.108:8000/static/"
        #endif
    #else
    public static let apiBaseURL = "https://astral-reader.duckdns.org/api/v1"
    public static let staticBaseURL = "https://astral-reader.duckdns.org/static/"
    #endif

    public static let downloadLimitPerTabBytes: Int64 = 5 * 1024 * 1024 * 1024 // 5GB

    public static let progressDebounceSeconds: TimeInterval = 5.0

    public static let cookieCacheTTLSeconds: TimeInterval = 86400 // 24h
}
