import Foundation
import SwiftData

/// Shared reservations prevent concurrent imports/downloads from taking the same offline slot.
@MainActor
public enum ComicStoragePolicy {
    private struct Reservation { let story: UUID; var bytes: Int64 = 0 }
    private static var reservations: [UUID: Reservation] = [:]
    public static var limit: Int { max(1, min(100, UserDefaults.standard.object(forKey: "comicOfflineLimit") as? Int ?? 2)) }
    public static func savedIDs(context: ModelContext) throws -> Set<UUID> {
        Set(try context.fetch(FetchDescriptor<LocalComicChapter>()).filter { $0.localPagesPath != nil }.map(\.comicId))
    }
    public static func acquire(story: UUID, context: ModelContext) throws -> UUID {
        // Older saved chapters may predate byte accounting; measure those copies once.
        for chapter in try context.fetch(FetchDescriptor<LocalComicChapter>()) where chapter.downloadSizeBytes == nil {
            if let path = chapter.localPagesPath { chapter.downloadSizeBytes = LocalStorageService.bytes(in: URL.documentsDirectory.appendingPathComponent(path)) }
        }
        let saved = try savedIDs(context: context)
        let occupied = saved.union(reservations.values.map(\.story))
        guard occupied.contains(story) || occupied.count < limit else {
            throw StorageError.message("Your offline limit is \(limit) comics. Remove saved pages in Settings → Manage saved content, or increase the limit. Library entries and reading positions can stay.")
        }
        let token = UUID(); reservations[token] = Reservation(story: story); return token
    }
    public static func release(_ token: UUID) { reservations.removeValue(forKey: token) }
    public static func reserve(bytes: Int64, token: UUID, context: ModelContext) throws {
        guard let reservation = reservations[token] else { throw CancellationError() }
        let saved = try savedIDs(context: context)
        // A lowered limit never erases an existing saved comic. New reservations must still fit.
        if !saved.contains(reservation.story) {
            let other = saved.union(reservations.filter { $0.key != token }.values.map(\.story)).subtracting([reservation.story])
            guard other.count < limit else { throw StorageError.message("The offline comic limit changed. Free a slot in Storage or raise the limit, then retry.") }
        }
        let stored = try context.fetch(FetchDescriptor<LocalComicChapter>()).reduce(Int64(0)) { $0 + ($1.downloadSizeBytes ?? 0) }
        let pending = reservations.values.reduce(Int64(0)) { $0 + $1.bytes }
        guard stored + pending + bytes <= AppConfig.comicDownloadLimitBytes else {
            throw StorageError.message("The comic storage budget is full. Remove saved pages or increase the comic GB budget in Settings.")
        }
        reservations[token]?.bytes += bytes
    }
    public enum StorageError: LocalizedError {
        case message(String)
        public var errorDescription: String? { if case .message(let text) = self { text } else { nil } }
    }
}
