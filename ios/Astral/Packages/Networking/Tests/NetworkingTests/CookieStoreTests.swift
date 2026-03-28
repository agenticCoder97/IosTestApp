import Testing
import Foundation
@testable import Networking
import Core

// MARK: - Helpers

/// Returns a fresh CookieStore backed by an isolated UserDefaults suite.
/// CookieStore.shared uses "com.astral.cookies"; tests use a unique suite per
/// test run so they can't pollute each other or the real shared store.
///
/// Because CookieStore.shared is a singleton we test the domain-mapping and
/// filter logic — the parts that don't require injecting a custom UserDefaults —
/// directly via the shared instance, and use a separate fresh instance only
/// where we need isolation.
private func makeCookies(domain: String, names: [String] = ["cf_clearance"]) -> [CookieDTO] {
    names.map { CookieDTO(name: $0, value: "v_\($0)", domain: domain) }
}

// MARK: - Domain Mapping

@Suite("CookieStore domain mapping")
struct CookieStoreDomainMappingTests {

    @Test("nhentai maps to nhentai.net")
    func nhentaiDomain() {
        #expect(CookieStore.shared.cookieDomain(for: "nhentai") == "nhentai.net")
    }

    @Test("toongod maps to toongod.com")
    func toongodDomain() {
        #expect(CookieStore.shared.cookieDomain(for: "toongod") == "toongod.com")
    }

    @Test("hentai20 maps to hentai20.io")
    func hentai20Domain() {
        #expect(CookieStore.shared.cookieDomain(for: "hentai20") == "hentai20.io")
    }

    @Test("ao3 maps to archiveofourown.org")
    func ao3Domain() {
        #expect(CookieStore.shared.cookieDomain(for: "ao3") == "archiveofourown.org")
    }

    @Test("ffnet maps to fanfiction.net")
    func ffnetDomain() {
        #expect(CookieStore.shared.cookieDomain(for: "ffnet") == "fanfiction.net")
    }

    @Test("unknown sourceKey returns nil")
    func unknownSource() {
        #expect(CookieStore.shared.cookieDomain(for: "mangadex") == nil)
    }
}

// MARK: - filterCookies

@Suite("CookieStore.filterCookies")
struct CookieStoreFilterTests {

    @Test("returns empty array for unknown sourceKey")
    func filterUnknownSource() {
        let cookies: [HTTPCookie] = []
        let result = CookieStore.shared.filterCookies(cookies, forSource: "unknown")
        #expect(result.isEmpty)
    }

    @Test("filters out cookies that don't match the domain")
    func filterMismatch() {
        let properties: [HTTPCookiePropertyKey: Any] = [
            .name: "cf_clearance",
            .value: "abc",
            .domain: "example.com",
            .path: "/",
        ]
        let cookies = [HTTPCookie(properties: properties)!]
        let result = CookieStore.shared.filterCookies(cookies, forSource: "ao3")
        #expect(result.isEmpty)
    }

    @Test("keeps cookies whose domain contains the mapped domain")
    func filterMatch() {
        let properties: [HTTPCookiePropertyKey: Any] = [
            .name: "user_credentials",
            .value: "xyz",
            .domain: ".archiveofourown.org",
            .path: "/",
        ]
        let cookies = [HTTPCookie(properties: properties)!]
        let result = CookieStore.shared.filterCookies(cookies, forSource: "ao3")
        #expect(result.count == 1)
        #expect(result[0].name == "user_credentials")
        #expect(result[0].domain == ".archiveofourown.org")
    }

    @Test("maps HTTPCookie fields to CookieDTO correctly")
    func filterMappingFields() {
        let properties: [HTTPCookiePropertyKey: Any] = [
            .name: "cf_clearance",
            .value: "secret-token",
            .domain: "nhentai.net",
            .path: "/",
        ]
        let cookies = [HTTPCookie(properties: properties)!]
        let result = CookieStore.shared.filterCookies(cookies, forSource: "nhentai")
        #expect(result.count == 1)
        #expect(result[0].name == "cf_clearance")
        #expect(result[0].value == "secret-token")
        #expect(result[0].domain == "nhentai.net")
    }

    @Test("returns only matching cookies from a mixed array")
    func filterMixedArray() {
        let matchProps: [HTTPCookiePropertyKey: Any] = [
            .name: "good", .value: "1", .domain: "nhentai.net", .path: "/",
        ]
        let otherProps: [HTTPCookiePropertyKey: Any] = [
            .name: "bad", .value: "2", .domain: "google.com", .path: "/",
        ]
        let cookies = [HTTPCookie(properties: matchProps)!, HTTPCookie(properties: otherProps)!]
        let result = CookieStore.shared.filterCookies(cookies, forSource: "nhentai")
        #expect(result.count == 1)
        #expect(result[0].name == "good")
    }
}

// MARK: - CookieCache Codable

@Suite("CookieCache")
struct CookieCacheTests {

    @Test("round-trips through JSON encoding")
    func roundTrip() throws {
        let cookies = makeCookies(domain: "archiveofourown.org")
        let cache = CookieCache(cookies: cookies, userAgent: "Mozilla/5.0", storedAt: Date())
        let data = try JSONEncoder().encode(cache)
        let decoded = try JSONDecoder().decode(CookieCache.self, from: data)
        #expect(decoded.userAgent == "Mozilla/5.0")
        #expect(decoded.cookies.count == cookies.count)
        #expect(decoded.cookies[0].name == cookies[0].name)
    }

    @Test("storedAt is preserved")
    func storedAtPreserved() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let cache = CookieCache(cookies: [], userAgent: "UA", storedAt: date)
        let data = try JSONEncoder().encode(cache)
        let decoded = try JSONDecoder().decode(CookieCache.self, from: data)
        #expect(abs(decoded.storedAt.timeIntervalSince1970 - date.timeIntervalSince1970) < 1)
    }
}

// MARK: - CookieDTO

@Suite("CookieDTO")
struct CookieDTOTests {

    @Test("stores name, value, domain")
    func storedFields() {
        let dto = CookieDTO(name: "cf", value: "token", domain: "nhentai.net")
        #expect(dto.name == "cf")
        #expect(dto.value == "token")
        #expect(dto.domain == "nhentai.net")
    }

    @Test("equatable by value")
    func equatable() {
        let a = CookieDTO(name: "cf", value: "tok", domain: "nhentai.net")
        let b = CookieDTO(name: "cf", value: "tok", domain: "nhentai.net")
        let c = CookieDTO(name: "cf", value: "different", domain: "nhentai.net")
        #expect(a == b)
        #expect(a != c)
    }

    @Test("round-trips through JSON encoding")
    func roundTrip() throws {
        let dto = CookieDTO(name: "user_credentials", value: "abc123", domain: ".archiveofourown.org")
        let data = try JSONEncoder().encode(dto)
        let decoded = try JSONDecoder().decode(CookieDTO.self, from: data)
        #expect(decoded == dto)
    }
}
