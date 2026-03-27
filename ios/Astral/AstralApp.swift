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

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(sharedModelContainer)
    }
}
