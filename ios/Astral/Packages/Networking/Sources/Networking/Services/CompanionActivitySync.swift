import Foundation
import SwiftData
import Core

@MainActor
public enum CompanionActivitySync {
    public static func sync(context: ModelContext) async {
        guard AppConfig.companionEnabled else { return }
        do {
            let deleted = Set(try context.fetch(FetchDescriptor<PendingRemoteDeletion>()).map(\.storyId))
            let dismissed = Set(UserDefaults.standard.stringArray(forKey: "companion.dismissedJobs") ?? [])
            var page = 1
            repeat {
                let response: PaginatedResponse<ScrapeJobResponse> = try await APIClient.shared.request(.allScrapeJobs(page: page, pageSize: 100))
                for dto in response.items where !deleted.contains(dto.storyId) && !dismissed.contains(dto.id.uuidString) {
                    let id = dto.id
                    let job = try context.fetch(FetchDescriptor<LocalScrapeJob>(predicate: #Predicate { $0.id == id })).first
                        ?? LocalScrapeJob(id: id, contentType: dto.contentType, storyId: dto.storyId)
                    if job.modelContext == nil { context.insert(job) }
                    job.status = ["complete", "partial"].contains(dto.status) ? (dto.status == "complete" ? "completed" : "failed") : dto.status
                    job.chaptersScraped = dto.chaptersScraped; job.chaptersFailed = dto.chaptersFailed
                    job.totalChapters = dto.totalChapters; job.completedAt = dto.completedAt; job.errorMessage = dto.errorMessage
                    job.currentStep = dto.currentStep; job.lastErrorType = dto.lastErrorType; job.startedAt = dto.startedAt
                }
                try context.save()
                guard page < response.totalPages else { break }
                page += 1
            } while !Task.isCancelled
            UserDefaults.standard.removeObject(forKey: "companion.lastError")
        } catch is CancellationError { }
        catch { UserDefaults.standard.set(error.localizedDescription, forKey: "companion.lastError") }
    }
}
