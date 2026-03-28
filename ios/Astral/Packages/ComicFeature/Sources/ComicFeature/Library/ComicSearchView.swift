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

    private var filteredComics: [LocalComic] {
        guard !searchText.isEmpty else { return allComics }
        let query = searchText.lowercased()
        return allComics.filter { comic in
            if comic.title.localizedCaseInsensitiveContains(query) { return true }
            if comic.sourceKey.localizedCaseInsensitiveContains(query) { return true }
            if let category = comic.category,
               category.localizedCaseInsensitiveContains(query) { return true }
            if let tagsJSON = comic.tagsJSON,
               tagsJSON.localizedCaseInsensitiveContains(query) { return true }
            if let authorsJSON = comic.authorsJSON,
               authorsJSON.localizedCaseInsensitiveContains(query) { return true }
            return false
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if filteredComics.isEmpty {
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: searchText.isEmpty ? "Search Your Library" : "No Results",
                        message: searchText.isEmpty
                            ? "Search by title, tag, author, source, or category."
                            : "No comics match \"\(searchText)\"."
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                } else {
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
        .searchable(text: $searchText, prompt: "Title, tag, author, source…")
    }
}
