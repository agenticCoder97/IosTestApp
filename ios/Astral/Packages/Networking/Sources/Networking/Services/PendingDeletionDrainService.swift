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
                    case "fanfic":
                        try await APIClient.shared.requestVoid(.permanentDeleteFanfic(id: record.storyId))
                        modelContext.delete(record)
                    default:
                        AstralLogger.warning("drain unknown contentType, discarding | \(record.contentType)", context: "PendingDelete")
                        modelContext.delete(record)
                    }
                } catch {
                    AstralLogger.warning("drain failed, leaving in queue | storyId=\(record.storyId) error=\(error)", context: "PendingDelete")
                }
            }
            try? modelContext.save()
            AstralLogger.info("drain done", context: "PendingDelete")
        }
    }
}
