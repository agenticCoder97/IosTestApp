import Foundation

/// Codable snapshot of ComicFilterState for @AppStorage persistence.
struct ComicFilterPrefs: Codable {
    var showArchived: Bool = false
    var completionStatus: String? = nil
    var tagsKeyword: String = ""
    var category: String? = nil
    var sourceKey: String? = nil
    var sortBy: String = ComicSortOption.lastRead.rawValue
    var sortAscending: Bool = false
}
