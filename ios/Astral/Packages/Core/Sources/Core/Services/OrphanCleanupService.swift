import Foundation
import SwiftData

/// Reconciles on-disk downloaded files with SwiftData state on app launch.
/// Removes orphaned files and resets stale download states.
public final class OrphanCleanupService {

    nonisolated(unsafe) private static let fileManager = FileManager.default

    private static var documentsDir: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static var tempDownloadDir: URL {
        fileManager.temporaryDirectory.appendingPathComponent("astral-downloads")
    }

    /// Run all cleanup tasks. Call once on app launch.
    @MainActor
    public static func cleanOnLaunch(modelContext: ModelContext) {
        cleanTempDirectory()
        reconcileComicDownloads(modelContext: modelContext)
        reconcileFanficDownloads(modelContext: modelContext)
        migrateFanficChapterPaths(modelContext: modelContext)
        AstralLogger.info("OrphanCleanupService: cleanup complete", context: "Cleanup")
    }

    // MARK: - Temp Cleanup

    private static func cleanTempDirectory() {
        if fileManager.fileExists(atPath: tempDownloadDir.path) {
            try? fileManager.removeItem(at: tempDownloadDir)
            AstralLogger.info("Cleaned temp download directory", context: "Cleanup")
        }
    }

    // MARK: - Comic Reconciliation

    @MainActor
    private static func reconcileComicDownloads(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<LocalComicChapter>()
        guard let chapters = try? modelContext.fetch(descriptor) else { return }

        for chapter in chapters where chapter.downloadStatus == .complete {
            guard let path = chapter.localPagesPath else {
                chapter.downloadStatus = .none
                chapter.isDownloaded = false
                continue
            }
            let dir = documentsDir.appendingPathComponent(path)
            if !fileManager.fileExists(atPath: dir.path) {
                chapter.localPagesPath = nil
                chapter.downloadStatus = .none
                chapter.isDownloaded = false
                chapter.downloadedAt = nil
                chapter.downloadSizeBytes = nil
                AstralLogger.warning("Reset orphaned comic chapter \(chapter.id): files missing", context: "Cleanup")
            }
        }

        // Reset stuck "downloading" or "queued" states (app was killed mid-download)
        for chapter in chapters where chapter.downloadStatus == .downloading || chapter.downloadStatus == .queued {
            chapter.downloadStatus = .none
            chapter.downloadError = "Interrupted — app was closed during download"
        }

        try? modelContext.save()
    }

    // MARK: - Fanfic Reconciliation

    @MainActor
    private static func reconcileFanficDownloads(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<LocalFanficChapter>()
        guard let chapters = try? modelContext.fetch(descriptor) else { return }

        for chapter in chapters where chapter.downloadStatus == .complete {
            guard let path = chapter.localTextPath else {
                chapter.downloadStatus = .none
                chapter.isDownloaded = false
                continue
            }
            let file = documentsDir.appendingPathComponent(path)
            if !fileManager.fileExists(atPath: file.path) {
                chapter.localTextPath = nil
                chapter.downloadStatus = .none
                chapter.isDownloaded = false
                chapter.downloadedAt = nil
                AstralLogger.warning("Reset orphaned fanfic chapter \(chapter.id): file missing", context: "Cleanup")
            }
        }

        for chapter in chapters where chapter.downloadStatus == .downloading || chapter.downloadStatus == .queued {
            chapter.downloadStatus = .none
            chapter.downloadError = "Interrupted — app was closed during download"
        }

        try? modelContext.save()
    }

    // MARK: - Migration: Fanfic Int→Double Filenames

    @MainActor
    private static func migrateFanficChapterPaths(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<LocalFanficChapter>()
        guard let chapters = try? modelContext.fetch(descriptor) else { return }

        for chapter in chapters {
            guard let path = chapter.localTextPath else { continue }
            let hasDecimal = chapter.chapterNumber.truncatingRemainder(dividingBy: 1) != 0
            guard hasDecimal else { continue }

            let intName = "ch\(Int(chapter.chapterNumber)).txt"
            let correctName = "ch\(String(format: "%.1f", chapter.chapterNumber)).txt"

            if path.hasSuffix(intName) {
                let oldURL = documentsDir.appendingPathComponent(path)
                let newPath = path.replacingOccurrences(of: intName, with: correctName)
                let newURL = documentsDir.appendingPathComponent(newPath)

                if fileManager.fileExists(atPath: oldURL.path) {
                    try? fileManager.moveItem(at: oldURL, to: newURL)
                    chapter.localTextPath = newPath
                    AstralLogger.info("Migrated fanfic chapter path: \(intName) → \(correctName)", context: "Cleanup")
                }
            }
        }
        try? modelContext.save()
    }
}
