import SwiftUI
import SwiftData
import Core
import DesignSystem

struct FanficLibraryView: View {
    @Binding var searchText: String
    var filterFavourites: Bool

    @State private var viewModel = FanficLibraryViewModel()
    @Environment(\.modelContext) private var modelContext

    @Query(
        filter: #Predicate<LocalFanfic> { $0.completionStatus != "deleted" },
        sort: \LocalFanfic.addedAt,
        order: .reverse
    )
    private var allFanfics: [LocalFanfic]

    @State private var showFilter = false
    @State private var sortOption: FanficSortOption = .dateAdded

    private var inProgressFanfics: [LocalFanfic] {
        allFanfics
            .filter { $0.progressPercent > 0 && $0.progressPercent < 1.0 }
            .sorted { ($0.lastReadAt ?? $0.addedAt) > ($1.lastReadAt ?? $1.addedAt) }
            .prefix(5)
            .map { $0 }
    }

    private var filteredFanfics: [LocalFanfic] {
        var result = filterFavourites
            ? allFanfics.filter { $0.isFavorite }
            : allFanfics

        if !searchText.isEmpty {
            result = result.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }
        switch sortOption {
        case .dateAdded:
            return result.sorted { $0.addedAt > $1.addedAt }
        case .wordCount:
            return result.sorted { ($0.wordCount ?? 0) > ($1.wordCount ?? 0) }
        case .title:
            return result.sorted { $0.title < $1.title }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !filterFavourites && !inProgressFanfics.isEmpty && searchText.isEmpty {
                    FanficContinueReadingStrip(fanfics: inProgressFanfics)
                        .padding(.top, 8)
                }

                if filteredFanfics.isEmpty {
                    EmptyStateView(
                        icon: filterFavourites ? "heart" : "scroll",
                        title: filterFavourites ? "No Favourites Yet" : "No Fan Fiction Yet",
                        message: filterFavourites
                            ? "Tap the heart on any story to add it here."
                            : "Browse AO3 or FFNet and scrape your first story."
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
        .sheet(isPresented: $showFilter) {
            FanficFilterView()
                .presentationDetents([.medium, .large])
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showFilter = true
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundStyle(AstralColors.body)
                }
                .buttonStyle(PressButtonStyle(scale: 0.88))
            }
        }
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
                        NavigationLink {
                            FanficDetailView(fanfic: fanfic)
                        } label: {
                            FanficContinueCard(fanfic: fanfic)
                        }
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

private struct FanficContinueCard: View {
    let fanfic: LocalFanfic

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(AstralColors.elevated)
                Image(systemName: "scroll")
                    .foregroundStyle(AstralColors.muted)
            }
            .frame(width: 100, height: 70)

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

// MARK: - Sort Option

enum FanficSortOption: String, CaseIterable {
    case dateAdded = "Date Added"
    case wordCount = "Word Count"
    case title = "Title"
}

// MARK: - Row View

struct FanficRowView: View {
    let fanfic: LocalFanfic

    @Environment(\.modelContext) private var modelContext

    private var progressPercent: Double {
        guard fanfic.totalChapters > 0 else { return 0 }
        return Double(fanfic.lastReadChapterNumber) / Double(fanfic.totalChapters)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                // Thumbnail placeholder with new-chapter badge
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(AstralColors.elevated)
                        .frame(width: 50, height: 70)
                        .overlay {
                            Image(systemName: "scroll")
                                .foregroundStyle(AstralColors.muted)
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
                    HStack(spacing: 6) {
                        Text(fanfic.title)
                            .font(AstralTypography.bodyMedium)
                            .foregroundStyle(AstralColors.white)
                            .lineLimit(2)

                        Spacer()

                        // Favourite heart — bouncy toggle
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

                    if let summary = fanfic.summary {
                        Text(summary)
                            .font(AstralTypography.caption)
                            .foregroundStyle(AstralColors.muted)
                            .lineLimit(2)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            if let fandom = fanfic.fandom {
                                StatusBadge(fandom)
                            }
                            if let rating = fanfic.rating {
                                StatusBadge(rating)
                            }
                            StatusBadge(fanfic.completionStatus)
                            if let wc = fanfic.wordCount {
                                StatusBadge("\(wc / 1000)K words", color: AstralColors.muted)
                            }
                        }
                    }
                }
            }

            if fanfic.totalChapters > 0 {
                ProgressBarView(progress: progressPercent)
                Text("\(fanfic.lastReadChapterNumber)/\(fanfic.totalChapters) chapters")
                    .font(AstralTypography.caption)
                    .foregroundStyle(AstralColors.muted)
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
