import SwiftUI
import SwiftData
import Core
import DesignSystem
import Networking

struct ComicLibraryView: View {
    @Binding var searchText: String
    var filterFavourites: Bool

    @State private var viewModel = ComicLibraryViewModel()
    @Environment(\.modelContext) private var modelContext
    @Environment(\.comicNavigation) private var comicNavigation

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

    @State private var pendingDeletion: LocalComic?

    private var displayedComics: [LocalComic] {
        let filter = comicNavigation?.filterState
        var ready = allComics.filter { $0.totalChapters > 0 && $0.title != "Pending scrape..." }

        if filterFavourites { ready = ready.filter { $0.isFavorite } }

        if !searchText.isEmpty {
            ready = ready.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                ($0.comicDescription ?? "").localizedCaseInsensitiveContains(searchText) ||
                ($0.category ?? "").localizedCaseInsensitiveContains(searchText) ||
                ($0.tagsJSON ?? "").localizedCaseInsensitiveContains(searchText) ||
                ($0.authorsJSON ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }

        if !(filter?.showArchived ?? false) {
            ready = ready.filter { !$0.isArchived }
        }
        if let status = filter?.completionStatus {
            ready = ready.filter { $0.completionStatus == status }
        }
        if let keyword = filter?.tagsKeyword, !keyword.isEmpty {
            ready = ready.filter {
                ($0.tagsJSON ?? "").localizedCaseInsensitiveContains(keyword)
            }
        }
        if let cat = filter?.category, !cat.isEmpty {
            ready = ready.filter {
                ($0.category ?? "").localizedCaseInsensitiveContains(cat)
            }
        }
        if let src = filter?.sourceKey {
            ready = ready.filter { $0.sourceKey == src || (src == "mangadex" && $0.sourceKey == "mangadex-device") }
        }

        let ascending = filter?.sortAscending ?? false
        switch filter?.sortBy ?? .lastRead {
        case .lastRead:
            return ready.sorted { ascending
                ? ($0.lastReadAt ?? .distantPast) < ($1.lastReadAt ?? .distantPast)
                : ($0.lastReadAt ?? .distantPast) > ($1.lastReadAt ?? .distantPast)
            }
        case .dateAdded:
            return ready.sorted { ascending ? $0.addedAt < $1.addedAt : $0.addedAt > $1.addedAt }
        case .title:
            return ready.sorted { ascending ? $0.title < $1.title : $0.title > $1.title }
        case .chapters:
            return ready.sorted { ascending
                ? $0.totalChapters < $1.totalChapters
                : $0.totalChapters > $1.totalChapters
            }
        }
    }

    private var inProgressComics: [LocalComic] {
        allComics
            .filter { $0.lastReadAt != nil && $0.completedAt == nil && !$0.isArchived }
            .sorted { ($0.lastReadAt ?? $0.addedAt) > ($1.lastReadAt ?? $1.addedAt) }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Backend error banner
                if let error = viewModel.errorMessage {
                    BackendStatusBanner(error) {
                        Task { await viewModel.fetchComics(modelContext: modelContext) }
                    }
                }

                if let latestSync = displayedComics.compactMap(\.lastSyncedAt).max() {
                    HStack {
                        Spacer()
                        Text("Updated \(latestSync, format: .relative(presentation: .named))")
                            .font(AstralTypography.caption)
                            .foregroundStyle(AstralColors.muted)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                }

                if !filterFavourites && !inProgressComics.isEmpty {
                    ContinueReadingStrip(comics: inProgressComics)
                        .padding(.top, 8)
                }

                if displayedComics.isEmpty {
                    EmptyStateView(icon: "books.vertical",
                        title: (!searchText.isEmpty || comicNavigation?.filterState.isActive == true) ? "No matches" : "No comics yet",
                        message: "Import a comic in Add. Saved stories stay available without a companion.")
                        .frame(maxWidth: .infinity).padding(.top, 80)
                    if !searchText.isEmpty || comicNavigation?.filterState.isActive == true {
                        Button("Clear search and filters") { searchText = ""; comicNavigation?.filterState.reset() }
                            .frame(maxWidth: .infinity).padding()
                    } else {
                        Button("Add comic") { comicNavigation?.activeSection = .browse }.frame(maxWidth: .infinity).padding()
                    }
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Array(displayedComics.enumerated()), id: \.element.id) { index, comic in
                            NavigationLink {
                                ComicDetailView(comic: comic)
                            } label: {
                                ComicCardView(comic: comic)
                            }
                            .accessibilityIdentifier(AccessibilityID.storyCard(comic.id))
                            .buttonStyle(PressButtonStyle())
                            .contextMenu {
                                Button(role: .destructive) {
                                    pendingDeletion = comic
                                } label: {
                                    Label("Delete permanently", systemImage: "trash.slash")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 100)
                }
            }
        }
        .background(AstralColors.background)

        .refreshable { if AppConfig.companionEnabled { await viewModel.fetchComics(modelContext: modelContext, force: true) } }
        .deletePermanentlyAlert(
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            storyTitle: pendingDeletion?.title ?? "",
            onConfirm: {
                if let comic = pendingDeletion {
                    let id = comic.id
                    Task {
                        let descriptor = FetchDescriptor<LocalComicChapter>(
                            predicate: #Predicate<LocalComicChapter> { $0.comicId == id }
                        )
                        let chapters = (try? modelContext.fetch(descriptor)) ?? []
                        await StoryDeletionService.shared.permanentlyDelete(
                            comic: comic,
                            modelContext: modelContext,
                            deleteFiles: {
                                ChapterDownloadService.shared.deleteAllChapters(
                                    comic: comic,
                                    chapters: chapters,
                                    modelContext: modelContext
                                )
                            }
                        )
                    }
                }
                pendingDeletion = nil
            }
        )
    }

    private func archiveComic(_ comic: LocalComic) {
        comic.archiveStatus = "archiving"
        try? modelContext.save()
        Task {
            let _: ComicResponse? = try? await APIClient.shared.request(.archiveComic(id: comic.id))
        }
    }

    private func unarchiveComic(_ comic: LocalComic) {
        comic.archiveStatus = "unarchiving"
        try? modelContext.save()
        Task {
            let _: ComicResponse? = try? await APIClient.shared.request(.unarchiveComic(id: comic.id))
        }
    }
}

// MARK: - Continue Reading Strip

private struct ContinueReadingStrip: View {
    let comics: [LocalComic]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Continue Reading")
                .font(AstralTypography.captionMedium)
                .foregroundStyle(AstralColors.muted)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(comics) { comic in
                        ContinueReadingCardLink(comic: comic)
                            .buttonStyle(PressButtonStyle(scale: 0.94))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            }
        }
        .padding(.bottom, 16)
    }
}

private struct ContinueReadingCardLink: View {
    let comic: LocalComic
    @Query private var chapters: [LocalComicChapter]

    init(comic: LocalComic) {
        self.comic = comic
        let comicId = comic.id
        _chapters = Query(
            filter: #Predicate<LocalComicChapter> { $0.comicId == comicId },
            sort: \LocalComicChapter.chapterNumber
        )
    }

    private var nextChapter: LocalComicChapter? {
        return chapters.first { $0.id == ReadingPositionStore.position(story: comic.id)?.chapterID } ?? chapters.first { $0.chapterNumber == Double(comic.lastReadChapterNumber) } ?? chapters.first
    }

    @State private var openChapter: LocalComicChapter?

    // Full-screen presentation, like comic detail: the reader owns the status bar
    // and is not built eagerly while the strip lays out.
    var body: some View {
        Button { openChapter = nextChapter } label: {
            ContinueReadingCard(comic: comic)
        }
        .accessibilityHint("Opens the reader at your saved position")
        .fullScreenCover(item: $openChapter) { chapter in
            ComicReaderView(comic: comic, chapters: chapters, startingAt: chapter)
        }
    }
}

private struct ContinueReadingCard: View {
    let comic: LocalComic

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            StoryThumbnail(path: comic.thumbnailPath, title: comic.title, icon: "book.fill", width: 100, height: 70, baseURL: AppConfig.staticBaseURL)

            Text(comic.title)
                .font(AstralTypography.caption)
                .foregroundStyle(AstralColors.white)
                .lineLimit(1)
                .frame(width: 100, alignment: .leading)

            ProgressBarView(progress: comic.progressPercent)
                .frame(width: 100)
        }
        .padding(8)
        .background(AstralColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Previews

#Preview("Library") {
    NavigationStack {
        ComicLibraryView(searchText: .constant(""), filterFavourites: false)
            .modelContainer(.previewContainer(
                comics: PreviewMocks.sampleComics,
                comicChapters: PreviewMocks.comic1Chapters
            ))
    }
}

#Preview("Favourites") {
    NavigationStack {
        ComicLibraryView(searchText: .constant(""), filterFavourites: true)
            .modelContainer(.previewContainer(comics: PreviewMocks.sampleComics))
    }
}

#Preview("Empty State") {
    ComicLibraryView(searchText: .constant(""), filterFavourites: false)
        .modelContainer(for: LocalComic.self, inMemory: true)
}
