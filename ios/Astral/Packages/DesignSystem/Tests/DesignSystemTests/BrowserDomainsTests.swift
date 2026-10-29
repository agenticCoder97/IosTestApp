import Testing
@testable import DesignSystem

@Suite("BrowserDomains")
struct BrowserDomainsTests {
    let toongod = ["toongod.org", "toongod.com"]

    @Test("source domains and their subdomains load in any frame")
    func sourceDomains() {
        #expect(BrowserDomains.allows("toongod.org", isMainFrame: true, domains: toongod))
        #expect(BrowserDomains.allows("www.toongod.org", isMainFrame: true, domains: toongod))
        #expect(BrowserDomains.allows("www.toongod.org", isMainFrame: false, domains: toongod))
    }

    @Test("Cloudflare's challenge widget loads inside the page")
    func challengeFrame() {
        #expect(BrowserDomains.allows("challenges.cloudflare.com", isMainFrame: false, domains: toongod))
    }

    @Test("Cloudflare never replaces the page itself")
    func challengeMainFrame() {
        #expect(!BrowserDomains.allows("challenges.cloudflare.com", isMainFrame: true, domains: toongod))
    }

    @Test("other sites stay blocked, including look-alike hosts and ad frames")
    func otherSites() {
        #expect(!BrowserDomains.allows("ads.example.com", isMainFrame: false, domains: toongod))
        #expect(!BrowserDomains.allows("eviltoongod.org", isMainFrame: true, domains: toongod))
        #expect(!BrowserDomains.allows("cloudflare.com", isMainFrame: false, domains: toongod))
        #expect(!BrowserDomains.allows("challenges.cloudflare.com.evil.net", isMainFrame: false, domains: toongod))
    }
}
