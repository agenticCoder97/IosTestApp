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
            // Schema has changed (e.g. a new @Model type was added) and the
            // existing store is incompatible.  For this personal sideloaded app
            // all data is re-scraped from the web, so deleting the store and
            // starting fresh is safe.
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
