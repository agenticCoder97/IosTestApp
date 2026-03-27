import Foundation
import SwiftData
import Core
import Networking

@Observable
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
                let fanfic = LocalFanfic(
                    id: dto.id,
                    title: dto.title,
                    sourceKey: dto.sourceKey,
                    summary: dto.summary,
                    fandom: dto.fandom,
                    rating: dto.rating,
                    completionStatus: dto.completionStatus,
                    wordCount: dto.wordCount,
                    totalChapters: dto.totalChapters
                )
                modelContext.insert(fanfic)
            }
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
