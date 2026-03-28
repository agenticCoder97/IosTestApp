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
            LocalBookmark.self,
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
            AstralLogger.warning("SwiftData store incompatible — deleting and recreating: \(error)")
            let storeURL = modelConfiguration.url
            try? FileManager.default.removeItem(at: storeURL)
            // SQLite also writes -wal and -shm sidecar files; remove them too.
            for suffix in ["-wal", "-shm"] {
                try? FileManager.default.removeItem(
                    at: storeURL.deletingLastPathComponent()
                        .appending(path: storeURL.lastPathComponent + suffix)
                )
            }
            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch let retryError {
                AstralLogger.error("ModelContainer creation failed after retry: \(retryError)")
                fatalError("Could not create ModelContainer: \(retryError)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(sharedModelContainer)
    }
}
