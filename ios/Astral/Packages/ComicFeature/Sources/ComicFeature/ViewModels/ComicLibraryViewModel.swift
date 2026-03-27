import Foundation
import SwiftData
import Core
import Networking

@Observable
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
                let comic = LocalComic(
                    id: dto.id,
                    title: dto.title,
                    sourceKey: dto.sourceKey,
                    thumbnailPath: dto.thumbnailPath,
                    totalChapters: dto.totalChapters,
                    status: dto.status
                )
                modelContext.insert(comic)
            }
            try modelContext.save()
        } catch let error as APIError where error == .cookieRefreshNeeded {
            errorMessage = "Browser refresh needed"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension APIError: Equatable {
    public static func == (lhs: APIError, rhs: APIError) -> Bool {
        lhs.localizedDescription == rhs.localizedDescription
    }
}
