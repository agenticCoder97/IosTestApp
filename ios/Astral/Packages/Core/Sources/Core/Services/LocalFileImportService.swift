import Foundation
import SwiftData
import ImageIO

/// Imports original files as independent device-owned copies. No API or companion.
@MainActor
public enum LocalFileImportService {
    public static func importText(_ source: URL, context: ModelContext) throws -> LocalFanfic {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: source, options: .mappedIfSafe)
        guard data.count <= 50 * 1024 * 1024, let text = String(data: data, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ImportError.invalid("Choose a nonempty UTF-8 text file smaller than 50 MB.")
        }
        let id = UUID(), chapterID = UUID()
        let path = "fanfics/\(id)/\(chapterID).txt"
        let url = URL.documentsDirectory.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        do {
            try context.save()
            let story = LocalFanfic(id: id, title: source.deletingPathExtension().lastPathComponent, sourceKey: "local", completionStatus: "complete", wordCount: text.split(whereSeparator: \.isWhitespace).count, totalChapters: 1, isDownloaded: true)
            let chapter = LocalFanficChapter(id: chapterID, fanficId: id, chapterNumber: 1, title: story.title, wordCount: story.wordCount, isDownloaded: true, localTextPath: path, scrapeStatus: "scraped")
            chapter.downloadStatus = .complete; chapter.downloadedAt = .now; chapter.fanfic = story
            context.insert(story); context.insert(chapter)
            context.insert(LocalScrapeJob(id: UUID(), contentType: "fanfic", storyId: id, status: "completed", chaptersScraped: 1, totalChapters: 1, completedAt: .now, sourceKey: "local", jobType: "local-file", currentStep: story.title))
            try context.save()
            return story
        } catch { context.rollback(); try? FileManager.default.removeItem(at: url.deletingLastPathComponent()); throw error }
    }
    public static func importComicFolder(_ source: URL, context: ModelContext, onCancel: @escaping () -> Void = {}) async throws -> LocalComic {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let id = UUID()
        let storageToken = try ComicStoragePolicy.acquire(story: id, context: context)
        defer { ComicStoragePolicy.release(storageToken) }
        let job = LocalScrapeJob(id: UUID(), contentType: "comic", storyId: id, status: "running", sourceKey: "local", jobType: "local-file", currentStep: source.lastPathComponent, startedAt: .now)
        context.insert(job); try context.save()
        LocalOperationRegistry.shared.register(job.id, cancel: onCancel)
        defer { LocalOperationRegistry.shared.finish(job.id) }
        let existingBytes = try context.fetch(FetchDescriptor<LocalComicChapter>()).reduce(Int64(0)) { $0 + ($1.downloadSizeBytes ?? 0) }
        var beganMutation = false
        do {
            let plannedBytes = try await ComicFolderStorage.shared.size(source)
            try ComicStoragePolicy.reserve(bytes: plannedBytes, token: storageToken, context: context)
            let records = try await ComicFolderStorage.shared.copy(source, storyID: id, existingBytes: existingBytes)
            try Task.checkCancellation()
            let actualBytes = records.reduce(Int64(0)) { $0 + $1.bytes }
            try ComicStoragePolicy.reserve(bytes: max(0, actualBytes - plannedBytes), token: storageToken, context: context)
            try context.save(); beganMutation = true
            let story = LocalComic(id: id, title: source.lastPathComponent, sourceKey: "local", totalChapters: records.count, status: "complete", isDownloaded: true, seenTotalChapters: records.count)
            story.completionStatus = "complete"; context.insert(story)
            for (index, record) in records.enumerated() {
                let chapter = LocalComicChapter(id: record.id, comicId: id, chapterNumber: Double(index + 1), title: record.title, totalPages: record.pages, isDownloaded: true, scrapeStatus: "scraped")
                chapter.comic = story; chapter.localPagesPath = record.path; chapter.downloadStatus = .complete
                chapter.downloadedAt = .now; chapter.downloadSizeBytes = record.bytes; context.insert(chapter)
            }
            job.status = "completed"; job.totalChapters = records.count; job.chaptersScraped = records.count; job.completedAt = .now
            try context.save()
            return story
        } catch {
            if beganMutation { context.rollback() }
            await ComicFolderStorage.shared.remove(id)
            job.status = error is CancellationError ? "cancelled" : "failed"; job.errorMessage = error.localizedDescription; job.completedAt = .now
            try? context.save(); throw error
        }
    }
    private static func isImage(_ url: URL) -> Bool { ["jpg", "jpeg", "png", "webp", "gif", "heic", "avif"].contains(url.pathExtension.lowercased()) }
    public enum ImportError: LocalizedError {
        case invalid(String)
        public var errorDescription: String? { if case .invalid(let message) = self { message } else { nil } }
    }
}

private actor ComicFolderStorage {
    static let shared = ComicFolderStorage()
    struct Record: Sendable { let id: UUID; let title: String; let pages: Int; let path: String; let bytes: Int64 }
    func remove(_ id: UUID) { try? FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent("comics/\(id)")) }
    func size(_ source: URL) throws -> Int64 {
        let files = FileManager.default.enumerator(at: source, includingPropertiesForKeys: [.fileSizeKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
        var bytes: Int64 = 0
        while let file = files?.nextObject() as? URL {
            try Task.checkCancellation()
            let values = try file.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw LocalFileImportService.ImportError.invalid("Symbolic links are not supported in comic folders.") }
            if ["jpg", "jpeg", "png", "webp", "gif", "heic", "avif"].contains(file.pathExtension.lowercased()) { bytes += Int64(values.fileSize ?? 0) }
        }
        return bytes
    }
    func copy(_ source: URL, storyID: UUID, existingBytes: Int64) throws -> [Record] {
        let fm = FileManager.default
        func images(_ directory: URL) throws -> [URL] {
            try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                .filter { ["jpg", "jpeg", "png", "webp", "gif", "heic", "avif"].contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        }
        let rootImages = try images(source)
        let folders = try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]).filter {
            let attrs = try $0.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            return attrs.isDirectory == true && attrs.isSymbolicLink != true
        }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        let chapters: [(String, [URL])] = try rootImages.isEmpty ? folders.compactMap { directory in
            let pages = try images(directory); return pages.isEmpty ? nil : (directory.lastPathComponent, pages)
        } : [(source.lastPathComponent, rootImages)]
        guard !chapters.isEmpty else { throw LocalFileImportService.ImportError.invalid("Choose a folder of page images, or a folder with one subfolder per chapter.") }
        var records: [Record] = []; var usedBytes = existingBytes
        do {
            for (title, pages) in chapters {
                let id = UUID(), path = "comics/\(storyID)/\(UUID().uuidString)"
                let directory = URL.documentsDirectory.appendingPathComponent(path)
                try fm.createDirectory(at: directory, withIntermediateDirectories: true)
                var bytes: Int64 = 0
                for (number, page) in pages.enumerated() {
                    try Task.checkCancellation()
                    guard try page.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true,
                          let image = CGImageSourceCreateWithURL(page as CFURL, nil), CGImageSourceGetCount(image) > 0 else { throw LocalFileImportService.ImportError.invalid("Invalid image: " + page.lastPathComponent) }
                    let size = Int64(try page.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
                    usedBytes += size; bytes += size
                    guard usedBytes <= AppConfig.comicDownloadLimitBytes else { throw LocalFileImportService.ImportError.invalid("The comic storage budget is full. Change it in Settings or remove saved pages.") }
                    let free = try URL.documentsDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? Int64.max
                    guard free > size + 50 * 1024 * 1024 else { throw LocalFileImportService.ImportError.invalid("Not enough free space for these pages.") }
                    try fm.copyItem(at: page, to: directory.appendingPathComponent(String(format: "page_%04d", number + 1) + "." + page.pathExtension.lowercased()))
                }
                records.append(Record(id: id, title: title, pages: pages.count, path: path, bytes: bytes))
            }
            return records
        } catch { remove(storyID); throw error }
    }
}
