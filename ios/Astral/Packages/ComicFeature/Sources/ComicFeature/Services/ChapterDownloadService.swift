import Foundation
import SwiftData
import Core
import Networking

/// Downloads comic chapter pages to device Documents directory for offline reading.
@MainActor
final class ChapterDownloadService {
    static let shared = ChapterDownloadService()
    private init() {}

    private let fileManager = FileManager.default
    private var activeDownloads: Set<UUID> = []

    private var documentsDir: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var tempDownloadDir: URL {
        fileManager.temporaryDirectory.appendingPathComponent("astral-downloads")
    }

    // MARK: - Download

    /// Download all pages for a single chapter with atomic completion.
    func downloadChapter(
        comicId: UUID,
        chapter: LocalComicChapter,
        modelContext: ModelContext
    ) async throws {
        guard !activeDownloads.contains(chapter.id) else { return }
        activeDownloads.insert(chapter.id)
        defer { activeDownloads.remove(chapter.id) }

        chapter.downloadStatus = .downloading
        chapter.downloadError = nil

        do {
            // Estimate: ~500KB per page
            let estimatedBytes = Int64(chapter.totalPages) * 500_000
            try checkDiskSpace(estimatedBytes: estimatedBytes)

            let pages: [PageResponse] = try await APIClient.shared.request(
                .chapterPages(comicId: comicId, chapterId: chapter.id)
            )

            // Write to temp directory
            let tempDir = tempDownloadDir.appendingPathComponent(chapter.id.uuidString)
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

            var totalBytes: Int64 = 0

            try await withThrowingTaskGroup(of: Int64.self) { group in
                for page in pages {
                    group.addTask {
                        guard let url = URL(string: AppConfig.staticBaseURL + page.filePath) else {
                            throw DownloadError.fileValidationFailed("Invalid URL for page \(page.pageNumber)")
                        }
                        let (data, _) = try await URLSession.shared.data(from: url)

                        // Validate image data
                        try self.validateImageData(data, pageNumber: page.pageNumber)

                        let fileName = String(format: "page_%04d.jpg", page.pageNumber)
                        let fileURL = tempDir.appendingPathComponent(fileName)
                        try data.write(to: fileURL)
                        return Int64(data.count)
                    }
                }
                for try await bytes in group {
                    totalBytes += bytes
                }
            }

            // Atomic move: temp → final
            let relativeDir = "comics/\(comicId)/\(chapter.id)"
            let finalDir = documentsDir.appendingPathComponent(relativeDir)

            // Remove existing if re-downloading
            if fileManager.fileExists(atPath: finalDir.path) {
                try fileManager.removeItem(at: finalDir)
            }
            try fileManager.createDirectory(at: finalDir.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.moveItem(at: tempDir, to: finalDir)

            // Update model
            chapter.localPagesPath = relativeDir
            chapter.downloadStatus = .complete
            chapter.downloadedAt = .now
            chapter.downloadSizeBytes = totalBytes
            chapter.isDownloaded = true

            do {
                try modelContext.save()
            } catch {
                // Save failed — remove moved files to stay consistent
                try? fileManager.removeItem(at: finalDir)
                chapter.localPagesPath = nil
                chapter.downloadStatus = .failed
                chapter.downloadError = "Database save failed"
                chapter.isDownloaded = false
                throw error
            }

        } catch {
            // Cleanup temp on failure
            let tempDir = tempDownloadDir.appendingPathComponent(chapter.id.uuidString)
            try? fileManager.removeItem(at: tempDir)

            chapter.downloadStatus = .failed
            chapter.downloadError = error.localizedDescription
            chapter.isDownloaded = false
            try? modelContext.save()
            throw error
        }
    }

    /// Download ALL chapters for a comic sequentially.
    func downloadAllChapters(
        comic: LocalComic,
        chapters: [LocalComicChapter],
        modelContext: ModelContext,
        onProgress: @escaping (Int, Int) -> Void
    ) async {
        let pending = chapters.filter { $0.downloadStatus != .complete && $0.scrapeStatus == "scraped" }
        guard !pending.isEmpty else { return }

        for chapter in pending {
            chapter.downloadStatus = .queued
        }
        try? modelContext.save()

        for (idx, chapter) in pending.enumerated() {
            do {
                try await downloadChapter(comicId: comic.id, chapter: chapter, modelContext: modelContext)
            } catch {
                AstralLogger.error("Download failed ch \(chapter.chapterNumber): \(error)", context: "Download")
            }
            onProgress(idx + 1, pending.count)
        }

        comic.isDownloaded = chapters.allSatisfy { $0.downloadStatus == .complete }
        try? modelContext.save()
    }

    // MARK: - Local Files

    /// Load locally saved page URLs for a chapter. Returns nil if not available.
    func localPageURLs(for chapter: LocalComicChapter) -> [URL]? {
        guard let relativePath = chapter.localPagesPath else { return nil }
        let chapterDir = documentsDir.appendingPathComponent(relativePath)
        guard let files = try? fileManager.contentsOfDirectory(at: chapterDir, includingPropertiesForKeys: nil) else {
            return nil
        }
        let sorted = files
            .filter { $0.pathExtension == "jpg" || $0.pathExtension == "png" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return sorted.isEmpty ? nil : sorted
    }

    // MARK: - Deletion

    /// Delete locally saved pages for a single chapter.
    func deleteChapter(comicId: UUID, chapter: LocalComicChapter, modelContext: ModelContext) {
        guard let relativePath = chapter.localPagesPath else { return }
        let chapterDir = documentsDir.appendingPathComponent(relativePath)
        try? fileManager.removeItem(at: chapterDir)
        chapter.localPagesPath = nil
        chapter.downloadStatus = .none
        chapter.isDownloaded = false
        chapter.downloadedAt = nil
        chapter.downloadSizeBytes = nil
        chapter.downloadError = nil
        try? modelContext.save()
    }

    /// Delete all locally saved pages for a comic.
    func deleteAllChapters(comic: LocalComic, chapters: [LocalComicChapter], modelContext: ModelContext) {
        let comicDir = documentsDir.appendingPathComponent("comics/\(comic.id)")
        try? fileManager.removeItem(at: comicDir)
        for chapter in chapters {
            chapter.localPagesPath = nil
            chapter.downloadStatus = .none
            chapter.isDownloaded = false
            chapter.downloadedAt = nil
            chapter.downloadSizeBytes = nil
            chapter.downloadError = nil
        }
        comic.isDownloaded = false
        try? modelContext.save()
    }

    // MARK: - Validation

    /// Validate downloaded image data has correct magic bytes.
    private nonisolated func validateImageData(_ data: Data, pageNumber: Int) throws {
        guard data.count > 1024 else {
            throw DownloadError.fileValidationFailed("Page \(pageNumber): file too small (\(data.count) bytes)")
        }
        let jpegMagic: [UInt8] = [0xFF, 0xD8, 0xFF]
        let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47]

        let header = Array(data.prefix(4))
        let isJPEG = header.starts(with: jpegMagic)
        let isPNG = header.starts(with: pngMagic)

        guard isJPEG || isPNG else {
            throw DownloadError.fileValidationFailed("Page \(pageNumber): not a valid JPEG/PNG")
        }
    }

    private func checkDiskSpace(estimatedBytes: Int64) throws {
        let attrs = try fileManager.attributesOfFileSystem(forPath: documentsDir.path)
        let freeSpace = (attrs[.systemFreeSize] as? Int64) ?? 0
        let buffer: Int64 = 50 * 1024 * 1024
        guard freeSpace > estimatedBytes + buffer else {
            throw DownloadError.insufficientDiskSpace
        }
    }
}
