import Foundation
import ImageIO
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
        let storageToken = try ComicStoragePolicy.acquire(story: comicId, context: modelContext)
        defer { ComicStoragePolicy.release(storageToken) }

        let previousPath = chapter.localPagesPath
        let previousState = chapter.downloadStatus
        let previousDate = chapter.downloadedAt
        let previousBytes = chapter.downloadSizeBytes
        let previousSaved = chapter.isDownloaded
        let generation = UUID().uuidString
        let relativeDir = "comics/\(comicId)/\(chapter.id)/\(generation)"
        let finalDir = documentsDir.appendingPathComponent(relativeDir)
        chapter.downloadStatus = .downloading
        chapter.downloadError = nil
        do {
            try checkDiskSpace(estimatedBytes: Int64(chapter.totalPages) * 500_000)
            let pages: [PageResponse]
            if chapter.comic?.sourceKey == "mangadex-device" {
                pages = try await MangaDexDeviceService.pages(chapter.id)
                // The at-home list is the chapter as it is now. An uploader edit since
                // import changes the count, which must not make every save fail.
                if !pages.isEmpty { chapter.totalPages = pages.count }
            }
            else if let comic = chapter.comic, DeviceComicService.sources.contains(comic.sourceKey) { pages = try await DeviceComicService.pages(comic: comic, chapter: chapter) }
            else { pages = try await APIClient.shared.request(.chapterPages(comicId: comicId, chapterId: chapter.id)) }
            guard !pages.isEmpty, Set(pages.map(\.pageNumber)).count == pages.count,
                  chapter.totalPages == 0 || chapter.totalPages == pages.count else {
                throw DownloadError.fileValidationFailed("The source returned an incomplete page list.")
            }
            try fileManager.createDirectory(at: finalDir, withIntermediateDirectories: true)
            var totalBytes: Int64 = 0
            // Bound both in-flight responses and decoded image validation to four pages.
            for start in stride(from: 0, to: pages.count, by: 4) {
                try Task.checkCancellation()
                let batch = Array(pages[start..<min(start + 4, pages.count)])
                totalBytes += try await withThrowingTaskGroup(of: (Int, Data).self) { group in
                    for page in batch {
                        guard let url = URL(string: page.filePath.hasPrefix("https://") ? page.filePath : AppConfig.staticBaseURL + page.filePath) else { throw APIError.invalidURL }
                        let request = DeviceComicService.imageRequest(url, comic: comicId, chapter: chapter.id)
                        group.addTask {
                            let (data, response) = try await SourceImageTransport.session.data(for: request)
                            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw APIError.invalidResponse }
                            try self.validateImageData(data, pageNumber: page.pageNumber)
                            try Task.checkCancellation()
                            return (page.pageNumber, data)
                        }
                    }
                    var bytes: Int64 = 0
                    for try await (number, data) in group {
                        try savePage(data, to: finalDir.appendingPathComponent(String(format: "page_%04d.img", number)), token: storageToken, context: modelContext)
                        bytes += Int64(data.count)
                    }
                    return bytes
                }
                let used = try modelContext.fetch(FetchDescriptor<LocalComicChapter>()).reduce(Int64(0)) { $0 + ($1.downloadSizeBytes ?? 0) }
                guard used - (previousBytes ?? 0) + totalBytes <= AppConfig.comicDownloadLimitBytes else { throw DownloadError.insufficientDiskSpace }
            }
            try Task.checkCancellation()
            guard !chapter.isDeleted, chapter.modelContext != nil else { throw CancellationError() }
            chapter.totalPages = pages.count
            chapter.localPagesPath = relativeDir; chapter.downloadStatus = .complete
            chapter.downloadedAt = .now; chapter.downloadSizeBytes = totalBytes; chapter.isDownloaded = true
            try modelContext.save()
            if let previousPath, previousPath != relativeDir {
                // A generation may live inside an older chapter directory. Never remove its ancestor.
                let old = documentsDir.appendingPathComponent(previousPath).standardizedFileURL
                if !finalDir.path.hasPrefix(old.path + "/") { try? fileManager.removeItem(at: old) }
            }
        } catch {
            try? fileManager.removeItem(at: finalDir)
            guard !chapter.isDeleted, chapter.modelContext != nil else { throw error }
            // A cancelled save is not a failure; the chapter simply stays unsaved.
            let cancelled = Self.isCancellation(error)
            chapter.localPagesPath = previousPath
            chapter.downloadStatus = previousSaved ? previousState : (cancelled ? .none : .failed)
            chapter.downloadedAt = previousDate; chapter.downloadSizeBytes = previousBytes; chapter.isDownloaded = previousSaved
            chapter.downloadError = cancelled ? (previousSaved ? "Download cancelled. Saved copy retained." : nil) : error.localizedDescription
            try? modelContext.save()
            throw cancelled ? CancellationError() : error
        }
    }

    /// Only this task's own cancellation counts. URLSession reports it as
    /// `URLError.cancelled`, but a page loader's redirect or ad also fails with
    /// that code, and must be a failed chapter rather than a silent stop.
    static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || Task.isCancelled
    }

    private func savePage(_ data: Data, to destination: URL, token: UUID, context: ModelContext) throws {
        try Task.checkCancellation()
        try ComicStoragePolicy.reserve(bytes: Int64(data.count), token: token, context: context)
        try data.write(to: destination, options: .atomic)
    }

    /// Download ALL chapters for a comic sequentially.
    @discardableResult
    func downloadAllChapters(
        comic: LocalComic,
        chapters: [LocalComicChapter],
        modelContext: ModelContext,
        onCancel: @escaping () -> Void = {},
        onProgress: @escaping (Int, Int) -> Void
    ) async -> String? {
        let pending = chapters.filter { ![DownloadState.complete, .queued, .downloading].contains($0.downloadStatus) && $0.scrapeStatus == "scraped" }
        guard !pending.isEmpty else { return nil }

        let job = LocalScrapeJob(id: UUID(), contentType: "comic", storyId: comic.id, status: "running", totalChapters: pending.count, sourceKey: comic.sourceKey, jobType: "local-download", currentStep: comic.title, startedAt: .now)
        modelContext.insert(job)
        let reservation: UUID
        do { reservation = try ComicStoragePolicy.acquire(story: comic.id, context: modelContext) }
        catch { job.status = "failed"; job.errorMessage = error.localizedDescription; job.completedAt = .now; try? modelContext.save(); return error.localizedDescription }
        defer { ComicStoragePolicy.release(reservation) }
        LocalOperationRegistry.shared.register(job.id, cancel: onCancel)
        defer { LocalOperationRegistry.shared.finish(job.id) }
        for chapter in pending {
            chapter.downloadStatus = .queued
        }
        try? modelContext.save()

        for (idx, chapter) in pending.enumerated() {
            if Task.isCancelled { break }
            do {
                try await downloadChapter(comicId: comic.id, chapter: chapter, modelContext: modelContext)
            } catch {
                if Self.isCancellation(error) { break }
                job.chaptersFailed += 1; job.errorMessage = error.localizedDescription
                AstralLogger.error("Download failed ch \(chapter.chapterNumber): \(error)", context: "Download")
                if error is ComicStoragePolicy.StorageError { break }
                if let failure = error as? DownloadError, case .insufficientDiskSpace = failure { break }
            }
            job.chaptersScraped = idx + 1 - job.chaptersFailed
            onProgress(idx + 1, pending.count)
        }

        for chapter in pending where chapter.downloadStatus == .queued { chapter.downloadStatus = .none }
        job.status = Task.isCancelled ? "cancelled" : (job.chaptersFailed > 0 ? "failed" : "completed")
        job.completedAt = .now
        let comicID = comic.id
        let allChapters = (try? modelContext.fetch(FetchDescriptor<LocalComicChapter>(predicate: #Predicate { $0.comicId == comicID }))) ?? []
        comic.isDownloaded = !allChapters.isEmpty && allChapters.allSatisfy { $0.downloadStatus == .complete }
        try? modelContext.save()
        return job.status == "failed" ? (job.errorMessage ?? "Some chapters could not be saved. Saved copies were retained.") : nil
    }

    // MARK: - Local Files

    /// Load locally saved page URLs for a chapter. Returns nil if not available.
    func localPageURLs(for chapter: LocalComicChapter) -> [URL]? {
        guard let relativePath = chapter.localPagesPath else {
            AstralLogger.warning("localPageURLs: localPagesPath nil for chapter \(chapter.id) (isDownloaded=\(chapter.isDownloaded), downloadStatus=\(chapter.downloadStatus.rawValue))", context: "Download")
            return nil
        }
        let chapterDir = documentsDir.appendingPathComponent(relativePath)
        let files: [URL]
        do {
            files = try fileManager.contentsOfDirectory(at: chapterDir, includingPropertiesForKeys: nil)
        } catch {
            AstralLogger.warning("localPageURLs: contentsOfDirectory failed at \(chapterDir.path): \(error)", context: "Download")
            return nil
        }
        let sorted = files
            .filter { ["jpg", "jpeg", "png", "webp", "gif", "heic", "avif", "img"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        if sorted.isEmpty {
            let rawNames = files.map { $0.lastPathComponent }
            AstralLogger.warning("localPageURLs: no .jpg/.png files after filter at \(chapterDir.path); raw files=\(rawNames)", context: "Download")
            return nil
        }
        return sorted
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
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              (properties[kCGImagePropertyPixelWidth] as? Int ?? 0) > 0,
              (properties[kCGImagePropertyPixelHeight] as? Int ?? 0) > 0 else {
            throw DownloadError.fileValidationFailed("Page \(pageNumber): invalid image data")
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
