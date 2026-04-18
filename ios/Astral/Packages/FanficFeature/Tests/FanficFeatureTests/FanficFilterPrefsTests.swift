import Testing
import Foundation
@testable import FanficFeature

@Suite("FanficFilterPrefs")
struct FanficFilterPrefsTests {

    @Test("round-trip encode/decode preserves all fields")
    func roundTrip() throws {
        let prefs = FanficFilterPrefs(
            fandom: "Harry Potter",
            completionStatus: "complete",
            wordCountMin: 10_000,
            wordCountMax: 100_000,
            selectedRatings: ["M", "E"],
            selectedWarnings: ["violence"],
            characters: "Hermione",
            relationship: "Harry/Ginny",
            sourceKey: "ao3",
            sortBy: "Last Read",
            sortAscending: true
        )
        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(FanficFilterPrefs.self, from: data)

        #expect(decoded.fandom == prefs.fandom)
        #expect(decoded.completionStatus == prefs.completionStatus)
        #expect(decoded.wordCountMin == prefs.wordCountMin)
        #expect(decoded.wordCountMax == prefs.wordCountMax)
        #expect(decoded.selectedRatings == prefs.selectedRatings)
        #expect(decoded.selectedWarnings == prefs.selectedWarnings)
        #expect(decoded.characters == prefs.characters)
        #expect(decoded.relationship == prefs.relationship)
        #expect(decoded.sourceKey == prefs.sourceKey)
        #expect(decoded.sortBy == prefs.sortBy)
        #expect(decoded.sortAscending == prefs.sortAscending)
    }

    @Test("defaults encode and decode cleanly")
    func defaultRoundTrip() throws {
        let prefs = FanficFilterPrefs()
        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(FanficFilterPrefs.self, from: data)
        #expect(decoded.fandom == "")
        #expect(decoded.completionStatus == nil)
        #expect(decoded.wordCountMin == nil)
        #expect(decoded.wordCountMax == nil)
        #expect(decoded.selectedRatings.isEmpty)
        #expect(decoded.sortBy == FanficSortOption.lastRead.rawValue)
        #expect(decoded.sortAscending == false)
    }

    @Test("FanficSortOption.allCases contains lastRead")
    func lastReadInAllCases() {
        let cases = FanficSortOption.allCases
        #expect(cases.contains(.lastRead))
    }

    @Test("FanficFilterState.isActive is false with defaults")
    @MainActor
    func isActiveDefaultFalse() {
        let state = FanficFilterState()
        #expect(state.isActive == false)
    }

    @Test("FanficFilterState.isActive is true when completionStatus set")
    @MainActor
    func isActiveWhenFieldSet() {
        let state = FanficFilterState()
        state.completionStatus = "complete"
        #expect(state.isActive == true)
    }

    @Test("FanficFilterState.isActive is true when fandom set")
    @MainActor
    func isActiveWhenFandomSet() {
        let state = FanficFilterState()
        state.fandom = "Harry Potter"
        #expect(state.isActive == true)
    }

    @Test("FanficFilterState load and snapshotForPersistence round-trip")
    @MainActor
    func loadAndSnapshot() {
        let prefs = FanficFilterPrefs(
            fandom: "Naruto",
            completionStatus: "ongoing",
            wordCountMin: 5_000,
            wordCountMax: nil,
            selectedRatings: ["G"],
            selectedWarnings: [],
            characters: "",
            relationship: "",
            sourceKey: "ao3",
            sortBy: FanficSortOption.title.rawValue,
            sortAscending: true
        )
        let state = FanficFilterState()
        state.load(from: prefs)

        let snapshot = state.snapshotForPersistence
        #expect(snapshot.fandom == prefs.fandom)
        #expect(snapshot.completionStatus == prefs.completionStatus)
        #expect(snapshot.wordCountMin == prefs.wordCountMin)
        #expect(snapshot.sourceKey == prefs.sourceKey)
        #expect(snapshot.sortBy == prefs.sortBy)
        #expect(snapshot.sortAscending == prefs.sortAscending)
    }
}
