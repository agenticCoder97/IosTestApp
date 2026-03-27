import Foundation
import SwiftData

// Stable UUIDs ensure deterministic Xcode Previews across rebuilds.
@MainActor
public enum PreviewMocks {

    // MARK: - Stable IDs

    private enum IDs {
        // Comics
        static let comic1 = UUID(uuidString: "11111111-0000-0000-0000-000000000001")!
        static let comic2 = UUID(uuidString: "11111111-0000-0000-0000-000000000002")!
        static let comic3 = UUID(uuidString: "11111111-0000-0000-0000-000000000003")!
        // Comic chapters
        static let comicChapter1 = UUID(uuidString: "22222222-0000-0000-0000-000000000001")!
        static let comicChapter2 = UUID(uuidString: "22222222-0000-0000-0000-000000000002")!
        static let comicChapter3 = UUID(uuidString: "22222222-0000-0000-0000-000000000003")!
        static let comicChapter4 = UUID(uuidString: "22222222-0000-0000-0000-000000000004")!
        static let comicChapter5 = UUID(uuidString: "22222222-0000-0000-0000-000000000005")!
        // Fanfics
        static let fanfic1 = UUID(uuidString: "33333333-0000-0000-0000-000000000001")!
        static let fanfic2 = UUID(uuidString: "33333333-0000-0000-0000-000000000002")!
        static let fanfic3 = UUID(uuidString: "33333333-0000-0000-0000-000000000003")!
        // Fanfic chapters
        static let fanficChapter1 = UUID(uuidString: "44444444-0000-0000-0000-000000000001")!
        static let fanficChapter2 = UUID(uuidString: "44444444-0000-0000-0000-000000000002")!
        static let fanficChapter3 = UUID(uuidString: "44444444-0000-0000-0000-000000000003")!
        static let fanficChapter4 = UUID(uuidString: "44444444-0000-0000-0000-000000000004")!
        static let fanficChapter5 = UUID(uuidString: "44444444-0000-0000-0000-000000000005")!
        // Scrape jobs
        static let jobQueued   = UUID(uuidString: "55555555-0000-0000-0000-000000000001")!
        static let jobRunning  = UUID(uuidString: "55555555-0000-0000-0000-000000000002")!
        static let jobComplete = UUID(uuidString: "55555555-0000-0000-0000-000000000003")!
        static let jobPartial  = UUID(uuidString: "55555555-0000-0000-0000-000000000004")!
        static let jobFailed   = UUID(uuidString: "55555555-0000-0000-0000-000000000005")!
        // Authors
        static let author1 = UUID(uuidString: "66666666-0000-0000-0000-000000000001")!
        static let author2 = UUID(uuidString: "66666666-0000-0000-0000-000000000002")!
    }

    // MARK: - Comics

    /// In-progress comic: 45 of 120 chapters read, partial scrape status, no download.
    public static let comic1: LocalComic = {
        let c = LocalComic(
            id: IDs.comic1,
            title: "Solo Leveling",
            sourceKey: "toongod",
            thumbnailPath: "/comics/solo-leveling/cover.jpg",
            totalChapters: 120,
            status: "partial",
            isDownloaded: false,
            lastReadChapterNumber: 45,
            progressPercent: 0.375,
            addedAt: Date(timeIntervalSinceNow: -60 * 60 * 24 * 30)
        )
        return c
    }()

    /// Complete comic: fully downloaded, 200/200 chapters read.
    public static let comic2: LocalComic = {
        let c = LocalComic(
            id: IDs.comic2,
            title: "Tower of God",
            sourceKey: "nhentai",
            thumbnailPath: "/comics/tower-of-god/cover.jpg",
            totalChapters: 200,
            status: "complete",
            isDownloaded: true,
            lastReadChapterNumber: 200,
            progressPercent: 1.0,
            addedAt: Date(timeIntervalSinceNow: -60 * 60 * 24 * 7)
        )
        return c
    }()

    /// Freshly added comic: 0 progress, pending scrape.
    public static let comic3: LocalComic = {
        let c = LocalComic(
            id: IDs.comic3,
            title: "The Beginning After the End",
            sourceKey: "toongod",
            thumbnailPath: nil,
            totalChapters: 0,
            status: "pending",
            isDownloaded: false,
            lastReadChapterNumber: 0,
            progressPercent: 0.0,
            addedAt: Date(timeIntervalSinceNow: -60 * 60 * 2)
        )
        return c
    }()

    public static let sampleComics: [LocalComic] = [comic1, comic2, comic3]

    // MARK: - Comic Chapters

    /// Returns 5 sample chapters for the given comic ID with varied scrape statuses.
    public static func comicChapters(for comicId: UUID) -> [LocalComicChapter] {
        let ids = [IDs.comicChapter1, IDs.comicChapter2, IDs.comicChapter3,
                   IDs.comicChapter4, IDs.comicChapter5]
        let statuses = ["scraped", "scraped", "scraped", "pending", "failed"]
        let titles: [String?] = ["The Awakening", "First Dungeon", "The Red Gate", nil, "Monarch's Domain"]
        return zip(0..<5, ids).map { i, id in
            LocalComicChapter(
                id: id,
                comicId: comicId,
                chapterNumber: Double(i + 1),
                title: titles[i],
                totalPages: [18, 24, 20, 22, 0][i],
                isDownloaded: i < 3,
                scrapeStatus: statuses[i]
            )
        }
    }

    /// Convenience: chapters for `comic1`.
    public static let comic1Chapters: [LocalComicChapter] = comicChapters(for: IDs.comic1)

    // MARK: - Fanfics

    /// AO3, Mature, ongoing, 87K words, 12/30 chapters read.
    public static let fanfic1: LocalFanfic = {
        let f = LocalFanfic(
            id: IDs.fanfic1,
            title: "A Study in Starlight",
            sourceKey: "ao3",
            summary: "Two strangers meet on a rainy night in Hogwarts and discover they have more in common than they ever imagined. A slow-burn romance set in an alternate universe where magic never left the world.",
            fandom: "Harry Potter",
            rating: "M",
            completionStatus: "ongoing",
            wordCount: 87_430,
            totalChapters: 30,
            isDownloaded: false,
            lastReadChapterNumber: 12,
            scrollOffsetPercent: 0.62,
            progressPercent: 0.4,
            addedAt: Date(timeIntervalSinceNow: -60 * 60 * 24 * 14)
        )
        return f
    }()

    /// FFNet, Teen, complete, 120K words, 20/20 chapters read.
    public static let fanfic2: LocalFanfic = {
        let f = LocalFanfic(
            id: IDs.fanfic2,
            title: "The Long Way Round",
            sourceKey: "ffnet",
            summary: "When the war finally ends, rebuilding is harder than anyone expected. A post-canon exploration of grief, found family, and the courage it takes to start over.",
            fandom: "Naruto",
            rating: "T",
            completionStatus: "complete",
            wordCount: 120_950,
            totalChapters: 20,
            isDownloaded: true,
            lastReadChapterNumber: 20,
            scrollOffsetPercent: nil,
            progressPercent: 1.0,
            addedAt: Date(timeIntervalSinceNow: -60 * 60 * 24 * 60)
        )
        return f
    }()

    /// AO3, Explicit, abandoned, 45K words, 5/8 chapters read.
    public static let fanfic3: LocalFanfic = {
        let f = LocalFanfic(
            id: IDs.fanfic3,
            title: "Echoes in the Void",
            sourceKey: "ao3",
            summary: "An experimental fic told through fragmented memories. The last guardian of an ancient order must confront what she lost before she can move forward.",
            fandom: "Attack on Titan",
            rating: "E",
            completionStatus: "abandoned",
            wordCount: 45_100,
            totalChapters: 8,
            isDownloaded: false,
            lastReadChapterNumber: 5,
            scrollOffsetPercent: 0.3,
            progressPercent: 0.625,
            addedAt: Date(timeIntervalSinceNow: -60 * 60 * 24 * 90)
        )
        return f
    }()

    public static let sampleFanfics: [LocalFanfic] = [fanfic1, fanfic2, fanfic3]

    // MARK: - Fanfic Chapters

    /// Returns 5 sample chapters for the given fanfic ID with realistic titles and word counts.
    public static func fanficChapters(for fanficId: UUID) -> [LocalFanficChapter] {
        let ids: [UUID] = [IDs.fanficChapter1, IDs.fanficChapter2, IDs.fanficChapter3,
                           IDs.fanficChapter4, IDs.fanficChapter5]
        let titles: [String?] = ["Prologue: Before the Storm", "Chapter 1: First Encounter",
                                 "Chapter 2: Crossed Paths", "Chapter 3: Hidden Truths", "Chapter 4: The Reckoning"]
        let wordCounts: [Int] = [1_200, 4_800, 5_300, 6_100, 4_950]
        let statuses: [String] = ["scraped", "scraped", "scraped", "scraped", "pending"]
        var result: [LocalFanficChapter] = []
        for i in 0..<5 {
            let chapter = LocalFanficChapter(
                id: ids[i],
                fanficId: fanficId,
                chapterNumber: i == 0 ? 0.5 : Double(i),
                title: titles[i],
                wordCount: wordCounts[i],
                isDownloaded: i < 4,
                localTextPath: i < 4 ? "/fanfics/\(fanficId)/ch\(i).txt" : nil,
                scrapeStatus: statuses[i]
            )
            result.append(chapter)
        }
        return result
    }

    /// Convenience: chapters for `fanfic1`.
    public static let fanfic1Chapters: [LocalFanficChapter] = fanficChapters(for: IDs.fanfic1)

    // MARK: - Scrape Jobs

    public static let scrapeJobQueued: LocalScrapeJob = LocalScrapeJob(
        id: IDs.jobQueued,
        contentType: "comic",
        storyId: IDs.comic3,
        status: "queued",
        chaptersScraped: 0,
        chaptersFailed: 0,
        totalChapters: nil,
        createdAt: Date(timeIntervalSinceNow: -60 * 5)
    )

    public static let scrapeJobRunning: LocalScrapeJob = LocalScrapeJob(
        id: IDs.jobRunning,
        contentType: "comic",
        storyId: IDs.comic1,
        status: "running",
        chaptersScraped: 14,
        chaptersFailed: 0,
        totalChapters: 30,
        createdAt: Date(timeIntervalSinceNow: -60 * 12)
    )

    public static let scrapeJobComplete: LocalScrapeJob = LocalScrapeJob(
        id: IDs.jobComplete,
        contentType: "comic",
        storyId: IDs.comic2,
        status: "complete",
        chaptersScraped: 30,
        chaptersFailed: 0,
        totalChapters: 30,
        createdAt: Date(timeIntervalSinceNow: -60 * 60 * 2),
        completedAt: Date(timeIntervalSinceNow: -60 * 60)
    )

    public static let scrapeJobPartial: LocalScrapeJob = LocalScrapeJob(
        id: IDs.jobPartial,
        contentType: "comic",
        storyId: IDs.comic1,
        status: "partial",
        chaptersScraped: 28,
        chaptersFailed: 2,
        totalChapters: 30,
        createdAt: Date(timeIntervalSinceNow: -60 * 60 * 5),
        completedAt: Date(timeIntervalSinceNow: -60 * 60 * 4)
    )

    public static let scrapeJobFailed: LocalScrapeJob = LocalScrapeJob(
        id: IDs.jobFailed,
        contentType: "comic",
        storyId: IDs.comic3,
        status: "failed",
        chaptersScraped: 0,
        chaptersFailed: 1,
        totalChapters: nil,
        createdAt: Date(timeIntervalSinceNow: -60 * 60 * 24),
        completedAt: Date(timeIntervalSinceNow: -60 * 60 * 23)
    )

    /// All 5 statuses with contentType = "comic".
    public static let comicScrapeJobs: [LocalScrapeJob] = [
        scrapeJobQueued, scrapeJobRunning, scrapeJobComplete, scrapeJobPartial, scrapeJobFailed
    ]

    /// Same 5 statuses re-created with contentType = "fanfic".
    public static let fanficScrapeJobs: [LocalScrapeJob] = {
        let fanficIds = [IDs.fanfic3, IDs.fanfic1, IDs.fanfic2, IDs.fanfic1, IDs.fanfic3]
        let statuses = ["queued", "running", "complete", "partial", "failed"]
        let scraped = [0, 14, 30, 28, 0]
        let failed  = [0,  0,  0,  2, 1]
        let totals: [Int?] = [nil, 30, 30, 30, nil]
        return (0..<5).map { i in
            LocalScrapeJob(
                id: UUID(),
                contentType: "fanfic",
                storyId: fanficIds[i],
                status: statuses[i],
                chaptersScraped: scraped[i],
                chaptersFailed: failed[i],
                totalChapters: totals[i],
                createdAt: Date(timeIntervalSinceNow: Double(-60 * 60 * (i + 1)))
            )
        }
    }()

    // MARK: - Authors

    public static let author1 = LocalAuthor(
        id: IDs.author1,
        name: "Chugong",
        updatedAt: Date(timeIntervalSinceNow: -60 * 60 * 24 * 30)
    )

    public static let author2 = LocalAuthor(
        id: IDs.author2,
        name: "SIU",
        updatedAt: Date(timeIntervalSinceNow: -60 * 60 * 24 * 7)
    )

    // MARK: - UserPreferences

    public static let defaultPrefs = UserPreferences(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        comicScrollDirection: "vertical",
        fanficFontSize: 16.0,
        fanficLineHeight: 1.6,
        fanficBackground: "dark",
        readerBrightness: 1.0
    )

    public static let sepiaPrefs = UserPreferences(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        comicScrollDirection: "horizontal",
        fanficFontSize: 18.0,
        fanficLineHeight: 1.8,
        fanficBackground: "sepia",
        readerBrightness: 0.8
    )
}

// MARK: - Preview ModelContainer

@MainActor
extension ModelContainer {
    /// In-memory container pre-seeded with mock objects for SwiftUI Previews.
    public static func previewContainer(
        comics: [LocalComic] = [],
        comicChapters: [LocalComicChapter] = [],
        fanfics: [LocalFanfic] = [],
        fanficChapters: [LocalFanficChapter] = [],
        scrapeJobs: [LocalScrapeJob] = [],
        authors: [LocalAuthor] = []
    ) -> ModelContainer {
        let schema = Schema([
            LocalComic.self,
            LocalComicChapter.self,
            LocalFanfic.self,
            LocalFanficChapter.self,
            LocalScrapeJob.self,
            LocalAuthor.self,
            UserPreferences.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        // swiftlint:disable:next force_try
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        comics.forEach { context.insert($0) }
        comicChapters.forEach { context.insert($0) }
        fanfics.forEach { context.insert($0) }
        fanficChapters.forEach { context.insert($0) }
        scrapeJobs.forEach { context.insert($0) }
        authors.forEach { context.insert($0) }
        return container
    }
}
