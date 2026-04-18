import SwiftUI
import SwiftData
import Core
import DesignSystem
import Networking

class AstralAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        BackgroundDownloadSession.shared.systemCompletionHandler = completionHandler
    }
}

@main
struct AstralApp: App {
    @UIApplicationDelegateAdaptor(AstralAppDelegate.self) var appDelegate
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
            LocalReadingSession.self,
            PendingRemoteDeletion.self,
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
                .task { ContentBlocker.shared.precompile() }
                .task {
                    let context = sharedModelContainer.mainContext
                    OrphanCleanupService.cleanOnLaunch(modelContext: context)
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
