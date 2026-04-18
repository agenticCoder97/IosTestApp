import Foundation
import SwiftData
import Core

@MainActor
public enum PendingDeletionDrainService {
    /// Fire-and-forget drain of queued remote deletions.
    /// Called once per launch; failures leave the row in place.
    public static func drain(modelContext: ModelContext) {
        Task { @MainActor in
            let fetch = FetchDescriptor<PendingRemoteDeletion>()
            guard let pending = try? modelContext.fetch(fetch), !pending.isEmpty else { return }

            AstralLogger.info("drain starting | count=\(pending.count)", context: "PendingDelete")

            for record in pending {
                do {
                    switch record.contentType {
                    case "comic":
                        try await APIClient.shared.requestVoid(.permanentDeleteComic(id: record.storyId))
                        modelContext.delete(record)
                        try? modelContext.save()
                    case "fanfic":
                        try await APIClient.shared.requestVoid(.permanentDeleteFanfic(id: record.storyId))
                        modelContext.delete(record)
                        try? modelContext.save()
                    default:
                        AstralLogger.warning("drain unknown contentType, discarding | \(record.contentType)", context: "PendingDelete")
                        modelContext.delete(record)
                        try? modelContext.save()
                    }
                } catch {
                    // Treat 404 as success — backend already has no such id.
                    if let apiError = error as? APIError, case .notFound = apiError {
                        AstralLogger.info("drain treating 404 as success | storyId=\(record.storyId)", context: "PendingDelete")
                        modelContext.delete(record)
                        try? modelContext.save()
                    } else {
                        AstralLogger.warning("drain failed, leaving in queue | storyId=\(record.storyId) error=\(error)", context: "PendingDelete")
                    }
                }
            }
            try? modelContext.save()
            AstralLogger.info("drain done", context: "PendingDelete")
        }
    }
}
