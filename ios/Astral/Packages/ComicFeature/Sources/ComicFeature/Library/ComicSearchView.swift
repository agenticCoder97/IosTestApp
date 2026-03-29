import SwiftUI
import SwiftData
import Core
import DesignSystem

struct ComicSearchView: View {
    @Binding var searchText: String

    @Query(
        filter: #Predicate<LocalComic> { $0.status != "deleted" },
        sort: \LocalComic.addedAt,
        order: .reverse
    )
    private var allComics: [LocalComic]

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    // MARK: - JSON helpers

    /// Extracts "name" values from a JSON array of objects.
    /// Handles both `[{"name":"foo","tag_type":"genre"}]` and `[{"id":"...","name":"bar"}]`.
    private func names(from json: String?) -> [String] {
        guard let json,
              let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return array.compactMap { $0["name"] as? String }
    }

    // MARK: - Relevance

    private enum MatchTier: Int, Comparable {
        case title = 0
        case description = 1
        case tag = 2
        case author = 3
        case category = 4
        case source = 5

        static func < (lhs: MatchTier, rhs: MatchTier) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// Returns the best (lowest) tier that matches, or nil if no match.
    private func matchTier(for comic: LocalComic, query: String) -> MatchTier? {
        if comic.title.localizedCaseInsensitiveContains(query) { return .title }

        if let desc = comic.comicDescription,
           desc.localizedCaseInsensitiveContains(query) { return .description }

        let tagNames = names(from: comic.tagsJSON)
        if tagNames.contains(where: { $0.localizedCaseInsensitiveContains(query) }) { return .tag }

        let authorNames = names(from: comic.authorsJSON)
        if authorNames.contains(where: { $0.localizedCaseInsensitiveContains(query) }) { return .author }

        if let cat = comic.category,
           cat.localizedCaseInsensitiveContains(query) { return .category }

        if comic.sourceKey.localizedCaseInsensitiveContains(query) { return .source }

        return nil
    }

    private var filteredComics: [LocalComic] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }

        var tiered: [(comic: LocalComic, tier: MatchTier)] = []
        for comic in allComics {
            if let tier = matchTier(for: comic, query: query) {
                tiered.append((comic, tier))
            }
        }

        // Primary sort: relevance tier. Secondary: original addedAt (already desc from @Query).
        return tiered
            .sorted { $0.tier < $1.tier }
            .map(\.comic)
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: "Search Your Library",
                        message: "Search by title, description, tag, author, source, or category."
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                } else if filteredComics.isEmpty {
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: "No Results",
                        message: "No comics match \"\(searchText.trimmingCharacters(in: .whitespaces))\"."
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                } else {
                    resultCountHeader

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Array(filteredComics.enumerated()), id: \.element.id) { index, comic in
                            NavigationLink {
                                ComicDetailView(comic: comic)
                            } label: {
                                ComicCardView(comic: comic)
                            }
                            .buttonStyle(PressButtonStyle())
                            .staggeredAppear(index: index)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 100)
                }
            }
        }
        .background(AstralColors.background)
        .searchable(text: $searchText, prompt: "Title, tag, author, description…")
    }

    // MARK: - Subviews

    private var resultCountHeader: some View {
        Text(filteredComics.count == 1 ? "1 result" : "\(filteredComics.count) results")
            .font(AstralTypography.caption)
            .foregroundStyle(AstralColors.muted)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }
}
