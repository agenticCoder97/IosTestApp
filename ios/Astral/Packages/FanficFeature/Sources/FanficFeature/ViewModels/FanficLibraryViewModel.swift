import Foundation
import SwiftData
import Core
import Networking

@MainActor @Observable
final class FanficLibraryViewModel {
    var isLoading = false
    var errorMessage: String?

    func fetchFanfics(
        modelContext: ModelContext,
        fandom: String? = nil,
        rating: String? = nil,
        completionStatus: String? = nil,
        sort: String? = nil
    ) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let response: PaginatedResponse<FanficResponse> = try await APIClient.shared.request(
                .fanfics(
                    fandom: fandom,
                    rating: rating,
                    completionStatus: completionStatus,
                    sort: sort
                )
            )

            for dto in response.items {
                let descriptor = FetchDescriptor<LocalFanfic>(
                    predicate: #Predicate<LocalFanfic> { $0.id == dto.id }
                )
                let localFanfic: LocalFanfic

                if let existing = try? modelContext.fetch(descriptor).first {
                    // Update server-owned fields; preserve user fields
                    existing.title = dto.title
                    existing.summary = dto.summary
                    existing.fandom = dto.fandom
                    existing.rating = dto.rating
                    existing.completionStatus = dto.completionStatus
                    existing.wordCount = dto.wordCount
                    existing.totalChapters = dto.totalChapters
                    localFanfic = existing
                } else {
                    let fanfic = LocalFanfic(
                        id: dto.id,
                        title: dto.title,
                        sourceKey: dto.sourceKey,
                        summary: dto.summary,
                        fandom: dto.fandom,
                        rating: dto.rating,
                        completionStatus: dto.completionStatus,
                        wordCount: dto.wordCount,
                        totalChapters: dto.totalChapters,
                        seenTotalChapters: dto.totalChapters
                    )
                    modelContext.insert(fanfic)
                    localFanfic = fanfic
                }

                if let chapters = dto.chapters {
                    try upsertChapters(
                        chapters,
                        for: localFanfic,
                        in: modelContext
                    )
                }
            }
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func upsertChapters(
        _ chapters: [FanficChapterResponse],
        for fanfic: LocalFanfic,
        in modelContext: ModelContext
    ) throws {
        let fanficID = fanfic.id
        let chapterIDs = Set(chapters.map(\.id))
        let existingDescriptor = FetchDescriptor<LocalFanficChapter>(
            predicate: #Predicate<LocalFanficChapter> { $0.fanficId == fanficID }
        )
        let existingChapters = try modelContext.fetch(existingDescriptor)
        let existingChaptersByID = Dictionary(uniqueKeysWithValues: existingChapters.map { ($0.id, $0) })

        for existingChapter in existingChapters where !chapterIDs.contains(existingChapter.id) {
            modelContext.delete(existingChapter)
        }

        for chapterDTO in chapters {
            if let existingChapter = existingChaptersByID[chapterDTO.id] {
                existingChapter.fanficId = fanfic.id
                existingChapter.fanfic = fanfic
                existingChapter.chapterNumber = chapterDTO.chapterNumber
                existingChapter.title = chapterDTO.title
                existingChapter.wordCount = chapterDTO.wordCount
                existingChapter.scrapeStatus = chapterDTO.scrapeStatus
                existingChapter.isDownloaded = chapterDTO.content != nil || existingChapter.localTextPath != nil
            } else {
                let chapter = LocalFanficChapter(
                    id: chapterDTO.id,
                    fanficId: fanfic.id,
                    chapterNumber: chapterDTO.chapterNumber,
                    title: chapterDTO.title,
                    wordCount: chapterDTO.wordCount,
                    isDownloaded: chapterDTO.content != nil,
                    scrapeStatus: chapterDTO.scrapeStatus
                )
                chapter.fanfic = fanfic
                modelContext.insert(chapter)
            }
        }
    }
}
