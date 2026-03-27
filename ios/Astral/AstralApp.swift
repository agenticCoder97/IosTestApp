import SwiftUI
import SwiftData
import Core

@main
struct AstralApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            LocalComic.self,
            LocalComicChapter.self,
            LocalFanfic.self,
            LocalFanficChapter.self,
            LocalAuthor.self,
            UserPreferences.self,
            LocalScrapeJob.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            return try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    @MainActor
    private func insertMockData(context: ModelContext) {
        let comicFetch = FetchDescriptor<LocalComic>()
        let fanficFetch = FetchDescriptor<LocalFanfic>()
        let comicCount = try? context.fetchCount(comicFetch)
        let fanficCount = try? context.fetchCount(fanficFetch)

        if (comicCount ?? 0) == 0 {
            let comicId = UUID()
            let comic = LocalComic(
                id: comicId,
                title: "Solo Leveling: System Logs",
                sourceKey: "toongod",
                thumbnailPath: "https://via.placeholder.com/300x400/18181A/E2E2E2?text=Solo+Logs",
                totalChapters: 3,
                status: "ongoing",
                isDownloaded: false,
                lastReadChapterNumber: 1,
                progressPercent: 0.33
            )
            context.insert(comic)

            // Pre-seed 3 Mock Chapters
            for i in 1...3 {
                let status = i == 1 ? "completed" : "pending"
                let chapter = LocalComicChapter(
                    id: UUID(),
                    comicId: comicId,
                    chapterNumber: Double(i),
                    title: "Chapter \(i): Awakening \(i)",
                    totalPages: 24,
                    isDownloaded: (i == 1),
                    scrapeStatus: status
                )
                context.insert(chapter)
                chapter.comic = comic
            }
        }

        if (fanficCount ?? 0) == 0 {
            let fanficId = UUID()
            let fanfic = LocalFanfic(
                id: fanficId,
                title: "Harry Potter and the Methods of Rationality",
                sourceKey: "ffnet",
                summary: "Petunia married a biochemist, and Harry grew up reading science and science fiction. Then came the letter to Hogwarts...",
                fandom: "Harry Potter",
                rating: "T",
                completionStatus: "completed",
                wordCount: 661619,
                totalChapters: 3,
                isDownloaded: true,
                lastReadChapterNumber: 2,
                scrollOffsetPercent: 0.5,
                progressPercent: 0.66
            )
            context.insert(fanfic)

            // Pre-seed 3 Fanfic Chapters
            let chapterTitles = ["A Day of Very Low Probability", "Everything I Believe Is False", "Comparing Reality To Its Alternatives"]
            for i in 1...3 {
                let chapter = LocalFanficChapter(
                    id: UUID(),
                    fanficId: fanficId,
                    chapterNumber: Double(i),
                    title: "Chapter \(i): \(chapterTitles[i-1])",
                    wordCount: 3450 + (i * 1200),
                    isDownloaded: true,
                    localTextPath: "/mock/documents/fic_chapter_\(i).txt",
                    scrapeStatus: "completed"
                )
                context.insert(chapter)
                chapter.fanfic = fanfic
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .onAppear {
                    insertMockData(context: sharedModelContainer.mainContext)
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
