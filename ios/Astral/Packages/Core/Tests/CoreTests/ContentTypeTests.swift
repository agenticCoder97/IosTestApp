import Testing
import Foundation
@testable import Core

// MARK: - ContentType enum

@Suite("ContentType")
struct ContentTypeTests {
    @Test("all raw values are correct")
    func allRawValues() {
        #expect(ContentType.comic.rawValue == "comic")
        #expect(ContentType.fanfic.rawValue == "fanfic")
    }
}

// MARK: - ScrapeStatus enum

@Suite("ScrapeStatus")
struct ScrapeStatusTests {
    @Test("all raw values are correct")
    func allRawValues() {
        #expect(ScrapeStatus.pending.rawValue == "pending")
        #expect(ScrapeStatus.scraped.rawValue == "scraped")
        #expect(ScrapeStatus.failed.rawValue == "failed")
    }

    @Test("initialises from raw string")
    func initFromRawValue() {
        #expect(ScrapeStatus(rawValue: "pending") == .pending)
        #expect(ScrapeStatus(rawValue: "scraped") == .scraped)
        #expect(ScrapeStatus(rawValue: "bogus") == nil)
    }
}

// MARK: - JobStatus enum

@Suite("JobStatus")
struct JobStatusTests {
    @Test("all cases present")
    func allCases() {
        let expected = Set(["queued", "running", "partial", "complete", "failed"])
        let actual = Set(JobStatus.allCases.map { $0.rawValue })
        #expect(actual == expected)
    }
}

// MARK: - JobType enum

@Suite("JobType")
struct JobTypeTests {
    @Test("all raw values correct")
    func rawValues() {
        #expect(JobType.initial.rawValue == "initial")
        #expect(JobType.delta.rawValue == "delta")
        #expect(JobType.retry.rawValue == "retry")
    }
}

// MARK: - ComicSource enum

@Suite("ComicSource")
struct ComicSourceTests {
    @Test("nhentai raw value")
    func nhentaiRawValue() {
        #expect(ComicSource.nhentai.rawValue == "nhentai")
    }

    @Test("toongod raw value")
    func toongodRawValue() {
        #expect(ComicSource.toongod.rawValue == "toongod")
    }
}

// MARK: - FanficSource enum

@Suite("FanficSource")
struct FanficSourceTests {
    @Test("ao3 raw value")
    func ao3RawValue() {
        #expect(FanficSource.ao3.rawValue == "ao3")
    }

    @Test("ffnet raw value")
    func ffnetRawValue() {
        #expect(FanficSource.ffnet.rawValue == "ffnet")
    }
}

// MARK: - FanficRating enum

@Suite("FanficRating")
struct FanficRatingTests {
    @Test("all ratings present")
    func allRatings() {
        let cases = FanficRating.allCases.map { $0.rawValue }
        #expect(cases.contains("G"))
        #expect(cases.contains("T"))
        #expect(cases.contains("M"))
        #expect(cases.contains("E"))
    }
}

// MARK: - CompletionStatus enum

@Suite("CompletionStatus")
struct CompletionStatusTests {
    @Test("ongoing and complete present")
    func basicStatuses() {
        #expect(CompletionStatus.ongoing.rawValue == "ongoing")
        #expect(CompletionStatus.complete.rawValue == "complete")
    }
}

// MARK: - ScrollDirection enum

@Suite("ScrollDirection")
struct ScrollDirectionTests {
    @Test("vertical and horizontal")
    func directions() {
        #expect(ScrollDirection.vertical.rawValue == "vertical")
        #expect(ScrollDirection.horizontal.rawValue == "horizontal")
    }
}
