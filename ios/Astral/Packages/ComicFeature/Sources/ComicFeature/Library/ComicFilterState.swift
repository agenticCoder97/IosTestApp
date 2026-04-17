import Foundation
import Observation

/// Sort options for the comic library.
enum ComicSortOption: String, CaseIterable {
    case lastRead = "Last Read"
    case dateAdded = "Date Added"
    case title = "Title"
    case chapters = "Chapters"
}

/// Runtime filter state for the comic library. Owned by ComicNavigation.
@Observable
final class ComicFilterState {
    var showArchived: Bool = false
    var completionStatus: String? = nil
    var tagsKeyword: String = ""
    var category: String? = nil
    var sourceKey: String? = nil
    var sortBy: ComicSortOption = .lastRead
    var sortAscending: Bool = false

    var isActive: Bool {
        showArchived
            || completionStatus != nil
            || !tagsKeyword.isEmpty
            || category != nil
            || sourceKey != nil
            || sortBy != .lastRead
    }

    func reset() {
        showArchived = false
        completionStatus = nil
        tagsKeyword = ""
        category = nil
        sourceKey = nil
        sortBy = .lastRead
        sortAscending = false
    }

    func load(from prefs: ComicFilterPrefs) {
        showArchived = prefs.showArchived
        completionStatus = prefs.completionStatus
        tagsKeyword = prefs.tagsKeyword
        category = prefs.category
        sourceKey = prefs.sourceKey
        sortBy = ComicSortOption(rawValue: prefs.sortBy) ?? .lastRead
        sortAscending = prefs.sortAscending
    }

    var snapshotForPersistence: ComicFilterPrefs {
        ComicFilterPrefs(
            showArchived: showArchived,
            completionStatus: completionStatus,
            tagsKeyword: tagsKeyword,
            category: category,
            sourceKey: sourceKey,
            sortBy: sortBy.rawValue,
            sortAscending: sortAscending
        )
    }
}
