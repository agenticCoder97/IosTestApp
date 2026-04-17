import Foundation
import Observation

/// Runtime filter state for the fanfic library. Owned by FanficNavigation.
@Observable
final class FanficFilterState {
    var fandom: String = ""
    var completionStatus: String? = nil
    var wordCountMin: Int? = nil
    var wordCountMax: Int? = nil
    var selectedRatings: [String] = []
    var selectedWarnings: [String] = []
    var characters: String = ""
    var relationship: String = ""
    var sourceKey: String? = nil
    var sortBy: FanficSortOption = .lastRead
    var sortAscending: Bool = false

    var isActive: Bool {
        !fandom.isEmpty
            || completionStatus != nil
            || wordCountMin != nil
            || wordCountMax != nil
            || !selectedRatings.isEmpty
            || !selectedWarnings.isEmpty
            || !characters.isEmpty
            || !relationship.isEmpty
            || sourceKey != nil
            || sortBy != .lastRead
    }

    func reset() {
        fandom = ""
        completionStatus = nil
        wordCountMin = nil
        wordCountMax = nil
        selectedRatings = []
        selectedWarnings = []
        characters = ""
        relationship = ""
        sourceKey = nil
        sortBy = .lastRead
        sortAscending = false
    }

    func load(from prefs: FanficFilterPrefs) {
        fandom = prefs.fandom
        completionStatus = prefs.completionStatus
        wordCountMin = prefs.wordCountMin
        wordCountMax = prefs.wordCountMax
        selectedRatings = prefs.selectedRatings
        selectedWarnings = prefs.selectedWarnings
        characters = prefs.characters
        relationship = prefs.relationship
        sourceKey = prefs.sourceKey
        sortBy = FanficSortOption(rawValue: prefs.sortBy) ?? .lastRead
        sortAscending = prefs.sortAscending
    }

    var snapshotForPersistence: FanficFilterPrefs {
        FanficFilterPrefs(
            fandom: fandom,
            completionStatus: completionStatus,
            wordCountMin: wordCountMin,
            wordCountMax: wordCountMax,
            selectedRatings: selectedRatings,
            selectedWarnings: selectedWarnings,
            characters: characters,
            relationship: relationship,
            sourceKey: sourceKey,
            sortBy: sortBy.rawValue,
            sortAscending: sortAscending
        )
    }
}
