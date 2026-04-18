import Testing
import Foundation
@testable import Core

@Suite("LocalFanfic")
struct LocalFanficTests {

    // MARK: - Initialiser defaults

    @Test("default values are set correctly")
    func defaultValues() {
        let fanfic = LocalFanfic(id: UUID(), title: "Test", sourceKey: "ao3")
        #expect(fanfic.completionStatus == "ongoing")
        #expect(fanfic.totalChapters == 0)
        #expect(fanfic.isDownloaded == false)
        #expect(fanfic.lastReadChapterNumber == nil)
        #expect(fanfic.progressPercent == 0.0)
        #expect(fanfic.isFavorite == false)
        #expect(fanfic.seenTotalChapters == 0)
        #expect(fanfic.lastReadAt == nil)
        #expect(fanfic.scrollOffsetPercent == nil)
        #expect(fanfic.wordCount == nil)
        #expect(fanfic.summary == nil)
        #expect(fanfic.fandom == nil)
    }

    @Test("stores all provided values")
    func storedValues() {
        let id = UUID()
        let fanfic = LocalFanfic(
            id: id,
            title: "A Study in Starlight",
            sourceKey: "ao3",
            summary: "A slow-burn romance.",
            fandom: "Harry Potter",
            rating: "M",
            completionStatus: "ongoing",
            wordCount: 87_430,
            totalChapters: 30,
            isDownloaded: false,
            lastReadChapterNumber: 12,
            scrollOffsetPercent: 0.62,
            progressPercent: 0.4,
            isFavorite: true,
            seenTotalChapters: 28
        )
        #expect(fanfic.id == id)
        #expect(fanfic.title == "A Study in Starlight")
        #expect(fanfic.fandom == "Harry Potter")
        #expect(fanfic.wordCount == 87_430)
        #expect(fanfic.scrollOffsetPercent == 0.62)
        #expect(fanfic.isFavorite == true)
        #expect(fanfic.seenTotalChapters == 28)
    }

    // MARK: - newChapterCount

    @Test("newChapterCount is zero when up to date")
    func newChapterCountZero() {
        let fanfic = LocalFanfic(
            id: UUID(), title: "T", sourceKey: "ao3",
            totalChapters: 30, seenTotalChapters: 30
        )
        #expect(fanfic.newChapterCount == 0)
    }

    @Test("newChapterCount shows new chapter delta")
    func newChapterCountPositive() {
        let fanfic = LocalFanfic(
            id: UUID(), title: "T", sourceKey: "ao3",
            totalChapters: 30, seenTotalChapters: 28
        )
        #expect(fanfic.newChapterCount == 2)
    }

    @Test("newChapterCount never negative")
    func newChapterCountNeverNegative() {
        let fanfic = LocalFanfic(
            id: UUID(), title: "T", sourceKey: "ao3",
            totalChapters: 5, seenTotalChapters: 10
        )
        #expect(fanfic.newChapterCount == 0)
    }

    // MARK: - estimatedWordsRead

    @Test("estimatedWordsRead is zero when no word count")
    func estimatedWordsReadNoWordCount() {
        let fanfic = LocalFanfic(
            id: UUID(), title: "T", sourceKey: "ao3",
            totalChapters: 10, progressPercent: 0.5
        )
        #expect(fanfic.estimatedWordsRead == 0)
    }

    @Test("estimatedWordsRead is zero when no chapters")
    func estimatedWordsReadNoChapters() {
        let fanfic = LocalFanfic(
            id: UUID(), title: "T", sourceKey: "ao3",
            wordCount: 10000, totalChapters: 0, progressPercent: 0.5
        )
        #expect(fanfic.estimatedWordsRead == 0)
    }

    @Test("estimatedWordsRead equals wordCount when fully read")
    func estimatedWordsReadComplete() {
        let fanfic = LocalFanfic(
            id: UUID(), title: "T", sourceKey: "ao3",
            wordCount: 100_000, totalChapters: 20, progressPercent: 1.0
        )
        #expect(fanfic.estimatedWordsRead == 100_000)
    }

    @Test("estimatedWordsRead is proportional to progress")
    func estimatedWordsReadProportional() {
        let fanfic = LocalFanfic(
            id: UUID(), title: "T", sourceKey: "ao3",
            wordCount: 80_000, totalChapters: 10, progressPercent: 0.5
        )
        #expect(fanfic.estimatedWordsRead == 40_000)
    }

    // MARK: - isFavorite

    @Test("isFavorite defaults to false")
    func isFavoriteDefault() {
        let fanfic = LocalFanfic(id: UUID(), title: "T", sourceKey: "ao3")
        #expect(fanfic.isFavorite == false)
    }

    @Test("isFavorite can be set")
    func isFavoriteSet() {
        let fanfic = LocalFanfic(id: UUID(), title: "T", sourceKey: "ao3", isFavorite: true)
        #expect(fanfic.isFavorite == true)
    }
}
