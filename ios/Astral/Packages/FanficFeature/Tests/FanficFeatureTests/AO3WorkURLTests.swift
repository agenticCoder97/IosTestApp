import Foundation
import Testing
@testable import FanficFeature

@Suite("AO3 work links")
@MainActor
struct AO3WorkURLTests {

    @Test("work, chapter and collection links resolve to the work")
    func workLinksResolve() {
        let expected = URL(string: "https://archiveofourown.org/works/123")
        for link in ["https://archiveofourown.org/works/123",
                     "https://archiveofourown.org/works/123/chapters/456",
                     "https://archiveofourown.org/collections/some_fest/works/123"] {
            #expect(AO3ImportService.workURL(from: URL(string: link)) == expected, "\(link)")
        }
    }

    @Test("other pages are not works")
    func otherPagesRejected() {
        for link in ["https://archiveofourown.org/collections/some_fest",
                     "https://archiveofourown.org/collections/some_fest/works",
                     "https://archiveofourown.org/users/someone/works",
                     "http://archiveofourown.org/works/123",
                     "https://example.com/works/123"] {
            #expect(AO3ImportService.workURL(from: URL(string: link)) == nil, "\(link)")
        }
    }
}
