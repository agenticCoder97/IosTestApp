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
        defer { isLoading = false }

        do {
            let response: PaginatedResponse<ComicResponse> = try await APIClient.shared.request(
                .comics()
            )

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
        } catch let error as APIError where error == .cookieRefreshNeeded {
            errorMessage = "Browser refresh needed"
        } catch {
            errorMessage = error.localizedDescription
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
