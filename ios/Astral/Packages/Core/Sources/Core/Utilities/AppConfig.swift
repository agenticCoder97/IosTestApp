import Foundation

public enum AppConfig {
    /// A companion is optional. No localhost, LAN or retired OCI endpoint is used implicitly.
    public static var companionURL: URL? {
        guard let value = UserDefaults.standard.string(forKey: "companionURL"),
              let url = URL(string: value), ["http", "https"].contains(url.scheme),
              url.host != nil, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { return nil }
        return url
    }
    public static var companionEnabled: Bool { companionURL != nil }
    public static var apiBaseURL: String { (companionURL?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? "") + "/api/v1" }
    public static var staticBaseURL: String { (companionURL?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? "") + "/static/" }
    public static let downloadLimitPerTabBytes: Int64 = 5 * 1024 * 1024 * 1024
    public static var comicDownloadLimitBytes: Int64 {
        Int64(max(1, min(100, UserDefaults.standard.object(forKey: "comicStorageLimitGB") as? Int ?? 5))) * 1024 * 1024 * 1024
    }
    public static let progressDebounceSeconds: TimeInterval = 5
    public static let cookieCacheTTLSeconds: TimeInterval = 86400
}
