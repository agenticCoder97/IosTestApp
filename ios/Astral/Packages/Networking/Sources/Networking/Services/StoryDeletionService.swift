import Foundation
import SwiftData
import Observation
import Core

/// Commits model deletion and a tombstone before removing saved files. A failed
/// database save rolls back without touching the sole on-device content copy.
@MainActor @Observable
public final class StoryDeletionService {
    public static let shared = StoryDeletionService()
    public private(set) var errorMessage: String?
    private init() {}
    public func clearError() { errorMessage = nil }

    public func permanentlyDelete(comic: LocalComic, modelContext: ModelContext, deleteFiles: @MainActor @escaping () -> Void) async {
        await delete(story: comic, id: comic.id, type: "comic", remote: !["local", "mangadex-device", "nhentai", "toongod", "hentai20"].contains(comic.sourceKey), context: modelContext)
    }
    public func permanentlyDelete(fanfic: LocalFanfic, modelContext: ModelContext, deleteFiles: @MainActor @escaping () -> Void) async {
        await delete(story: fanfic, id: fanfic.id, type: "fanfic", remote: !["ao3", "ffnet", "local"].contains(fanfic.sourceKey), context: modelContext)
    }
    private func delete<T: PersistentModel>(story: T, id: UUID, type: String, remote: Bool, context: ModelContext) async {
        do {
            try LocalStorageService.ensureIdle(id, context: context)
            try context.save()
            let bookmarks = try context.fetch(FetchDescriptor<LocalBookmark>(predicate: #Predicate { $0.storyId == id }))
            let sessions = try context.fetch(FetchDescriptor<LocalReadingSession>(predicate: #Predicate { $0.storyId == id }))
            let jobs = try context.fetch(FetchDescriptor<LocalScrapeJob>(predicate: #Predicate { $0.storyId == id }))
            bookmarks.forEach { context.delete($0) }; sessions.forEach { context.delete($0) }; jobs.forEach { context.delete($0) }
            if remote { context.insert(PendingRemoteDeletion(storyId: id, contentType: type)) }
            context.delete(story)
            try context.save()
        } catch {
            context.rollback(); errorMessage = "The story could not be deleted. Saved files were retained. " + error.localizedDescription
            return
        }
        let directory = URL.documentsDirectory.appendingPathComponent((type == "comic" ? "comics/" : "fanfics/") + id.uuidString)
        do { if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) } }
        catch { errorMessage = "The story was removed from the library, but its files could not be removed: " + error.localizedDescription }
        if type == "comic" { try? FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent("comicSources/" + id.uuidString)) }
        if type == "fanfic" { try? FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent("fanficCovers/" + id.uuidString + ".jpg")) }
        guard remote, AppConfig.companionEnabled else { return }
        do {
            try await APIClient.shared.requestVoid(type == "comic" ? .permanentDeleteComic(id: id) : .permanentDeleteFanfic(id: id))
        } catch { AstralLogger.warning("Companion deletion pending; local tombstone retained.", context: "Deletion") }
    }
}
