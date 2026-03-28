import Testing
import Foundation
@testable import Core

@Suite("LocalComic")
struct LocalComicTests {

    // MARK: - Initialiser defaults

    @Test("default values are set correctly")
    func defaultValues() {
        let comic = LocalComic(id: UUID(), title: "Test", sourceKey: "nhentai")
        #expect(comic.totalChapters == 0)
        #expect(comic.status == "pending")
        #expect(comic.isDownloaded == false)
        #expect(comic.lastReadChapterNumber == 0)
        #expect(comic.progressPercent == 0.0)
        #expect(comic.isFavorite == false)
        #expect(comic.seenTotalChapters == 0)
        #expect(comic.lastReadAt == nil)
        #expect(comic.thumbnailPath == nil)
    }

    @Test("stores all provided values")
    func storedValues() {
        let id = UUID()
        let now = Date()
        let comic = LocalComic(
            id: id,
            title: "Solo Leveling",
            sourceKey: "toongod",
            thumbnailPath: "/path/cover.jpg",
            totalChapters: 120,
            status: "partial",
            isDownloaded: true,
            lastReadChapterNumber: 45,
            progressPercent: 0.375,
            addedAt: now,
            isFavorite: true,
            seenTotalChapters: 115,
            lastReadAt: now
        )
        #expect(comic.id == id)
        #expect(comic.title == "Solo Leveling")
        #expect(comic.sourceKey == "toongod")
        #expect(comic.thumbnailPath == "/path/cover.jpg")
        #expect(comic.totalChapters == 120)
        #expect(comic.isFavorite == true)
        #expect(comic.seenTotalChapters == 115)
        #expect(comic.lastReadAt != nil)
    }

    // MARK: - newChapterCount

    @Test("newChapterCount is zero when seen equals total")
    func newChapterCountZero() {
        let comic = LocalComic(
            id: UUID(), title: "T", sourceKey: "s",
            totalChapters: 50, seenTotalChapters: 50
        )
        #expect(comic.newChapterCount == 0)
    }

    @Test("newChapterCount returns difference when new chapters arrive")
    func newChapterCountPositive() {
        let comic = LocalComic(
            id: UUID(), title: "T", sourceKey: "s",
            totalChapters: 120, seenTotalChapters: 115
        )
        #expect(comic.newChapterCount == 5)
    }

    @Test("newChapterCount never goes negative")
    func newChapterCountNeverNegative() {
        // Edge case: seenTotalChapters somehow exceeds totalChapters
        let comic = LocalComic(
            id: UUID(), title: "T", sourceKey: "s",
            totalChapters: 10, seenTotalChapters: 15
        )
        #expect(comic.newChapterCount == 0)
    }

    // MARK: - isFavorite toggle

    @Test("isFavorite toggles correctly")
    func isFavoriteToggle() {
        let comic = LocalComic(id: UUID(), title: "T", sourceKey: "s", isFavorite: false)
        comic.isFavorite = true
        #expect(comic.isFavorite == true)
        comic.isFavorite = false
        #expect(comic.isFavorite == false)
    }

    // MARK: - lastReadAt

    @Test("lastReadAt can be set and read back")
    func lastReadAt() {
        let comic = LocalComic(id: UUID(), title: "T", sourceKey: "s")
        #expect(comic.lastReadAt == nil)
        let now = Date()
        comic.lastReadAt = now
        #expect(comic.lastReadAt != nil)
    }
}
