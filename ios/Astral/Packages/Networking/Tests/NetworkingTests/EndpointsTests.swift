import Testing
import Foundation
@testable import Networking
import Core

// MARK: - Helpers

private func queryValue(_ endpoint: Endpoint, name: String) -> String? {
    endpoint.queryItems?.first(where: { $0.name == name })?.value
}

// MARK: - HTTPMethod

@Suite("HTTPMethod")
struct HTTPMethodTests {
    @Test("raw values match HTTP verbs")
    func rawValues() {
        #expect(HTTPMethod.get.rawValue == "GET")
        #expect(HTTPMethod.post.rawValue == "POST")
        #expect(HTTPMethod.put.rawValue == "PUT")
        #expect(HTTPMethod.patch.rawValue == "PATCH")
        #expect(HTTPMethod.delete.rawValue == "DELETE")
    }
}

// MARK: - Comic Endpoints

@Suite("Endpoint.comics")
struct ComicEndpointsTests {

    @Test("comics path is /comics with GET")
    func comicsPath() {
        let ep = Endpoint.comics()
        #expect(ep.path == "/comics")
        #expect(ep.method == .get)
    }

    @Test("comics includes page and page_size defaults")
    func comicsDefaultPagination() {
        let ep = Endpoint.comics()
        #expect(queryValue(ep, name: "page") == "1")
        #expect(queryValue(ep, name: "page_size") == "20")
    }

    @Test("comics accepts custom page and pageSize")
    func comicsCustomPagination() {
        let ep = Endpoint.comics(page: 3, pageSize: 10)
        #expect(queryValue(ep, name: "page") == "3")
        #expect(queryValue(ep, name: "page_size") == "10")
    }

    @Test("comics omits sort when nil")
    func comicsSortNil() {
        let ep = Endpoint.comics()
        #expect(queryValue(ep, name: "sort") == nil)
    }

    @Test("comics includes sort when provided")
    func comicsSortProvided() {
        let ep = Endpoint.comics(sort: "title")
        #expect(queryValue(ep, name: "sort") == "title")
    }

    @Test("comicDetail path embeds UUID")
    func comicDetailPath() {
        let id = UUID()
        let ep = Endpoint.comicDetail(id: id)
        #expect(ep.path == "/comics/\(id)")
        #expect(ep.method == .get)
        #expect(ep.queryItems == nil)
    }

    @Test("chapterPages path embeds both UUIDs")
    func chapterPagesPath() {
        let comicId = UUID()
        let chapterId = UUID()
        let ep = Endpoint.chapterPages(comicId: comicId, chapterId: chapterId)
        #expect(ep.path == "/comics/\(comicId)/chapters/\(chapterId)/pages")
        #expect(ep.method == .get)
    }

    @Test("updateComic uses PATCH with body")
    func updateComicMethod() {
        let id = UUID()
        let body = ComicUpdateRequest(title: "New Title")
        let ep = Endpoint.updateComic(id: id, body: body)
        #expect(ep.path == "/comics/\(id)")
        #expect(ep.method == .patch)
        #expect(ep.body != nil)
    }

    @Test("deleteComic uses DELETE")
    func deleteComicMethod() {
        let id = UUID()
        let ep = Endpoint.deleteComic(id: id)
        #expect(ep.path == "/comics/\(id)")
        #expect(ep.method == .delete)
        #expect(ep.body == nil)
    }
}

// MARK: - Fanfic Endpoints

@Suite("Endpoint.fanfics")
struct FanficEndpointsTests {

    @Test("fanfics path is /fanfic with GET")
    func fanficsPath() {
        let ep = Endpoint.fanfics()
        #expect(ep.path == "/fanfic")
        #expect(ep.method == .get)
    }

    @Test("fanfics default pagination")
    func fanficsDefaultPagination() {
        let ep = Endpoint.fanfics()
        #expect(queryValue(ep, name: "page") == "1")
        #expect(queryValue(ep, name: "page_size") == "20")
    }

    @Test("fanfics omits optional filters when nil")
    func fanficsNoFilters() {
        let ep = Endpoint.fanfics()
        let names = ep.queryItems?.map { $0.name } ?? []
        #expect(!names.contains("fandom"))
        #expect(!names.contains("rating"))
        #expect(!names.contains("completion_status"))
        #expect(!names.contains("sort"))
    }

    @Test("fanfics includes fandom filter")
    func fanficsFandomFilter() {
        let ep = Endpoint.fanfics(fandom: "Harry Potter")
        #expect(queryValue(ep, name: "fandom") == "Harry Potter")
    }

    @Test("fanfics includes rating filter")
    func fanficsRatingFilter() {
        let ep = Endpoint.fanfics(rating: "M")
        #expect(queryValue(ep, name: "rating") == "M")
    }

    @Test("fanfics includes completion_status filter")
    func fanficsCompletionFilter() {
        let ep = Endpoint.fanfics(completionStatus: "complete")
        #expect(queryValue(ep, name: "completion_status") == "complete")
    }

    @Test("fanfics includes sort")
    func fanficsSort() {
        let ep = Endpoint.fanfics(sort: "word_count")
        #expect(queryValue(ep, name: "sort") == "word_count")
    }

    @Test("fanfics includes all filters together")
    func fanficsAllFilters() {
        let ep = Endpoint.fanfics(
            page: 2, pageSize: 5,
            fandom: "Naruto", rating: "T",
            completionStatus: "ongoing", sort: "title"
        )
        #expect(queryValue(ep, name: "page") == "2")
        #expect(queryValue(ep, name: "page_size") == "5")
        #expect(queryValue(ep, name: "fandom") == "Naruto")
        #expect(queryValue(ep, name: "rating") == "T")
        #expect(queryValue(ep, name: "completion_status") == "ongoing")
        #expect(queryValue(ep, name: "sort") == "title")
    }

    @Test("fanficDetail path embeds UUID")
    func fanficDetailPath() {
        let id = UUID()
        let ep = Endpoint.fanficDetail(id: id)
        #expect(ep.path == "/fanfic/\(id)")
        #expect(ep.method == .get)
    }

    @Test("fanficChapter path embeds both UUIDs")
    func fanficChapterPath() {
        let fanficId = UUID()
        let chapterId = UUID()
        let ep = Endpoint.fanficChapter(fanficId: fanficId, chapterId: chapterId)
        #expect(ep.path == "/fanfic/\(fanficId)/chapters/\(chapterId)")
        #expect(ep.method == .get)
    }

    @Test("deleteFanfic uses DELETE")
    func deleteFanficMethod() {
        let id = UUID()
        let ep = Endpoint.deleteFanfic(id: id)
        #expect(ep.path == "/fanfic/\(id)")
        #expect(ep.method == .delete)
    }
}

// MARK: - Scrape Endpoints

@Suite("Endpoint.scrape")
struct ScrapeEndpointsTests {

    @Test("initiateScrape uses /scrape/comic for comic")
    func initiateScrapeComic() {
        let req = ScrapeRequest(
            url: "https://nhentai.net/g/123",
            sourceKey: "nhentai",
            cookies: [],
            userAgent: "Mozilla/5.0",
            contentType: "comic"
        )
        let ep = Endpoint.initiateScrape(req)
        #expect(ep.path == "/scrape/comic")
        #expect(ep.method == .post)
        #expect(ep.body != nil)
    }

    @Test("initiateScrape uses /scrape/fanfic for fanfic")
    func initiateScrapeFantfic() {
        let req = ScrapeRequest(
            url: "https://archiveofourown.org/works/123",
            sourceKey: "ao3",
            cookies: [],
            userAgent: "Mozilla/5.0",
            contentType: "fanfic"
        )
        let ep = Endpoint.initiateScrape(req)
        #expect(ep.path == "/scrape/fanfic")
        #expect(ep.method == .post)
    }

    @Test("scrapeStatus path embeds jobId")
    func scrapeStatusPath() {
        let jobId = UUID()
        let ep = Endpoint.scrapeStatus(jobId: jobId)
        #expect(ep.path == "/scrape/\(jobId)")
        #expect(ep.method == .get)
    }

    @Test("retryScrape uses POST")
    func retryScrapeMethod() {
        let jobId = UUID()
        let ep = Endpoint.retryScrape(jobId: jobId)
        #expect(ep.path == "/scrape/\(jobId)/retry")
        #expect(ep.method == .post)
    }

    @Test("deltaUpdate uses POST")
    func deltaUpdateMethod() {
        let storyId = UUID()
        let ep = Endpoint.deltaUpdate(storyId: storyId)
        #expect(ep.path == "/scrape/\(storyId)/update")
        #expect(ep.method == .post)
    }

    @Test("allScrapeJobs default pagination")
    func allScrapeJobsPagination() {
        let ep = Endpoint.allScrapeJobs()
        #expect(ep.path == "/scrape")
        #expect(ep.method == .get)
        #expect(queryValue(ep, name: "page") == "1")
        #expect(queryValue(ep, name: "page_size") == "20")
    }

    @Test("allScrapeJobs custom pagination")
    func allScrapeJobsCustom() {
        let ep = Endpoint.allScrapeJobs(page: 2, pageSize: 50)
        #expect(queryValue(ep, name: "page") == "2")
        #expect(queryValue(ep, name: "page_size") == "50")
    }
}

// MARK: - Progress Endpoints

@Suite("Endpoint.progress")
struct ProgressEndpointsTests {

    @Test("updateComicProgress uses PUT")
    func updateComicProgressMethod() {
        let id = UUID()
        let body = ComicProgressRequest(lastChapterNumber: 5, lastPageNumber: 3)
        let ep = Endpoint.updateComicProgress(storyId: id, body: body)
        #expect(ep.path == "/progress/comic/\(id)")
        #expect(ep.method == .put)
        #expect(ep.body != nil)
    }

    @Test("updateFanficProgress uses PUT")
    func updateFanficProgressMethod() {
        let id = UUID()
        let body = FanficProgressRequest(lastChapterNumber: 3, scrollOffsetPercent: 0.7)
        let ep = Endpoint.updateFanficProgress(storyId: id, body: body)
        #expect(ep.path == "/progress/fanfic/\(id)")
        #expect(ep.method == .put)
        #expect(ep.body != nil)
    }

    @Test("getProgress embeds type and storyId")
    func getProgressPath() {
        let id = UUID()
        let ep = Endpoint.getProgress(type: "comic", storyId: id)
        #expect(ep.path == "/progress/comic/\(id)")
        #expect(ep.method == .get)
    }
}

// MARK: - Author & Health Endpoints

@Suite("Endpoint.misc")
struct MiscEndpointsTests {

    @Test("authorDetail path embeds UUID")
    func authorDetailPath() {
        let id = UUID()
        let ep = Endpoint.authorDetail(id: id)
        #expect(ep.path == "/authors/\(id)")
        #expect(ep.method == .get)
    }

    @Test("health endpoint is /health GET")
    func healthEndpoint() {
        let ep = Endpoint.health
        #expect(ep.path == "/health")
        #expect(ep.method == .get)
        #expect(ep.queryItems == nil)
        #expect(ep.body == nil)
    }
}
