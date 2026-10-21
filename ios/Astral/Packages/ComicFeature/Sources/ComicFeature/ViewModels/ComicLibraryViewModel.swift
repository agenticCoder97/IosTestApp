import Foundation
import SwiftData
import Core
import Networking

@MainActor @Observable
final class ComicLibraryViewModel {
    var isLoading = false
    var errorMessage: String?
    private var lastSyncTime: Date?
    private static let syncInterval: TimeInterval = 120 // 2 minutes

    func fetchComics(modelContext: ModelContext, force: Bool = false) async {
        guard AppConfig.companionEnabled else { return }
        if !force, let last = lastSyncTime, Date().timeIntervalSince(last) < Self.syncInterval {
            AstralLogger.info("fetchComics skipped — last sync \(Int(Date().timeIntervalSince(last)))s ago", context: "ComicLibraryVM")
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        AstralLogger.info("fetchComics started", context: "ComicLibraryVM")

        do {
            var response: PaginatedResponse<ComicResponse> = try await APIClient.shared.request(.comics())
            var allItems = response.items
            var page = 1
            while page < response.totalPages {
                page += 1
                response = try await APIClient.shared.request(.comics(page: page))
                allItems += response.items
            }
            AstralLogger.info("fetchComics got \(response.items.count) comics (page \(response.page)/\(response.totalPages))", context: "ComicLibraryVM")

            let deleted = Set(try modelContext.fetch(FetchDescriptor<PendingRemoteDeletion>()).map(\.storyId))
            for dto in allItems where !deleted.contains(dto.id) {
                let descriptor = FetchDescriptor<LocalComic>(
                    predicate: #Predicate<LocalComic> { $0.id == dto.id }
                )
                let localComic: LocalComic
                if let existing = try? modelContext.fetch(descriptor).first {
                    // Update server-owned fields; preserve user fields (isFavorite, seenTotalChapters, lastReadAt)
                    existing.title = dto.title
                    existing.thumbnailPath = dto.thumbnailPath
                    existing.comicDescription = dto.description
                    existing.totalChapters = dto.totalChapters
                    existing.status = dto.status
                    existing.category = dto.category
                    existing.archiveStatus = dto.archiveStatus
                    existing.archivedAt = dto.archivedAt
                    existing.tagsJSON = Self.encodeTagsJSON(dto.tags)
                    existing.authorsJSON = Self.encodeAuthorsJSON(dto.authors)
                    localComic = existing
                } else {
                    // New entry — seed seenTotalChapters to current count so no phantom badge
                    let comic = LocalComic(
                        id: dto.id,
                        title: dto.title,
                        sourceKey: dto.sourceKey,
                        thumbnailPath: dto.thumbnailPath,
                        comicDescription: dto.description,
                        totalChapters: dto.totalChapters,
                        status: dto.status,
                        seenTotalChapters: dto.totalChapters
                    )
                    comic.category = dto.category
                    comic.archiveStatus = dto.archiveStatus
                    comic.archivedAt = dto.archivedAt
                    comic.tagsJSON = Self.encodeTagsJSON(dto.tags)
                    comic.authorsJSON = Self.encodeAuthorsJSON(dto.authors)
                    modelContext.insert(comic)
                    localComic = comic
                }

                UserDefaults.standard.set(dto.sourceUrl, forKey: "reading.source." + dto.id.uuidString)
                if let chapters = dto.chapters {
                    try upsertChapters(chapters, for: localComic, in: modelContext)
                }
            }
            try modelContext.save()

            // Reading position belongs to this device; companion metadata never advances it.
            lastSyncTime = .now
        } catch APIError.cookieRefreshNeeded {
            errorMessage = "Browser refresh needed"
            AstralLogger.warning("fetchComics: cookie refresh needed", context: "ComicLibraryVM")
        } catch let urlError as URLError where urlError.code == .cancelled {
            AstralLogger.info("fetchComics cancelled mid-flight", context: "ComicLibraryVM")
        } catch let urlError as URLError {
            errorMessage = "Couldn't reach the server — \(urlError.localizedDescription)"
            AstralLogger.error("fetchComics URL error: \(urlError.code.rawValue) — \(urlError.localizedDescription)", context: "ComicLibraryVM")
        } catch {
            errorMessage = "Sync failed: \(error.localizedDescription)"
            AstralLogger.error("fetchComics failed: \(error)", context: "ComicLibraryVM")
        }
    }

    private static func encodeTagsJSON(_ tags: [TagResponse]?) -> String? {
        guard let tags, !tags.isEmpty else { return nil }
        let dicts = tags.map { ["name": $0.name, "tag_type": $0.tagType] }
        guard let data = try? JSONSerialization.data(withJSONObject: dicts) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func encodeAuthorsJSON(_ authors: [AuthorResponse]?) -> String? {
        guard let authors, !authors.isEmpty else { return nil }
        let dicts = authors.map { ["id": $0.id.uuidString, "name": $0.name] }
        guard let data = try? JSONSerialization.data(withJSONObject: dicts) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func upsertChapters(
        _ chapters: [ComicChapterResponse],
        for comic: LocalComic,
        in modelContext: ModelContext
    ) throws {
        let comicID = comic.id
        let existingDescriptor = FetchDescriptor<LocalComicChapter>(
            predicate: #Predicate<LocalComicChapter> { $0.comicId == comicID }
        )
        let existingChapters = try modelContext.fetch(existingDescriptor)
        let existingByID = Dictionary(uniqueKeysWithValues: existingChapters.map { ($0.id, $0) })

        // A partial response must not delete chapters already saved on this device.
        for dto in chapters {
            if let sourceURL = dto.sourceUrl { UserDefaults.standard.set(sourceURL, forKey: "reading.chapterSource." + dto.id.uuidString) }
            if let existing = existingByID[dto.id] {
                existing.chapterNumber = dto.chapterNumber
                existing.title = dto.title
                existing.totalPages = dto.totalPages
                existing.scrapeStatus = dto.scrapeStatus
                existing.comic = comic
            } else {
                let chapter = LocalComicChapter(
                    id: dto.id,
                    comicId: comic.id,
                    chapterNumber: dto.chapterNumber,
                    title: dto.title,
                    totalPages: dto.totalPages,
                    scrapeStatus: dto.scrapeStatus
                )
                chapter.comic = comic
                modelContext.insert(chapter)
            }
        }
    }
}
