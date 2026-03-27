import SwiftUI
import SwiftData
import Core
import DesignSystem

struct FanficLibraryView: View {
    @Binding var searchText: String

    @Query(
        filter: #Predicate<LocalFanfic> { $0.completionStatus != "deleted" },
        sort: \LocalFanfic.addedAt,
        order: .reverse
    )
    private var fanfics: [LocalFanfic]

    @State private var showFilter = false
    @State private var sortOption: FanficSortOption = .dateAdded

    var body: some View {
        ScrollView {
            if fanfics.isEmpty {
                EmptyStateView(
                    icon: "scroll",
                    title: "No Fan Fiction Yet",
                    message: "Browse AO3 or FFNet and scrape your first story."
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(filteredFanfics) { fanfic in
                        NavigationLink {
                            FanficDetailView(fanfic: fanfic)
                        } label: {
                            FanficRowView(fanfic: fanfic)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
        }
        .background(AstralColors.background)
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
            }
        }
    }

    private var filteredFanfics: [LocalFanfic] {
        var result = fanfics
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
}

// MARK: - Previews

#Preview("With Fanfics") {
    NavigationStack {
        FanficLibraryView(searchText: .constant(""))
            .modelContainer(.previewContainer(fanfics: PreviewMocks.sampleFanfics))
            .navigationTitle("Fan Fiction")
    }
}

#Preview("Filtered Search") {
    NavigationStack {
        FanficLibraryView(searchText: .constant("starlight"))
            .modelContainer(.previewContainer(fanfics: PreviewMocks.sampleFanfics))
            .navigationTitle("Fan Fiction")
    }
}

#Preview("Empty State") {
    NavigationStack {
        FanficLibraryView(searchText: .constant(""))
            .modelContainer(for: LocalFanfic.self, inMemory: true)
            .navigationTitle("Fan Fiction")
    }
}

#Preview("Fanfic Row - Ongoing") {
    FanficRowView(fanfic: PreviewMocks.fanfic1)
        .padding()
        .background(AstralColors.background)
}

#Preview("Fanfic Row - Complete") {
    FanficRowView(fanfic: PreviewMocks.fanfic2)
        .padding()
        .background(AstralColors.background)
}

#Preview("Fanfic Row - Abandoned") {
    FanficRowView(fanfic: PreviewMocks.fanfic3)
        .padding()
        .background(AstralColors.background)
}

enum FanficSortOption: String, CaseIterable {
    case dateAdded = "Date Added"
    case wordCount = "Word Count"
    case title = "Title"
}

struct FanficRowView: View {
    let fanfic: LocalFanfic

    private var progressPercent: Double {
        guard fanfic.totalChapters > 0 else { return 0 }
        return Double(fanfic.lastReadChapterNumber) / Double(fanfic.totalChapters)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                // Thumbnail placeholder
                RoundedRectangle(cornerRadius: 6)
                    .fill(AstralColors.elevated)
                    .frame(width: 50, height: 70)
                    .overlay {
                        Image(systemName: "scroll")
                            .foregroundStyle(AstralColors.muted)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(fanfic.title)
                        .font(AstralTypography.bodyMedium)
                        .foregroundStyle(AstralColors.white)
                        .lineLimit(2)

                    if let summary = fanfic.summary {
                        Text(summary)
                            .font(AstralTypography.caption)
                            .foregroundStyle(AstralColors.muted)
                            .lineLimit(2)
                    }

                    // Tag pills
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

            // Progress
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
