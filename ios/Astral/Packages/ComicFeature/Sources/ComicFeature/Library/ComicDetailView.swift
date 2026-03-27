import SwiftUI
import SwiftData
import Core
import DesignSystem

struct ComicDetailView: View {
    let comic: LocalComic

    @Query private var chapters: [LocalComicChapter]

    init(comic: LocalComic) {
        self.comic = comic
        let id = comic.id
        _chapters = Query(
            filter: #Predicate<LocalComicChapter> { $0.comicId == id },
            sort: \LocalComicChapter.chapterNumber
        )
    }

    var body: some View {
        ScrollView {
            if chapters.isEmpty {
                EmptyStateView(
                    icon: "book.closed",
                    title: "No Chapters Yet",
                    message: "Scrape this comic from the browser to load its chapters."
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(chapters) { chapter in
                        NavigationLink {
                            ComicReaderView(comic: comic, chapters: chapters, startingAt: chapter)
                        } label: {
                            ComicChapterRow(chapter: chapter, isLastRead: chapter.chapterNumber == Double(comic.lastReadChapterNumber))
                        }
                        .buttonStyle(.plain)

                        Divider()
                            .background(AstralColors.elevated)
                            .padding(.leading, 16)
                    }
                }
                .padding(.bottom, 100)
            }
        }
        .background(AstralColors.background)
        .navigationTitle(comic.title)
        .navigationBarTitleDisplayMode(.large)
    }
}

private struct ComicChapterRow: View {
    let chapter: LocalComicChapter
    let isLastRead: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Ch. \(chapter.chapterNumber, specifier: chapter.chapterNumber.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f")")
                        .font(AstralTypography.bodyMedium)
                        .foregroundStyle(AstralColors.white)

                    if isLastRead {
                        Text("Last Read")
                            .font(AstralTypography.caption)
                            .foregroundStyle(AstralColors.gold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AstralColors.gold.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }

                if let title = chapter.title {
                    Text(title)
                        .font(AstralTypography.caption)
                        .foregroundStyle(AstralColors.muted)
                }

                HStack(spacing: 8) {
                    if chapter.totalPages > 0 {
                        Text("\(chapter.totalPages) pages")
                            .font(AstralTypography.caption)
                            .foregroundStyle(AstralColors.muted)
                    }
                    if chapter.isDownloaded {
                        StatusBadge.downloaded()
                    }
                }
            }

            Spacer()

            statusIcon(for: chapter.scrapeStatus)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func statusIcon(for status: String) -> some View {
        switch status {
        case "scraped":
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(AstralColors.muted)
        case "pending":
            Image(systemName: "clock")
                .foregroundStyle(AstralColors.muted)
        case "failed":
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(AstralColors.error)
        default:
            EmptyView()
        }
    }
}

// MARK: - Previews

#Preview("With Chapters") {
    let comic = PreviewMocks.comic1
    let chapters = PreviewMocks.comic1Chapters
    return NavigationStack {
        ComicDetailView(comic: comic)
            .modelContainer(
                .previewContainer(comics: [comic], comicChapters: chapters)
            )
    }
}

#Preview("No Chapters") {
    NavigationStack {
        ComicDetailView(comic: PreviewMocks.comic3)
            .modelContainer(.previewContainer(comics: [PreviewMocks.comic3]))
    }
}
