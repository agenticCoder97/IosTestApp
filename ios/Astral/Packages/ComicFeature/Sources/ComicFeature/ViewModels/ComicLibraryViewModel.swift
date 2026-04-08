import Foundation
import SwiftData
import Core
import Networking

@MainActor @Observable
final class ComicLibraryViewModel {
    var isLoading = false
    var errorMessage: String?

    func fetchComics(modelContext: ModelContext) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        AstralLogger.info("fetchComics started", context: "ComicLibraryVM")

        do {
            let response: PaginatedResponse<ComicResponse> = try await APIClient.shared.request(
                .comics()
            )
            AstralLogger.info("fetchComics got \(response.items.count) comics (page \(response.page)/\(response.totalPages))", context: "ComicLibraryVM")

            for dto in response.items {
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

                if let chapters = dto.chapters {
                    try upsertChapters(chapters, for: localComic, in: modelContext)
                }
            }
            try modelContext.save()

            // Sync server reading progress — restores position after a SwiftData wipe.
            // Only advances local progress; never overwrites a chapter the user has read further.
            let progressList: [ProgressResponse] = try await APIClient.shared.request(.allProgress(contentType: "comic"))
            let progressByStoryId = Dictionary(uniqueKeysWithValues: progressList.map { ($0.storyId, $0) })

            let allComicsDescriptor = FetchDescriptor<LocalComic>()
            let allComics = (try? modelContext.fetch(allComicsDescriptor)) ?? []
            for comic in allComics {
                guard let progress = progressByStoryId[comic.id],
                      progress.lastChapterNumber > comic.lastReadChapterNumber else { continue }
                comic.lastReadChapterNumber = progress.lastChapterNumber
                if comic.totalChapters > 0 {
                    comic.progressPercent = Double(progress.lastChapterNumber) / Double(comic.totalChapters)
                }
            }
            try modelContext.save()
        } catch let error as APIError where error == .cookieRefreshNeeded {
            errorMessage = "Browser refresh needed"
            AstralLogger.warning("fetchComics: cookie refresh needed", context: "ComicLibraryVM")
        } catch is URLError {
            errorMessage = "Backend unreachable — check Docker is running"
            AstralLogger.error("fetchComics: backend unreachable", context: "ComicLibraryVM")
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
        let chapterIDs = Set(chapters.map(\.id))
        let existingDescriptor = FetchDescriptor<LocalComicChapter>(
            predicate: #Predicate<LocalComicChapter> { $0.comicId == comicID }
        )
        let existingChapters = try modelContext.fetch(existingDescriptor)
        let existingByID = Dictionary(uniqueKeysWithValues: existingChapters.map { ($0.id, $0) })

        for existing in existingChapters where !chapterIDs.contains(existing.id) {
            modelContext.delete(existing)
        }

        for dto in chapters {
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

extension APIError: Equatable {

    public static func == (lhs: APIError, rhs: APIError) -> Bool {
        lhs.localizedDescription == rhs.localizedDescription
    }
}
