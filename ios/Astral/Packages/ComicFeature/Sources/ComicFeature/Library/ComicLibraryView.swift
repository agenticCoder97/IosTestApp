import SwiftUI
import SwiftData
import Core
import DesignSystem
import Networking

struct ComicLibraryView: View {
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
        let ready = allComics.filter { $0.totalChapters > 0 && $0.title != "Pending scrape..." }
        return filterFavourites ? ready.filter { $0.isFavorite } : ready
    }

    private var inProgressComics: [LocalComic] {
        allComics
            .filter { $0.progressPercent > 0 && $0.progressPercent < 1.0 }
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
                            .buttonStyle(PressButtonStyle())
                            .staggeredAppear(index: index)
                            .contextMenu {
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
    }

    private func deleteComic(_ comic: LocalComic) {
        Task { try? await APIClient.shared.requestVoid(.deleteComic(id: comic.id)) }
        modelContext.delete(comic)
        try? modelContext.save()
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
        if let chapter = nextChapter, !chapters.isEmpty {
            NavigationLink {
                ComicReaderView(comic: comic, chapters: chapters, startingAt: chapter)
            } label: {
                ContinueReadingCard(comic: comic)
            }
        } else {
            NavigationLink {
                ComicDetailView(comic: comic)
            } label: {
                ContinueReadingCard(comic: comic)
            }
        }
    }
}

private struct ContinueReadingCard: View {
    let comic: LocalComic

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(AstralColors.elevated)
                Image(systemName: "book.fill")
                    .foregroundStyle(AstralColors.muted)
            }
            .frame(width: 100, height: 70)

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
        ComicLibraryView(filterFavourites: false)
            .modelContainer(.previewContainer(
                comics: PreviewMocks.sampleComics,
                comicChapters: PreviewMocks.comic1Chapters
            ))
    }
}

#Preview("Favourites") {
    NavigationStack {
        ComicLibraryView(filterFavourites: true)
            .modelContainer(.previewContainer(comics: PreviewMocks.sampleComics))
    }
}

#Preview("Empty State") {
    ComicLibraryView(filterFavourites: false)
        .modelContainer(for: LocalComic.self, inMemory: true)
}
