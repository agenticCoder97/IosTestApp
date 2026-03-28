import SwiftUI
import SwiftData
import Core
import DesignSystem

struct ComicDetailView: View {
    let comic: LocalComic

    @Environment(\.modelContext) private var modelContext
    @Query private var chapters: [LocalComicChapter]
    @Query private var bookmarks: [LocalBookmark]

    init(comic: LocalComic) {
        self.comic = comic
        let id = comic.id
        _chapters = Query(
            filter: #Predicate<LocalComicChapter> { $0.comicId == id },
            sort: \LocalComicChapter.chapterNumber
        )
        _bookmarks = Query(
            filter: #Predicate<LocalBookmark> { $0.storyId == id && $0.contentType == "comic" },
            sort: \LocalBookmark.createdAt,
            order: .reverse
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // MARK: Thumbnail + description header
                if comic.thumbnailPath != nil || comic.comicDescription != nil {
                    HStack(alignment: .top, spacing: 12) {
                        if let path = comic.thumbnailPath {
                            AsyncImage(url: thumbnailURL(path)) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                default:
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(AstralColors.elevated)
                                        .overlay {
                                            Image(systemName: "book.fill")
                                                .foregroundStyle(AstralColors.muted)
                                        }
                                }
                            }
                            .frame(width: 100)
                            .aspectRatio(3/4, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        if let desc = comic.comicDescription {
                            Text(desc)
                                .font(AstralTypography.caption)
                                .foregroundStyle(AstralColors.body)
                                .lineLimit(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(16)
                }

                // MARK: Bookmarks section
                if !bookmarks.isEmpty {
                    BookmarksSection(bookmarks: bookmarks, onDelete: deleteBookmark)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                }

                // MARK: Chapter list
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
                                ComicChapterRow(
                                    chapter: chapter,
                                    isLastRead: chapter.chapterNumber == Double(comic.lastReadChapterNumber),
                                    isBookmarked: bookmarks.contains { $0.chapterNumber == chapter.chapterNumber }
                                )
                            }
                            .buttonStyle(PressButtonStyle(scale: 0.98))
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    withAnimation(AstralAnimation.bouncy) {
                                        addBookmark(for: chapter)
                                    }
                                } label: {
                                    Label("Bookmark", systemImage: "bookmark")
                                }
                                .tint(AstralColors.gold)
                            }

                            Divider()
                                .background(AstralColors.elevated)
                                .padding(.leading, 16)
                        }
                    }
                    .padding(.bottom, 100)
                }
            }
        }
        .background(AstralColors.background)
        .navigationTitle(comic.title)
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            comic.seenTotalChapters = comic.totalChapters
            comic.lastReadAt = .now
            try? modelContext.save()
        }
    }

    private func thumbnailURL(_ path: String) -> URL? {
        if path.hasPrefix("http") { return URL(string: path) }
        return URL(string: AppConfig.staticBaseURL + path)
    }

    private func addBookmark(for chapter: LocalComicChapter) {
        let bookmark = LocalBookmark(
            contentType: "comic",
            storyId: comic.id,
            chapterNumber: chapter.chapterNumber
        )
        modelContext.insert(bookmark)
        try? modelContext.save()
    }

    private func deleteBookmark(_ bookmark: LocalBookmark) {
        modelContext.delete(bookmark)
        try? modelContext.save()
    }
}

// MARK: - Bookmarks Section

private struct BookmarksSection: View {
    let bookmarks: [LocalBookmark]
    let onDelete: (LocalBookmark) -> Void

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header — rotates chevron instead of swapping symbols
            Button {
                withAnimation(AstralAnimation.smooth) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "bookmark.fill")
                        .foregroundStyle(AstralColors.gold)
                    Text("Bookmarks (\(bookmarks.count))")
                        .font(AstralTypography.bodyMedium)
                        .foregroundStyle(AstralColors.white)
                    Spacer()
                    Image(systemName: "chevron.up")
                        .font(.caption)
                        .foregroundStyle(AstralColors.muted)
                        .rotationEffect(.degrees(isExpanded ? 0 : -180))
                        .animation(AstralAnimation.smooth, value: isExpanded)
                }
            }
            .buttonStyle(.plain)

            // Rows — push in from top on expand, fade out on collapse
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(bookmarks) { bookmark in
                        HStack {
                            Text(bookmark.displayLabel)
                                .font(AstralTypography.caption)
                                .foregroundStyle(AstralColors.body)
                            if let note = bookmark.note {
                                Text("— \(note)")
                                    .font(AstralTypography.caption)
                                    .foregroundStyle(AstralColors.muted)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button {
                                withAnimation(AstralAnimation.snappy) {
                                    onDelete(bookmark)
                                }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundStyle(AstralColors.error)
                            }
                            .buttonStyle(PressButtonStyle(scale: 0.85))
                        }
                        .padding(.vertical, 4)
                    }
                }
                .transition(
                    .asymmetric(
                        insertion: .push(from: .top).combined(with: .opacity),
                        removal: .opacity.combined(with: .scale(scale: 0.97, anchor: .top))
                    )
                )
            }
        }
        .padding(12)
        .astralCard()
    }
}

// MARK: - Chapter Row

private struct ComicChapterRow: View {
    let chapter: LocalComicChapter
    let isLastRead: Bool
    let isBookmarked: Bool

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

                    if isBookmarked {
                        Image(systemName: "bookmark.fill")
                            .font(.caption)
                            .foregroundStyle(AstralColors.gold)
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }
                }
                .animation(AstralAnimation.bouncy, value: isBookmarked)

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

#Preview("With Chapters + Bookmarks") {
    let comic = PreviewMocks.comic1
    let chapters = PreviewMocks.comic1Chapters
    let bookmarks = PreviewMocks.sampleBookmarks.filter { $0.storyId == comic.id }
    return NavigationStack {
        ComicDetailView(comic: comic)
            .modelContainer(
                .previewContainer(comics: [comic], comicChapters: chapters, bookmarks: bookmarks)
            )
    }
}

#Preview("No Chapters") {
    NavigationStack {
        ComicDetailView(comic: PreviewMocks.comic3)
            .modelContainer(.previewContainer(comics: [PreviewMocks.comic3]))
    }
}
