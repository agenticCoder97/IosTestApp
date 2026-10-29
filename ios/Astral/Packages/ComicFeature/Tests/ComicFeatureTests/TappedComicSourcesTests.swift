import Testing
import Foundation
@testable import ComicFeature

@Suite("Comic source URLs")
@MainActor
struct ComicSourceURLTests {
    @Test("MangaFire title and chapter pages import their title")
    func mangaFireCanonical() {
        let title = URL(string: "https://mangafire.to/title/vq0w6-psychopath-in-murim")
        let chapter = URL(string: "https://mangafire.to/title/vq0w6-psychopath-in-murim/chapter/9532998")
        #expect(DeviceComicService.canonical(title, source: "mangafire")?.absoluteString == "https://mangafire.to/title/vq0w6-psychopath-in-murim")
        #expect(DeviceComicService.canonical(chapter, source: "mangafire")?.absoluteString == "https://mangafire.to/title/vq0w6-psychopath-in-murim")
        #expect(DeviceComicService.canonical(URL(string: "https://mangafire.to/browse?keyword=x"), source: "mangafire") == nil)
        #expect(DeviceComicService.canonical(URL(string: "https://evil.example/title/vq0w6-x"), source: "mangafire") == nil)
    }

    @Test("IDs come from the path")
    func ids() {
        #expect(TappedComicSources.MangaFire.titleID(URL(string: "https://mangafire.to/title/vq0w6-psychopath-in-murim")!) == "vq0w6")
        #expect(TappedComicSources.MangaFire.chapterID(URL(string: "https://mangafire.to/title/vq0w6-x/chapter/9532998")!) == "9532998")
        #expect(TappedComicSources.MangaFire.chapterID(URL(string: "https://mangafire.to/title/vq0w6-x")!) == nil)
    }
}

@Suite("MangaFire parsing")
struct MangaFireParsingTests {
    let title = Data(#"""
    {"data":{"title":"Psychopath in Murim","synopsisHtml":"[Welcome]<br>\n<br>\nDong Bongsu&#039;s <b>fangs</b>","poster":{"medium":"https://static.mfcdn.nl/a@280.jpg","large":"https://static.mfcdn.nl/a.jpg"},
    "genres":[{"id":1,"title":"Action"}],"themes":[{"id":2,"title":"Martial Arts"}],"authors":[{"id":3,"title":"Kim Eon"}],"artists":[{"id":4,"title":"Kim Eon"},{"id":5,"title":"Song Beom-Gyu"}]}}
    """#.utf8)

    @Test("pages of the chapter list merge, de-duplicate by number and sort ascending")
    func work() throws {
        let page1 = Data(#"{"items":[{"id":30,"number":35,"name":"S2 - Start"},{"id":20,"number":34.5,"name":""}],"meta":{"page":1,"lastPage":2}}"#.utf8)
        let page2 = Data(#"{"items":[{"id":21,"number":34.5,"name":""},{"id":10,"number":1,"name":null}],"meta":{"page":2,"lastPage":2}}"#.utf8)
        let work = try TappedComicSources.MangaFire.work(title: title, chapterLists: [page1, page2], seriesURL: URL(string: "https://mangafire.to/title/vq0w6-psychopath-in-murim")!)
        #expect(work.title == "Psychopath in Murim")
        #expect(work.description == "[Welcome]\n\nDong Bongsu's fangs")
        #expect(work.cover == "https://static.mfcdn.nl/a.jpg")
        #expect(work.authors == ["Kim Eon", "Song Beom-Gyu"])
        #expect(work.tags.map { $0["name"] } == ["Action", "Martial Arts"])
        #expect(work.chapters.map(\.number) == [1, 34.5, 35])
        #expect(work.chapters.map(\.title) == ["Chapter 1", "Chapter 34.5", "Chapter 35: S2 - Start"])
        #expect(work.chapters.last?.url == "https://mangafire.to/title/vq0w6-psychopath-in-murim/chapter/30")
    }

    @Test("chapter pages are the listed image URLs in order")
    func pages() throws {
        let data = Data(#"{"data":{"id":1,"pages":[{"url":"https://pw6.mfcdn1.xyz/mf/a/h/p.jpg","width":900,"height":1621},{"url":"https://pw6.mfcdn1.xyz/mf/b/h/p.jpg","width":900,"height":1621}]}}"#.utf8)
        #expect(try TappedComicSources.MangaFire.pages(data) == ["https://pw6.mfcdn1.xyz/mf/a/h/p.jpg", "https://pw6.mfcdn1.xyz/mf/b/h/p.jpg"])
    }
}
