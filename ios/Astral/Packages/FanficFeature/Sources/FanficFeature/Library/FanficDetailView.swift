import SwiftUI
import SwiftData
import Core
import DesignSystem

struct FanficDetailView: View {
    let fanfic: LocalFanfic

    @Query private var chapters: [LocalFanficChapter]

    init(fanfic: LocalFanfic) {
        self.fanfic = fanfic
        let id = fanfic.id
        _chapters = Query(
            filter: #Predicate<LocalFanficChapter> { $0.fanficId == id },
            sort: \LocalFanficChapter.chapterNumber
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Metadata header
                if fanfic.summary != nil || fanfic.fandom != nil || fanfic.wordCount != nil {
                    metadataHeader
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }

                // Chapter list
                if chapters.isEmpty {
                    EmptyStateView(
                        icon: "scroll",
                        title: "No Chapters Yet",
                        message: "Scrape this story from the browser to load its chapters."
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(chapters) { chapter in
                            NavigationLink {
                                FanficReaderView(fanfic: fanfic, chapter: chapter)
                            } label: {
                                FanficChapterRow(
                                    chapter: chapter,
                                    isLastRead: chapter.chapterNumber == Double(fanfic.lastReadChapterNumber)
                                )
                            }
                            .buttonStyle(.plain)

                            Divider()
                                .background(AstralColors.elevated)
                                .padding(.leading, 16)
                        }
                    }
                }
            }
            .padding(.bottom, 100)
        }
        .background(AstralColors.background)
        .navigationTitle(fanfic.title)
        .navigationBarTitleDisplayMode(.large)
    }

    private var metadataHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let summary = fanfic.summary {
                Text(summary)
                    .font(AstralTypography.body)
                    .foregroundStyle(AstralColors.body)
                    .lineLimit(4)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
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
                    if fanfic.totalChapters > 0 {
                        StatusBadge("\(fanfic.totalChapters) ch", color: AstralColors.muted)
                    }
                }
            }
        }
        .padding(12)
        .astralCard()
    }
}

private struct FanficChapterRow: View {
    let chapter: LocalFanficChapter
    let isLastRead: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(chapterLabel)
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
                    if let wc = chapter.wordCount {
                        Text("\(wc / 1000)K words")
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

    private var chapterLabel: String {
        let num = chapter.chapterNumber
        if num.truncatingRemainder(dividingBy: 1) == 0 {
            return "Chapter \(Int(num))"
        }
        return "Chapter \(num)"
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
    let fanfic = PreviewMocks.fanfic1
    let chapters = PreviewMocks.fanfic1Chapters
    return NavigationStack {
        FanficDetailView(fanfic: fanfic)
            .modelContainer(
                .previewContainer(fanfics: [fanfic], fanficChapters: chapters)
            )
    }
}

#Preview("No Chapters") {
    NavigationStack {
        FanficDetailView(fanfic: PreviewMocks.fanfic3)
            .modelContainer(.previewContainer(fanfics: [PreviewMocks.fanfic3]))
    }
}
