import Foundation
import Core

/// Persists harvested Cloudflare cookies from WKWebView sessions.
///
/// Architecture fix #5: Uses a domain mapping dictionary instead of matching
/// `sourceKey` directly against cookie domains. "ao3" won't match
/// ".archiveofourown.org" — the mapping resolves this.
public final class CookieStore: Sendable {
    public static let shared = CookieStore()

    /// Maps source_key to the actual cookie domain used by the site.
    private let sourceDomains: [String: String] = [
        "nhentai": "nhentai.net",
        "toongod": "toongod.org",
        "hentai20": "hentai20.io",
        "ao3": "archiveofourown.org",
        "ffnet": "fanfiction.net",
        "mangadex": "mangadex.org",
    ]

    private nonisolated(unsafe) let defaults = UserDefaults(suiteName: "com.astral.cookies")!

    private init() {}

    public func storeCookies(_ cookies: [CookieDTO], forSource sourceKey: String, userAgent: String) {
        let data = CookieCache(
            cookies: cookies,
            userAgent: userAgent,
            storedAt: Date()
        )
        if let encoded = try? JSONEncoder().encode(data) {
            defaults.set(encoded, forKey: "cookies:\(sourceKey)")
        }
    }

    public func getCookies(forSource sourceKey: String) -> CookieCache? {
        guard let data = defaults.data(forKey: "cookies:\(sourceKey)"),
              let cache = try? JSONDecoder().decode(CookieCache.self, from: data) else {
            return nil
        }

        // Check TTL
        if Date().timeIntervalSince(cache.storedAt) > AppConfig.cookieCacheTTLSeconds {
            clearCookies(forSource: sourceKey)
            return nil
        }

        return cache
    }

    public func clearCookies(forSource sourceKey: String) {
        defaults.removeObject(forKey: "cookies:\(sourceKey)")
    }

    /// Returns the domain string to filter cookies for a given source.
    /// Uses the mapping dictionary to resolve sourceKey -> actual domain.
    public func cookieDomain(for sourceKey: String) -> String? {
        sourceDomains[sourceKey]
    }

    /// Filters an array of HTTP cookies to only those matching the given source.
    public func filterCookies(_ cookies: [HTTPCookie], forSource sourceKey: String) -> [CookieDTO] {
        guard let domain = cookieDomain(for: sourceKey) else { return [] }
        return cookies
            .filter { $0.domain.contains(domain) }
            .map { CookieDTO(name: $0.name, value: $0.value, domain: $0.domain) }
    }
}

public struct CookieCache: Codable, Sendable {
    public let cookies: [CookieDTO]
    public let userAgent: String
    public let storedAt: Date
}
