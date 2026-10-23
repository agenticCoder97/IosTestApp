import Foundation
import SwiftData

/// Moves files aside before committing removal. A failed database save restores
/// the original directory, so storage management cannot erase the only copy first.
@MainActor
public enum LocalStorageService {
    public nonisolated static func bytes(in directory: URL) -> Int64 {
        guard let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: [.skipsHiddenFiles]) else { return 0 }
        var result: Int64 = 0
        while let file = files.nextObject() as? URL {
            if let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), values.isRegularFile == true { result += Int64(values.fileSize ?? 0) }
        }
        return result
    }
    private static var journal: URL { URL.applicationSupportDirectory.appendingPathComponent("AstralContentRemoval.json") }
    public static func recoverInterruptedRemoval(context: ModelContext) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: journal.path) else { return }
        let record = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: journal))
        guard let originalPath = record["original"], let heldPath = record["held"],
              originalPath.hasPrefix(URL.documentsDirectory.path + "/"), heldPath.hasPrefix(URL.documentsDirectory.path + "/") else { return }
        let original = URL(fileURLWithPath: originalPath), held = URL(fileURLWithPath: heldPath)
        let relative = String(originalPath.dropFirst(URL.documentsDirectory.path.count + 1))
        let comicReferences = try context.fetch(FetchDescriptor<LocalComicChapter>()).contains { ($0.localPagesPath ?? "").hasPrefix(relative + "/") || $0.localPagesPath == relative }
        let fanficReferences = try context.fetch(FetchDescriptor<LocalFanficChapter>()).contains { ($0.localTextPath ?? "").hasPrefix(relative + "/") }
        if fm.fileExists(atPath: held.path) {
            if comicReferences || fanficReferences {
                if !fm.fileExists(atPath: original.path) { try fm.moveItem(at: held, to: original) }
            } else { try fm.removeItem(at: held) }
        }
        try fm.removeItem(at: journal)
    }
    public static func removeComicCopies(_ comic: LocalComic, context: ModelContext) throws {
        try ensureCopiesCanBeRemoved(sourceKey: comic.sourceKey)
        let id = comic.id
        try ensureIdle(id, context: context)
        let chapters = try context.fetch(FetchDescriptor<LocalComicChapter>(predicate: #Predicate { $0.comicId == id }))
        try context.save()
        let original = URL.documentsDirectory.appendingPathComponent("comics/\(id)")
        let held = try hold(original)
        do {
            for chapter in chapters {
                chapter.localPagesPath = nil; chapter.isDownloaded = false; chapter.downloadStatus = .none
                chapter.downloadedAt = nil; chapter.downloadSizeBytes = nil; chapter.downloadError = nil
            }
            comic.isDownloaded = false
            try context.save()
        } catch { context.rollback(); if let held { try? FileManager.default.moveItem(at: held, to: original) }; throw error }
        if let held { try FileManager.default.removeItem(at: held) }
        try? FileManager.default.removeItem(at: journal)
    }
    public static func removeFanficCopies(_ fanfic: LocalFanfic, context: ModelContext) throws {
        try ensureCopiesCanBeRemoved(sourceKey: fanfic.sourceKey)
        let id = fanfic.id
        try ensureIdle(id, context: context)
        let chapters = try context.fetch(FetchDescriptor<LocalFanficChapter>(predicate: #Predicate { $0.fanficId == id }))
        try context.save()
        let original = URL.documentsDirectory.appendingPathComponent("fanfics/\(id)")
        let held = try hold(original)
        do {
            for chapter in chapters {
                chapter.localTextPath = nil; chapter.isDownloaded = false; chapter.downloadStatus = .none
                chapter.downloadedAt = nil; chapter.downloadError = nil
            }
            fanfic.isDownloaded = false
            try context.save()
        } catch { context.rollback(); if let held { try? FileManager.default.moveItem(at: held, to: original) }; throw error }
        if let held { try FileManager.default.removeItem(at: held) }
        try? FileManager.default.removeItem(at: journal)
    }
    private static func hold(_ original: URL) throws -> URL? {
        guard FileManager.default.fileExists(atPath: original.path) else { return nil }
        let held = original.deletingLastPathComponent().appendingPathComponent(".removing-" + UUID().uuidString)
        try JSONEncoder().encode(["original": original.path, "held": held.path]).write(to: journal, options: .atomic)
        try FileManager.default.moveItem(at: original, to: held)
        return held
    }
    private static func ensureCopiesCanBeRemoved(sourceKey: String) throws {
        guard sourceKey != "local" else {
            throw ComicStoragePolicy.StorageError.message("Keep imported files with their story. Importing them again creates a separate story and does not reconnect this reading position or bookmarks. Export a library backup before deleting the story to free space.")
        }
    }
    public static func ensureIdle(_ id: UUID, context: ModelContext) throws {
        if try context.fetch(FetchDescriptor<LocalScrapeJob>(predicate: #Predicate { $0.storyId == id })).contains(where: { ["running", "queued"].contains($0.status) && ($0.jobType ?? "").hasPrefix("local") }) {
            throw ComicStoragePolicy.StorageError.message("This story has an active import or download. Cancel it in Activity and wait for it to stop before removing content.")
        }
    }
}
