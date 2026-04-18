import Foundation

/// Codable snapshot of FanficFilterState for @AppStorage persistence.
struct FanficFilterPrefs: Codable {
    var fandom: String = ""
    var completionStatus: String? = nil
    var wordCountMin: Int? = nil
    var wordCountMax: Int? = nil
    var selectedRatings: [String] = []
    var selectedWarnings: [String] = []
    var characters: String = ""
    var relationship: String = ""
    var sourceKey: String? = nil
    var sortBy: String = FanficSortOption.lastRead.rawValue
    var sortAscending: Bool = false
}
