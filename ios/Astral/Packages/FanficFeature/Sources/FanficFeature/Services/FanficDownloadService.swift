import Foundation
import SwiftData
import Core
import Networking

@MainActor
public final class FanficDownloadService {
    public static let shared = FanficDownloadService()

    /// Prevents concurrent downloads of the same chapter
    private var activeDownloads: Set<UUID> = []

    /// Minimum free disk space required before downloading (50 MB)
    private let minimumFreeSpace: Int64 = 50 * 1024 * 1024

    private init() {}

    // MARK: - Public API

    /// Downloads a single chapter's text content to local storage.
    public func downloadChapter(
        fanfic: LocalFanfic,
        chapter: LocalFanficChapter,
        modelContext: ModelContext
    ) async {
        guard !activeDownloads.contains(chapter.id) else { return }
        guard chapter.scrapeStatus == "scraped" else { return }

        activeDownloads.insert(chapter.id)
        defer { activeDownloads.remove(chapter.id) }

        chapter.downloadStatus = .queued

        // Check disk space
        do {
            try checkDiskSpace()
        } catch {
            chapter.downloadStatus = .failed
            chapter.downloadError = error.localizedDescription
            try? modelContext.save()
            return
        }

        chapter.downloadStatus = .downloading

        do {
            let response: FanficChapterResponse = try await APIClient.shared.request(
                .fanficChapter(fanficId: fanfic.id, chapterId: chapter.id)
            )

            guard let content = response.content, !content.isEmpty else {
                throw DownloadError.fileValidationFailed("Server returned empty content")
            }

            let relPath = chapterRelativePath(fanficId: fanfic.id, chapterNumber: chapter.chapterNumber)
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let finalURL = documentsURL.appendingPathComponent(relPath)

            // Write to temp file first, then atomic move
            try FileManager.default.createDirectory(
                at: finalURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let tempURL = finalURL.deletingLastPathComponent()
                .appendingPathComponent(UUID().uuidString + ".tmp")
            try content.write(to: tempURL, atomically: true, encoding: .utf8)

            // Validate written file is non-empty
            let attributes = try FileManager.default.attributesOfItem(atPath: tempURL.path)
            guard let fileSize = attributes[.size] as? Int64, fileSize > 0 else {
                try? FileManager.default.removeItem(at: tempURL)
                throw DownloadError.fileValidationFailed("Written file is empty")
            }

            // Atomic move to final path
            if FileManager.default.fileExists(atPath: finalURL.path) {
                try FileManager.default.removeItem(at: finalURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: finalURL)

            // Update model
            chapter.localTextPath = relPath
            chapter.isDownloaded = true
            chapter.downloadStatus = .complete
            chapter.downloadedAt = .now
            chapter.downloadError = nil
            try? modelContext.save()
        } catch {
            chapter.downloadStatus = .failed
            chapter.downloadError = error.localizedDescription
            AstralLogger.error("Download ch \(chapter.chapterNumber) failed: \(error)", context: "FanficDownload")
            try? modelContext.save()
        }
    }

    /// Downloads all pending chapters sequentially, reporting progress via callback.
    public func downloadAllChapters(
        fanfic: LocalFanfic,
        chapters: [LocalFanficChapter],
        modelContext: ModelContext,
        onProgress: @escaping (Int, Int) -> Void
    ) async {
        let pending = chapters.filter { $0.downloadStatus != .complete && $0.scrapeStatus == "scraped" }
        guard !pending.isEmpty else { return }

        for (idx, chapter) in pending.enumerated() {
            await downloadChapter(fanfic: fanfic, chapter: chapter, modelContext: modelContext)
            onProgress(idx + 1, pending.count)
        }

        fanfic.isDownloaded = chapters.allSatisfy { $0.downloadStatus == .complete }
        try? modelContext.save()
    }

    /// Deletes all locally downloaded chapter files and resets download state.
    public func deleteAllChapters(
        fanfic: LocalFanfic,
        chapters: [LocalFanficChapter],
        modelContext: ModelContext
    ) {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        for chapter in chapters {
            if let path = chapter.localTextPath {
                let fileURL = documentsURL.appendingPathComponent(path)
                try? FileManager.default.removeItem(at: fileURL)
            }
            chapter.localTextPath = nil
            chapter.isDownloaded = false
            chapter.downloadStatus = .none
            chapter.downloadedAt = nil
            chapter.downloadError = nil
        }

        // Remove the fanfic's directory if empty
        let fanficDir = documentsURL.appendingPathComponent("fanfics/\(fanfic.id)")
        try? FileManager.default.removeItem(at: fanficDir)

        fanfic.isDownloaded = false
        try? modelContext.save()
    }

    // MARK: - Private Helpers

    /// Formats chapter number: integer chapters use "3", decimal chapters use "3.5"
    private func chapterRelativePath(fanficId: UUID, chapterNumber: Double) -> String {
        let formatted: String
        if chapterNumber.truncatingRemainder(dividingBy: 1) == 0 {
            formatted = "\(Int(chapterNumber))"
        } else {
            formatted = "\(chapterNumber)"
        }
        return "fanfics/\(fanficId)/ch\(formatted).txt"
    }

    /// Checks available disk space and throws if below minimum threshold.
    private func checkDiskSpace() throws {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: documentsURL.path)
        guard let freeSpace = attributes[.systemFreeSize] as? Int64 else { return }

        if freeSpace < minimumFreeSpace {
            throw DownloadError.insufficientDiskSpace
        }
    }
}
