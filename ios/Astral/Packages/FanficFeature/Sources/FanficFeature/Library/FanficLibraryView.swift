import SwiftUI
import SwiftData
import Core
import DesignSystem
import Networking

struct FanficLibraryView: View {
    @Binding var searchText: String
    var filterFavourites: Bool

    @State private var viewModel = FanficLibraryViewModel()
    @Environment(\.modelContext) private var modelContext
    @Environment(\.fanficNavigation) private var fanficNavigation

    @Query(
        filter: #Predicate<LocalFanfic> { $0.completionStatus != "deleted" },
        sort: \LocalFanfic.addedAt,
        order: .reverse
    )
    private var allFanfics: [LocalFanfic]

    @State private var showFilter = false
    @State private var filterState = FanficFilterState()

    private var inProgressFanfics: [LocalFanfic] {
        allFanfics
            .filter { $0.progressPercent > 0 && $0.progressPercent < 1.0 }
            .sorted { ($0.lastReadAt ?? $0.addedAt) > ($1.lastReadAt ?? $1.addedAt) }
            .prefix(5)
            .map { $0 }
    }

    private var filteredFanfics: [LocalFanfic] {
        var result = allFanfics.filter { $0.totalChapters > 0 && $0.title != "Pending scrape..." }
        if filterFavourites {
            result = result.filter { $0.isFavorite }
        }

        if !searchText.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                ($0.fandom ?? "").localizedCaseInsensitiveContains(searchText) ||
                ($0.characters ?? "").localizedCaseInsensitiveContains(searchText) ||
                ($0.pairing ?? "").localizedCaseInsensitiveContains(searchText) ||
                ($0.summary ?? "").localizedCaseInsensitiveContains(searchText) ||
                ($0.rating ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }

        // Apply filters from FanficFilterState
        if !filterState.fandom.isEmpty {
            result = result.filter { ($0.fandom ?? "").localizedCaseInsensitiveContains(filterState.fandom) }
        }
        if let status = filterState.completionStatus {
            result = result.filter { $0.completionStatus == status.rawValue }
        }
        if !filterState.selectedRatings.isEmpty {
            result = result.filter { fanfic in
                guard let rating = fanfic.rating else { return filterState.selectedRatings.contains("NR") }
                // Match short codes (G, T, M, E) or full names
                return filterState.selectedRatings.contains { code in
                    rating == code || rating.localizedCaseInsensitiveContains(ratingFullName(code))
                }
            }
        }
        if !filterState.selectedWarnings.isEmpty {
            result = result.filter { fanfic in
                guard let warnings = fanfic.warnings else { return false }
                return filterState.selectedWarnings.contains { warnings.localizedCaseInsensitiveContains($0) }
            }
        }
        if !filterState.characters.isEmpty {
            result = result.filter { ($0.characters ?? "").localizedCaseInsensitiveContains(filterState.characters) }
        }
        if !filterState.relationship.isEmpty {
            result = result.filter { ($0.pairing ?? "").localizedCaseInsensitiveContains(filterState.relationship) }
        }
        if let min = filterState.wordCountMin {
            result = result.filter { ($0.wordCount ?? 0) >= min }
        }
        if let max = filterState.wordCountMax {
            result = result.filter { ($0.wordCount ?? 0) <= max }
        }

        // Sort
        let ascending = filterState.sortAscending
        switch filterState.sortBy {
        case .dateAdded:
            return result.sorted { ascending ? $0.addedAt < $1.addedAt : $0.addedAt > $1.addedAt }
        case .dateUpdated:
            return result.sorted { ascending
                ? ($0.updatedAtSource ?? $0.addedAt) < ($1.updatedAtSource ?? $1.addedAt)
                : ($0.updatedAtSource ?? $0.addedAt) > ($1.updatedAtSource ?? $1.addedAt)
            }
        case .wordCount:
            return result.sorted { ascending ? ($0.wordCount ?? 0) < ($1.wordCount ?? 0) : ($0.wordCount ?? 0) > ($1.wordCount ?? 0) }
        case .title:
            return result.sorted { ascending ? $0.title < $1.title : $0.title > $1.title }
        case .chapters:
            return result.sorted { ascending ? $0.totalChapters < $1.totalChapters : $0.totalChapters > $1.totalChapters }
        }
    }

    private func ratingFullName(_ code: String) -> String {
        switch code {
        case "G": "General"
        case "T": "Teen"
        case "M": "Mature"
        case "E": "Explicit"
        case "NR": "Not Rated"
        default: code
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Backend error banner
                if let error = viewModel.errorMessage {
                    BackendStatusBanner(error) {
                        Task { await viewModel.fetchFanfics(modelContext: modelContext) }
                    }
                }

                if !filterFavourites && !inProgressFanfics.isEmpty && searchText.isEmpty {
                    FanficContinueReadingStrip(fanfics: inProgressFanfics)
                        .padding(.top, 8)
                }

                if filteredFanfics.isEmpty {
                    EmptyStateView(
                        icon: filterFavourites ? "heart" : (viewModel.errorMessage != nil ? "wifi.slash" : "scroll"),
                        title: filterFavourites ? "No Favourites Yet" : (viewModel.errorMessage != nil ? "Offline" : "No Fan Fiction Yet"),
                        message: filterFavourites
                            ? "Tap the heart on any story to add it here."
                            : (viewModel.errorMessage != nil
                                ? "Backend unreachable. Previously synced stories will appear here."
                                : "Browse AO3 or FFNet and scrape your first story.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(Array(filteredFanfics.enumerated()), id: \.element.id) { index, fanfic in
                            NavigationLink {
                                FanficDetailView(fanfic: fanfic)
                            } label: {
                                FanficRowView(fanfic: fanfic)
                            }
                            .buttonStyle(PressButtonStyle())
                            .staggeredAppear(index: index)
                            .contextMenu {
                                Button(role: .destructive) {
                                    deleteFanfic(fanfic)
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
        .task { await viewModel.fetchFanfics(modelContext: modelContext) }
        .sheet(isPresented: Binding(
            get: { fanficNavigation?.showFilter ?? false },
            set: { fanficNavigation?.showFilter = $0 }
        )) {
            FanficFilterView(filterState: filterState)
                .presentationDetents([.medium, .large])
        }
    }

    private func deleteFanfic(_ fanfic: LocalFanfic) {
        Task { try? await APIClient.shared.requestVoid(.deleteFanfic(id: fanfic.id)) }
        modelContext.delete(fanfic)
        try? modelContext.save()
    }
}


// MARK: - Continue Reading Strip

private struct FanficContinueReadingStrip: View {
    let fanfics: [LocalFanfic]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Continue Reading")
                .font(AstralTypography.captionMedium)
                .foregroundStyle(AstralColors.muted)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(fanfics) { fanfic in
                        FanficContinueCardLink(fanfic: fanfic)
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

private struct FanficContinueCardLink: View {
    let fanfic: LocalFanfic
    @Query private var chapters: [LocalFanficChapter]

    init(fanfic: LocalFanfic) {
        self.fanfic = fanfic
        let fanficId = fanfic.id
        _chapters = Query(
            filter: #Predicate<LocalFanficChapter> { $0.fanficId == fanficId },
            sort: \LocalFanficChapter.chapterNumber
        )
    }

    private var nextChapter: LocalFanficChapter? {
        let lastRead = Double(fanfic.lastReadChapterNumber)
        return chapters.first { $0.chapterNumber > lastRead } ?? chapters.first
    }

    var body: some View {
        if let chapter = nextChapter, !chapters.isEmpty {
            NavigationLink {
                FanficReaderView(fanfic: fanfic, chapter: chapter)
            } label: {
                FanficContinueCard(fanfic: fanfic)
            }
        } else {
            NavigationLink {
                FanficDetailView(fanfic: fanfic)
            } label: {
                FanficContinueCard(fanfic: fanfic)
            }
        }
    }
}

private struct FanficContinueCard: View {
    let fanfic: LocalFanfic

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            StoryThumbnail(path: fanfic.thumbnailPath, title: fanfic.title, icon: "scroll.fill", width: 100, height: 70, baseURL: AppConfig.staticBaseURL)

            Text(fanfic.title)
                .font(AstralTypography.caption)
                .foregroundStyle(AstralColors.white)
                .lineLimit(1)
                .frame(width: 100, alignment: .leading)

            ProgressBarView(progress: fanfic.progressPercent)
                .frame(width: 100)
        }
        .padding(8)
        .background(AstralColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Previews

#Preview("With Fanfics") {
    NavigationStack {
        FanficLibraryView(searchText: .constant(""), filterFavourites: false)
            .modelContainer(.previewContainer(fanfics: PreviewMocks.sampleFanfics))
            .navigationTitle("Fan Fiction")
    }
}

#Preview("Favourites") {
    NavigationStack {
        FanficLibraryView(searchText: .constant(""), filterFavourites: true)
            .modelContainer(.previewContainer(fanfics: PreviewMocks.sampleFanfics))
            .navigationTitle("Favourites")
    }
}

#Preview("Empty State") {
    NavigationStack {
        FanficLibraryView(searchText: .constant(""), filterFavourites: false)
            .modelContainer(for: LocalFanfic.self, inMemory: true)
            .navigationTitle("Fan Fiction")
    }
}

// MARK: - Row View

struct FanficRowView: View {
    let fanfic: LocalFanfic

    @Environment(\.modelContext) private var modelContext

    private var progressPercent: Double {
        guard fanfic.totalChapters > 0 else { return 0 }
        return Double(fanfic.lastReadChapterNumber) / Double(fanfic.totalChapters)
    }

    private func thumbnailURL(_ path: String) -> URL? {
        if path.hasPrefix("http") { return URL(string: path) }
        return URL(string: AppConfig.staticBaseURL + path)
    }

    private var sourceIcon: String {
        switch fanfic.sourceKey {
        case "ao3": "a.square.fill"
        case "ffnet": "f.square.fill"
        default: "questionmark.square.fill"
        }
    }

    private var fanficPlaceholder: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(AstralColors.elevated)
            .frame(width: 50, height: 70)
            .overlay {
                Image(systemName: "scroll")
                    .foregroundStyle(AstralColors.muted)
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                // Thumbnail with new-chapter badge
                ZStack(alignment: .topTrailing) {
                    if let path = fanfic.thumbnailPath, let url = thumbnailURL(path) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            default:
                                fanficPlaceholder
                            }
                        }
                        .frame(width: 50, height: 70)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        fanficPlaceholder
                    }

                    if fanfic.newChapterCount > 0 {
                        Text("+\(fanfic.newChapterCount)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(AstralColors.gold)
                            .clipShape(Capsule())
                            .offset(x: 4, y: -4)
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }
                }
                .animation(AstralAnimation.bouncy, value: fanfic.newChapterCount)

                VStack(alignment: .leading, spacing: 4) {
                    // Title + source icon + favourite
                    HStack(spacing: 6) {
                        Text(fanfic.title)
                            .font(AstralTypography.bodyMedium)
                            .foregroundStyle(AstralColors.white)
                            .lineLimit(2)

                        Spacer()

                        Image(systemName: sourceIcon)
                            .font(.system(size: 14))
                            .foregroundStyle(AstralColors.muted)

                        Button {
                            withAnimation(AstralAnimation.bouncy) {
                                fanfic.isFavorite.toggle()
                            }
                            try? modelContext.save()
                        } label: {
                            Image(systemName: fanfic.isFavorite ? "heart.fill" : "heart")
                                .font(.system(size: 14))
                                .foregroundStyle(fanfic.isFavorite ? AstralColors.error : AstralColors.muted)
                                .contentTransition(.symbolEffect(.replace.downUp))
                                .scaleEffect(fanfic.isFavorite ? 1.18 : 1.0)
                                .animation(AstralAnimation.bouncy, value: fanfic.isFavorite)
                        }
                        .buttonStyle(.plain)
                    }

                    // Summary
                    if let summary = fanfic.summary, !summary.isEmpty {
                        Text(summary)
                            .font(AstralTypography.caption)
                            .foregroundStyle(AstralColors.body)
                            .lineLimit(2)
                    }

                    // Tags row — fandom, rating, status, word count
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            if let fandom = fanfic.fandom, !fandom.isEmpty {
                                StatusBadge(fandom)
                            }
                            if let rating = fanfic.rating, !rating.isEmpty {
                                StatusBadge(rating)
                            }
                            StatusBadge(fanfic.completionStatus)
                            if let wc = fanfic.wordCount, wc > 0 {
                                StatusBadge("\(wc / 1000)K words", color: AstralColors.muted)
                            }
                        }
                    }

                    // Metadata row — chapters, dates
                    HStack(spacing: 12) {
                        Label("\(fanfic.totalChapters) ch", systemImage: "book.pages")
                            .font(AstralTypography.caption)
                            .foregroundStyle(AstralColors.muted)

                        if let published = fanfic.publishedAt {
                            Label(published.formatted(.dateTime.month(.abbreviated).year()), systemImage: "calendar")
                                .font(AstralTypography.caption)
                                .foregroundStyle(AstralColors.muted)
                        }

                        if let updated = fanfic.updatedAtSource {
                            Label(updated.formatted(.dateTime.month(.abbreviated).day()), systemImage: "arrow.clockwise")
                                .font(AstralTypography.caption)
                                .foregroundStyle(AstralColors.muted)
                        }
                    }
                }
            }

            // Progress — circular + text like comic cards
            if fanfic.totalChapters > 0 && fanfic.lastReadChapterNumber > 0 {
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .stroke(AstralColors.muted.opacity(0.2), lineWidth: 2.5)
                        Circle()
                            .trim(from: 0, to: progressPercent)
                            .stroke(AstralColors.gold, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .rotationEffect(.degrees(-135))
                    }
                    .frame(width: 18, height: 18)

                    Text("\(fanfic.lastReadChapterNumber)/\(fanfic.totalChapters) chapters")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AstralColors.body)
                }
            }
        }
        .padding(12)
        .astralCard()
    }
}

#Preview("Row - Ongoing + Favourite + Badge") {
    FanficRowView(fanfic: PreviewMocks.fanfic1)
        .padding()
        .background(AstralColors.background)
        .modelContainer(.previewContainer(fanfics: [PreviewMocks.fanfic1]))
}
