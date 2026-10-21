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
    @State private var store = Self.openStore()

    private static func openStore() -> Result<ModelContainer, Error> {
        do {
            try LibraryBackupService.applyPendingRestore()
            let schema = Schema([
                LocalComic.self, LocalComicChapter.self, LocalFanfic.self, LocalFanficChapter.self,
                LocalAuthor.self, UserPreferences.self, LocalScrapeJob.self, LocalBookmark.self,
                LocalReadingSession.self, PendingRemoteDeletion.self,
            ])
            return .success(try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema)]))
        } catch {
            AstralLogger.error("Library could not be opened. Files preserved: \(error)")
            return .failure(error)
        }
    }

    var body: some Scene {
        WindowGroup {
            switch store {
            case .success(let container):
                RootView()
                    .modelContainer(container)
                    .task { ContentBlocker.shared.precompile() }
                    .task {
                        #if DEBUG
                        do { try DevelopmentReaderCorpus.installIfRequested(context: container.mainContext) }
                        catch { AstralLogger.error("Reader fixture creation failed: \(error)") }
                        #endif
                        do { try LocalStorageService.recoverInterruptedRemoval(context: container.mainContext) }
                        catch { AstralLogger.error("Storage recovery needs attention: \(error)") }
                        OrphanCleanupService.cleanOnLaunch(modelContext: container.mainContext)
                        if AppConfig.companionEnabled {
                            PendingDeletionDrainService.drain(modelContext: container.mainContext)
                        }
                    }
            case .failure(let error):
                LibraryRecoveryView(message: error.localizedDescription) { store = Self.openStore() }
            }
        }
    }
}
