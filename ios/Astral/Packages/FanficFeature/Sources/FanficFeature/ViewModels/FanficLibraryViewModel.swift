import Foundation
import SwiftData
import Core
import Networking

@MainActor @Observable
final class FanficLibraryViewModel {
    var isLoading = false
    var errorMessage: String?
    private var lastSyncTime: Date?
    private static let syncInterval: TimeInterval = 120

    func fetchFanfics(
        modelContext: ModelContext,
        fandom: String? = nil,
        rating: String? = nil,
        completionStatus: String? = nil,
        sort: String? = nil,
        force: Bool = false
    ) async {
        if !force, let last = lastSyncTime, Date().timeIntervalSince(last) < Self.syncInterval {
            AstralLogger.info("fetchFanfics skipped — last sync \(Int(Date().timeIntervalSince(last)))s ago", context: "FanficLibraryVM")
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        AstralLogger.info("fetchFanfics started (fandom=\(fandom ?? "nil") rating=\(rating ?? "nil"))", context: "FanficLibraryVM")

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
                    existing.sourceUrl = dto.sourceUrl
                    existing.summary = dto.summary
                    existing.fandom = dto.fandom
                    existing.rating = dto.rating
                    existing.completionStatus = dto.completionStatus
                    existing.wordCount = dto.wordCount
                    existing.totalChapters = dto.totalChapters
                    existing.thumbnailPath = dto.thumbnailPath
                    existing.characters = dto.characters
                    existing.pairing = dto.relationship
                    existing.warnings = dto.warnings
                    existing.publishedAt = dto.publishedAt
                    existing.updatedAtSource = dto.updatedAtSource
                    existing.freeformTags = dto.freeformTags
                    existing.hits = dto.hits
                    existing.kudos = dto.kudos
                    existing.commentsCount = dto.commentsCount
                    existing.bookmarksCount = dto.bookmarksCount
                    if let authors = dto.authors, !authors.isEmpty {
                        existing.authorsText = authors.map(\.name).joined(separator: ", ")
                    }
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
                    fanfic.sourceUrl = dto.sourceUrl
                    fanfic.thumbnailPath = dto.thumbnailPath
                    fanfic.characters = dto.characters
                    fanfic.pairing = dto.relationship
                    fanfic.warnings = dto.warnings
                    fanfic.publishedAt = dto.publishedAt
                    fanfic.updatedAtSource = dto.updatedAtSource
                    fanfic.freeformTags = dto.freeformTags
                    fanfic.hits = dto.hits
                    fanfic.kudos = dto.kudos
                    fanfic.commentsCount = dto.commentsCount
                    fanfic.bookmarksCount = dto.bookmarksCount
                    if let authors = dto.authors, !authors.isEmpty {
                        fanfic.authorsText = authors.map(\.name).joined(separator: ", ")
                    }
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

            // Sync server reading progress — restores position after a SwiftData wipe.
            // Only advances local progress; never overwrites a chapter the user has read further.
            let progressList: [ProgressResponse] = try await APIClient.shared.request(.allProgress(contentType: "fanfic"))
            let progressByStoryId = Dictionary(uniqueKeysWithValues: progressList.map { ($0.storyId, $0) })

            let allFanficsDescriptor = FetchDescriptor<LocalFanfic>()
            let allFanfics = (try? modelContext.fetch(allFanficsDescriptor)) ?? []
            for fanfic in allFanfics {
                guard let progress = progressByStoryId[fanfic.id],
                      progress.lastChapterNumber > fanfic.lastReadChapterNumber else { continue }
                fanfic.lastReadChapterNumber = progress.lastChapterNumber
                fanfic.scrollOffsetPercent = progress.scrollOffsetPercent
                if fanfic.totalChapters > 0 {
                    fanfic.progressPercent = Double(progress.lastChapterNumber) / Double(fanfic.totalChapters)
                }
            }
            for fanfic in allFanfics {
                fanfic.lastSyncedAt = .now
            }
            try modelContext.save()
            lastSyncTime = .now

            // AST-12: one-off migration — assign thumbnails to fanfics with nil paths (batch)
            let nilThumbFanfics = allFanfics.filter { $0.thumbnailPath == nil }
            if !nilThumbFanfics.isEmpty {
                let count = min(nilThumbFanfics.count, 50)
                AstralLogger.info("Migration: \(nilThumbFanfics.count) fanfics need thumbnails", context: "FanficLibraryVM")
                if let batch: RandomThumbnailBatchResponse = try? await APIClient.shared.request(
                    .randomFanficThumbnails(count: count)
                ) {
                    for (fanfic, path) in zip(nilThumbFanfics, batch.paths) {
                        fanfic.thumbnailPath = path
                    }
                    // Fanfics beyond the 50-cap stay nil and are handled on the next library open
                    try? modelContext.save()
                    AstralLogger.info("Migration: thumbnail assignment complete", context: "FanficLibraryVM")
                }
            }
        } catch is URLError {
            errorMessage = "Backend unreachable — check Docker is running"
            AstralLogger.error("fetchFanfics: backend unreachable", context: "FanficLibraryVM")
        } catch {
            errorMessage = "Sync failed: \(error.localizedDescription)"
            AstralLogger.error("fetchFanfics failed: \(error)", context: "FanficLibraryVM")
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
