import Foundation
import Testing
import Core
@testable import FanficFeature

@Suite("Fan fiction source links")
@MainActor
struct FanficLinksTests {
    private func story(_ source: String?, key: String = "ao3") -> LocalFanfic {
        let fanfic = LocalFanfic(id: UUID(), title: "Story", sourceKey: key)
        fanfic.sourceUrl = source
        return fanfic
    }

    @Test("story links are canonical AO3 and FanFiction.net work pages")
    func canonicalStoryLinks() {
        #expect(FanficLinks.story(story("https://archiveofourown.org/works/123/chapters/9")) == URL(string: "https://archiveofourown.org/works/123"))
        #expect(FanficLinks.story(story("https://m.fanfiction.net/s/42/7/", key: "ffnet")) == URL(string: "https://www.fanfiction.net/s/42/1/"))
    }

    @Test("any other saved source gets no link")
    func otherSourcesGetNoLink() {
        for source in ["javascript:alert(1)", "data:text/html,hi", "file:///etc/hosts",
                       "https://example.com/works/1", "http://archiveofourown.org/works/1", "notes.txt", nil] {
            #expect(FanficLinks.story(story(source)) == nil, "\(source ?? "nil")")
        }
    }

    @Test("author links stay on the source's own domain")
    func authorLinks() {
        #expect(FanficLinks.author("Sarah1281", sourceKey: "ao3") == URL(string: "https://archiveofourown.org/users/Sarah1281"))
        #expect(FanficLinks.author("Pen (user)", sourceKey: "ao3") == URL(string: "https://archiveofourown.org/users/user/pseuds/Pen"))
        #expect(FanficLinks.author("../../x?y", sourceKey: "ao3")?.host == "archiveofourown.org")
        #expect(FanficLinks.author("Spiny Norman", sourceKey: "ffnet")?.host == "www.fanfiction.net")
        #expect(FanficLinks.author("Someone", sourceKey: "local") == nil)
    }
}
