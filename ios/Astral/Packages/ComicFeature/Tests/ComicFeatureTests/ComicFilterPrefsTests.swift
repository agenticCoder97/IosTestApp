import Testing
import Foundation
@testable import ComicFeature

@Suite("ComicFilterPrefs")
struct ComicFilterPrefsTests {

    @Test("round-trip encode/decode preserves all fields")
    func roundTrip() throws {
        let prefs = ComicFilterPrefs(
            showArchived: true,
            completionStatus: "complete",
            tagsKeyword: "magic",
            category: "webtoon",
            sourceKey: "nhentai",
            sortBy: "Title",
            sortAscending: true
        )
        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(ComicFilterPrefs.self, from: data)

        #expect(decoded.showArchived == prefs.showArchived)
        #expect(decoded.completionStatus == prefs.completionStatus)
        #expect(decoded.tagsKeyword == prefs.tagsKeyword)
        #expect(decoded.category == prefs.category)
        #expect(decoded.sourceKey == prefs.sourceKey)
        #expect(decoded.sortBy == prefs.sortBy)
        #expect(decoded.sortAscending == prefs.sortAscending)
    }

    @Test("defaults encode and decode cleanly")
    func defaultRoundTrip() throws {
        let prefs = ComicFilterPrefs()
        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(ComicFilterPrefs.self, from: data)
        #expect(decoded.showArchived == false)
        #expect(decoded.completionStatus == nil)
        #expect(decoded.tagsKeyword == "")
        #expect(decoded.category == nil)
        #expect(decoded.sourceKey == nil)
        #expect(decoded.sortBy == ComicSortOption.lastRead.rawValue)
        #expect(decoded.sortAscending == false)
    }

    @Test("ComicSortOption.allCases contains lastRead")
    func lastReadInAllCases() {
        let cases = ComicSortOption.allCases
        #expect(cases.contains(.lastRead))
    }

    @Test("ComicFilterState.isActive is false with defaults")
    @MainActor
    func isActiveDefaultFalse() {
        let state = ComicFilterState()
        #expect(state.isActive == false)
    }

    @Test("ComicFilterState.isActive is true when showArchived set")
    @MainActor
    func isActiveWhenShowArchivedSet() {
        let state = ComicFilterState()
        state.showArchived = true
        #expect(state.isActive == true)
    }

    @Test("ComicFilterState.isActive is true when completionStatus set")
    @MainActor
    func isActiveWhenCompletionStatusSet() {
        let state = ComicFilterState()
        state.completionStatus = "ongoing"
        #expect(state.isActive == true)
    }

    @Test("ComicFilterState.isActive is true when tagsKeyword set")
    @MainActor
    func isActiveWhenTagsKeywordSet() {
        let state = ComicFilterState()
        state.tagsKeyword = "magic"
        #expect(state.isActive == true)
    }

    @Test("ComicFilterState load and snapshotForPersistence round-trip")
    @MainActor
    func loadAndSnapshot() {
        let prefs = ComicFilterPrefs(
            showArchived: true,
            completionStatus: "complete",
            tagsKeyword: "romance",
            category: nil,
            sourceKey: "toongod",
            sortBy: ComicSortOption.title.rawValue,
            sortAscending: false
        )
        let state = ComicFilterState()
        state.load(from: prefs)

        let snapshot = state.snapshotForPersistence
        #expect(snapshot.showArchived == prefs.showArchived)
        #expect(snapshot.completionStatus == prefs.completionStatus)
        #expect(snapshot.tagsKeyword == prefs.tagsKeyword)
        #expect(snapshot.sourceKey == prefs.sourceKey)
        #expect(snapshot.sortBy == prefs.sortBy)
        #expect(snapshot.sortAscending == prefs.sortAscending)
    }

    @Test("ComicFilterState.reset clears all fields to defaults")
    @MainActor
    func resetClearsFields() {
        let state = ComicFilterState()
        state.showArchived = true
        state.completionStatus = "complete"
        state.tagsKeyword = "magic"
        state.sourceKey = "nhentai"
        state.sortBy = .title

        state.reset()

        #expect(state.showArchived == false)
        #expect(state.completionStatus == nil)
        #expect(state.tagsKeyword == "")
        #expect(state.sourceKey == nil)
        #expect(state.sortBy == .lastRead)
        #expect(state.isActive == false)
    }
}
