import SwiftUI
import SwiftData
import Core
import DesignSystem

struct FanficStatsView: View {
    @Query(filter: #Predicate<LocalComic> { $0.status != "deleted" })
    private var comics: [LocalComic]

    @Query(filter: #Predicate<LocalFanfic> { $0.completionStatus != "deleted" })
    private var fanfics: [LocalFanfic]

    @Query private var bookmarks: [LocalBookmark]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Reading Stats")
                    .font(AstralTypography.title)
                    .foregroundStyle(AstralColors.white)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                statsCard(title: "Fan Fiction", systemImage: "scroll.fill", index: 0) {
                    statRow("Total in library", value: "\(fanfics.count)")
                    statRow("In progress", value: "\(fanfics.filter { $0.progressPercent > 0 && $0.progressPercent < 1.0 }.count)")
                    statRow("Completed", value: "\(fanfics.filter { $0.progressPercent >= 1.0 }.count)")
                    statRow("Favourites", value: "\(fanfics.filter { $0.isFavorite }.count)")
                    statRow("Est. words read", value: formattedWords(fanfics.reduce(0) { $0 + $1.estimatedWordsRead }))
                    statRow("New chapter alerts", value: "\(fanfics.filter { $0.newChapterCount > 0 }.count)")
                }

                statsCard(title: "Comics", systemImage: "book.closed.fill", index: 1) {
                    statRow("Total in library", value: "\(comics.count)")
                    statRow("In progress", value: "\(comics.filter { $0.progressPercent > 0 && $0.progressPercent < 1.0 }.count)")
                    statRow("Favourites", value: "\(comics.filter { $0.isFavorite }.count)")
                }

                statsCard(title: "Bookmarks", systemImage: "bookmark.fill", index: 2) {
                    statRow("Total saved", value: "\(bookmarks.count)")
                    statRow("Comic", value: "\(bookmarks.filter { $0.contentType == "comic" }.count)")
                    statRow("Fanfic", value: "\(bookmarks.filter { $0.contentType == "fanfic" }.count)")
                }

                Spacer().frame(height: 100)
            }
        }
        .background(AstralColors.background)
    }

    @ViewBuilder
    private func statsCard<Content: View>(
        title: String,
        systemImage: String,
        index: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(AstralColors.gold)
                Text(title)
                    .font(AstralTypography.titleSmall)
                    .foregroundStyle(AstralColors.white)
            }
            Divider().background(AstralColors.border)
            content()
        }
        .padding(16)
        .astralCard()
        .padding(.horizontal, 16)
        .staggeredAppear(index: index)
    }

    private func statRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(AstralTypography.body)
                .foregroundStyle(AstralColors.body)
            Spacer()
            Text(value)
                .font(AstralTypography.bodyMedium)
                .foregroundStyle(AstralColors.white)
                .contentTransition(.numericText())
                .animation(AstralAnimation.smooth, value: value)
        }
    }

    private func formattedWords(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return "\(count / 1_000)K" }
        return "\(count)"
    }
}

#Preview {
    FanficStatsView()
        .modelContainer(.previewContainer(
            comics: PreviewMocks.sampleComics,
            fanfics: PreviewMocks.sampleFanfics,
            bookmarks: PreviewMocks.sampleBookmarks
        ))
}
