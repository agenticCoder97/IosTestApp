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

    private var displayedComics: [LocalComic] {
        var ready = allComics.filter { $0.totalChapters > 0 && $0.title != "Pending scrape..." }
        if filterFavourites {
            ready = ready.filter { $0.isFavorite }
        }
        if !searchText.isEmpty {
            ready = ready.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                ($0.comicDescription ?? "").localizedCaseInsensitiveContains(searchText) ||
                ($0.category ?? "").localizedCaseInsensitiveContains(searchText) ||
                ($0.tagsJSON ?? "").localizedCaseInsensitiveContains(searchText) ||
                ($0.authorsJSON ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
        // Sort archived comics to the bottom
        return ready.sorted { lhs, rhs in
            if lhs.isArchived != rhs.isArchived { return !lhs.isArchived }
            return (lhs.lastReadAt ?? lhs.addedAt) > (rhs.lastReadAt ?? rhs.addedAt)
        }
    }

    private var inProgressComics: [LocalComic] {
        allComics
            .filter { $0.progressPercent > 0 && $0.progressPercent < 1.0 && !$0.isArchived }
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
                    EmptyStateView(
                        icon: filterFavourites ? "heart" : (viewModel.errorMessage != nil ? "wifi.slash" : "book.closed"),
                        title: filterFavourites ? "No Favourites Yet" : (viewModel.errorMessage != nil ? "Offline" : "No Comics Yet"),
                        message: filterFavourites
                            ? "Tap the heart on any comic to add it here."
                            : (viewModel.errorMessage != nil
                                ? "Backend unreachable. Previously synced comics will appear here."
                                : "Browse a source and scrape your first comic to get started.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
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
                            .staggeredAppear(index: index)
                            .contextMenu {
                                if comic.isArchived {
                                    Button {
                                        unarchiveComic(comic)
                                    } label: {
                                        Label("Unarchive", systemImage: "arrow.uturn.left.circle")
                                    }
                                } else if !comic.isArchiving && !comic.isUnarchiving {
                                    Button {
                                        archiveComic(comic)
                                    } label: {
                                        Label("Archive", systemImage: "archivebox")
                                    }
                                }
                                Button(role: .destructive) {
                                    deleteComic(comic)
                                } label: {
                                    Label("Delete", systemImage: "trash")
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
        .task { await viewModel.fetchComics(modelContext: modelContext) }
        .refreshable { await viewModel.fetchComics(modelContext: modelContext, force: true) }
    }

    private func deleteComic(_ comic: LocalComic) {
        Task { try? await APIClient.shared.requestVoid(.deleteComic(id: comic.id)) }
        modelContext.delete(comic)
        try? modelContext.save()
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
        let lastRead = Double(comic.lastReadChapterNumber)
        return chapters.first { $0.chapterNumber > lastRead } ?? chapters.first
    }

    var body: some View {
        NavigationLink {
            ComicDetailView(comic: comic)
        } label: {
            ContinueReadingCard(comic: comic)
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
