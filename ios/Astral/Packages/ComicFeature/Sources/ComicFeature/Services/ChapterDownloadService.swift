import Foundation
import SwiftData
import Core
import Networking

/// Downloads comic chapter pages to the device's Documents directory for offline reading.
@MainActor
final class ChapterDownloadService {
    static let shared = ChapterDownloadService()
    private init() {}

    private let fileManager = FileManager.default

    private var documentsDir: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Download all pages for a chapter to local storage.
    /// Returns the local directory path relative to Documents.
    func downloadChapter(
        comicId: UUID,
        chapter: LocalComicChapter,
        modelContext: ModelContext
    ) async throws {
        let pages: [PageResponse] = try await APIClient.shared.request(
            .chapterPages(comicId: comicId, chapterId: chapter.id)
        )

        let relativeDir = "comics/\(comicId)/\(chapter.id)"
        let chapterDir = documentsDir.appendingPathComponent(relativeDir)
        try fileManager.createDirectory(at: chapterDir, withIntermediateDirectories: true)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for page in pages {
                group.addTask {
                    let url = URL(string: AppConfig.staticBaseURL + page.filePath)!
                    let (data, _) = try await URLSession.shared.data(from: url)
                    let fileName = String(format: "page_%04d.jpg", page.pageNumber)
                    let fileURL = chapterDir.appendingPathComponent(fileName)
                    try data.write(to: fileURL)
                }
            }
            try await group.waitForAll()
        }

        chapter.localPagesPath = relativeDir
        chapter.isDownloaded = true
        try? modelContext.save()
    }

    /// Download ALL chapters for a comic.
    func downloadAllChapters(
        comic: LocalComic,
        chapters: [LocalComicChapter],
        modelContext: ModelContext,
        onProgress: @escaping (Int, Int) -> Void
    ) async {
        let pendingChapters = chapters.filter { $0.localPagesPath == nil && $0.scrapeStatus == "scraped" }
        for (idx, chapter) in pendingChapters.enumerated() {
            do {
                try await downloadChapter(comicId: comic.id, chapter: chapter, modelContext: modelContext)
            } catch {
                AstralLogger.error("Download failed ch \(chapter.chapterNumber): \(error)", context: "Download")
            }
            onProgress(idx + 1, pendingChapters.count)
        }
        comic.isDownloaded = chapters.allSatisfy { $0.localPagesPath != nil }
        try? modelContext.save()
    }

    /// Load locally saved pages for a chapter.
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

    /// Delete locally saved pages for a chapter.
    func deleteChapter(comicId: UUID, chapter: LocalComicChapter, modelContext: ModelContext) {
        guard let relativePath = chapter.localPagesPath else { return }
        let chapterDir = documentsDir.appendingPathComponent(relativePath)
        try? fileManager.removeItem(at: chapterDir)
        chapter.localPagesPath = nil
        chapter.isDownloaded = false
        try? modelContext.save()
    }

    /// Delete all locally saved pages for a comic.
    func deleteAllChapters(comic: LocalComic, chapters: [LocalComicChapter], modelContext: ModelContext) {
        let comicDir = documentsDir.appendingPathComponent("comics/\(comic.id)")
        try? fileManager.removeItem(at: comicDir)
        for chapter in chapters {
            chapter.localPagesPath = nil
            chapter.isDownloaded = false
        }
        comic.isDownloaded = false
        try? modelContext.save()
    }
}
