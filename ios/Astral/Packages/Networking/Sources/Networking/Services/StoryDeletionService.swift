import Foundation
import SwiftData
import Core

/// Orchestrates permanent deletion of a story (comic or fanfic).
/// Local SwiftData + downloaded files are purged first; backend
/// call is attempted and, on failure, queued for launch-time retry.
@MainActor
public final class StoryDeletionService {
    public static let shared = StoryDeletionService()
    private init() {}

    public func permanentlyDelete(
        comic: LocalComic,
        modelContext: ModelContext,
        deleteFiles: @escaping () -> Void
    ) async {
        let id = comic.id
        AstralLogger.info("permanentlyDelete comic | id=\(id)", context: "StoryDeletion")

        deleteFiles()
        await purgeLocalReferences(storyId: id, contentType: "comic", modelContext: modelContext)
        modelContext.delete(comic)
        try? modelContext.save()

        do {
            try await APIClient.shared.requestVoid(.permanentDeleteComic(id: id))
            AstralLogger.info("permanentlyDelete comic backend ok | id=\(id)", context: "StoryDeletion")
        } catch {
            AstralLogger.warning("permanentlyDelete comic backend failed, queueing | id=\(id) error=\(error)", context: "StoryDeletion")
            modelContext.insert(PendingRemoteDeletion(storyId: id, contentType: "comic"))
            try? modelContext.save()
        }
    }

    public func permanentlyDelete(
        fanfic: LocalFanfic,
        modelContext: ModelContext,
        deleteFiles: @escaping () -> Void
    ) async {
        let id = fanfic.id
        AstralLogger.info("permanentlyDelete fanfic | id=\(id)", context: "StoryDeletion")

        deleteFiles()
        await purgeLocalReferences(storyId: id, contentType: "fanfic", modelContext: modelContext)
        modelContext.delete(fanfic)
        try? modelContext.save()

        do {
            try await APIClient.shared.requestVoid(.permanentDeleteFanfic(id: id))
            AstralLogger.info("permanentlyDelete fanfic backend ok | id=\(id)", context: "StoryDeletion")
        } catch {
            AstralLogger.warning("permanentlyDelete fanfic backend failed, queueing | id=\(id) error=\(error)", context: "StoryDeletion")
            modelContext.insert(PendingRemoteDeletion(storyId: id, contentType: "fanfic"))
            try? modelContext.save()
        }
    }

    private func purgeLocalReferences(storyId: UUID, contentType: String, modelContext: ModelContext) async {
        let targetStoryId = storyId
        let targetContentType = contentType

        let bookmarkFetch = FetchDescriptor<LocalBookmark>(
            predicate: #Predicate { $0.storyId == targetStoryId && $0.contentType == targetContentType }
        )
        if let bookmarks = try? modelContext.fetch(bookmarkFetch) {
            bookmarks.forEach { modelContext.delete($0) }
        }

        let sessionFetch = FetchDescriptor<LocalReadingSession>(
            predicate: #Predicate { $0.storyId == targetStoryId && $0.contentType == targetContentType }
        )
        if let sessions = try? modelContext.fetch(sessionFetch) {
            sessions.forEach { modelContext.delete($0) }
        }

        let scrapeFetch = FetchDescriptor<LocalScrapeJob>(
            predicate: #Predicate { $0.storyId == targetStoryId }
        )
        if let jobs = try? modelContext.fetch(scrapeFetch) {
            jobs.forEach { modelContext.delete($0) }
        }
    }
}
