import SwiftUI
import SwiftData
import Core
import DesignSystem

struct ComicLibraryView: View {
    @Query(
        filter: #Predicate<LocalComic> { $0.status != "deleted" },
        sort: \LocalComic.addedAt,
        order: .reverse
    )
    private var comics: [LocalComic]

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        ScrollView {
            if comics.isEmpty {
                EmptyStateView(
                    icon: "book.closed",
                    title: "No Comics Yet",
                    message: "Browse a source and scrape your first comic to get started."
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(comics) { comic in
                        ComicCardView(comic: comic)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 100) // Tab bar clearance
            }
        }
        .background(AstralColors.background)
    }
}

#Preview {
    ComicLibraryView()
        .modelContainer(for: LocalComic.self, inMemory: true)
}
