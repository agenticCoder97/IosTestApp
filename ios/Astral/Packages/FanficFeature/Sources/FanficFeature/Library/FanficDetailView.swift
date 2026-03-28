import SwiftUI
import SwiftData
import Core
import DesignSystem

struct FanficDetailView: View {
    let fanfic: LocalFanfic

    @Environment(\.modelContext) private var modelContext
    @Query private var chapters: [LocalFanficChapter]
    @Query private var bookmarks: [LocalBookmark]

    init(fanfic: LocalFanfic) {
        self.fanfic = fanfic
        let id = fanfic.id
        _chapters = Query(
            filter: #Predicate<LocalFanficChapter> { $0.fanficId == id },
            sort: \LocalFanficChapter.chapterNumber
        )
        _bookmarks = Query(
            filter: #Predicate<LocalBookmark> { $0.storyId == id && $0.contentType == "fanfic" },
            sort: \LocalBookmark.createdAt,
            order: .reverse
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

                // Continue Reading
                if !chapters.isEmpty {
                    FanficContinueReadingButton(
                        chapters: Array(chapters),
                        lastReadChapterNumber: fanfic.lastReadChapterNumber,
                        fanfic: fanfic
                    )
                    .padding(.horizontal, 16)
                }

                // Bookmarks
                if !bookmarks.isEmpty {
                    FanficBookmarksSection(bookmarks: bookmarks, onDelete: deleteBookmark)
                        .padding(.horizontal, 16)
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
                                    isLastRead: chapter.chapterNumber == Double(fanfic.lastReadChapterNumber),
                                    isRead: chapter.chapterNumber < Double(fanfic.lastReadChapterNumber),
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
                }
            }
            .padding(.bottom, 100)
        }
        .background(AstralColors.background)
        .navigationTitle(fanfic.title)
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            fanfic.seenTotalChapters = fanfic.totalChapters
            fanfic.lastReadAt = .now
            try? modelContext.save()
        }
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

    private func addBookmark(for chapter: LocalFanficChapter) {
        let bookmark = LocalBookmark(
            contentType: "fanfic",
            storyId: fanfic.id,
            chapterNumber: chapter.chapterNumber,
            scrollPercent: fanfic.scrollOffsetPercent
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

private struct FanficBookmarksSection: View {
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

            // Rows — push in from top on expand, scale/fade out on collapse
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(bookmarks) { bookmark in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                if let heading = bookmark.heading {
                                    Text(heading)
                                        .font(AstralTypography.captionMedium)
                                        .foregroundStyle(AstralColors.white)
                                        .lineLimit(1)
                                }
                                Text(bookmark.displayLabel)
                                    .font(AstralTypography.caption)
                                    .foregroundStyle(AstralColors.body)
                                    .lineLimit(1)
                                if let note = bookmark.note {
                                    Text("— \(note)")
                                        .font(AstralTypography.caption)
                                        .foregroundStyle(AstralColors.muted)
                                        .lineLimit(1)
                                }
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

private struct FanficChapterRow: View {
    let chapter: LocalFanficChapter
    let isLastRead: Bool
    let isRead: Bool
    let isBookmarked: Bool

    private var textColor: Color {
        isRead ? AstralColors.muted : AstralColors.white
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(chapterLabel)
                        .font(AstralTypography.bodyMedium)
                        .foregroundStyle(textColor)

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
        return num.truncatingRemainder(dividingBy: 1) == 0
            ? "Chapter \(Int(num))"
            : "Chapter \(num)"
    }

    @ViewBuilder
    private func statusIcon(for status: String) -> some View {
        switch status {
        case "scraped":
            if isRead {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(AstralColors.muted)
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(AstralColors.muted)
            }
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

// MARK: - Continue Reading Button

private struct FanficContinueReadingButton: View {
    let chapters: [LocalFanficChapter]
    let lastReadChapterNumber: Int
    let fanfic: LocalFanfic

    private enum ReadingState {
        case start(LocalFanficChapter)
        case continueReading(LocalFanficChapter)
        case readAgain(LocalFanficChapter)
    }

    private var readingState: ReadingState? {
        guard let firstChapter = chapters.first else { return nil }
        if lastReadChapterNumber == 0 {
            return .start(firstChapter)
        }
        if let next = chapters.first(where: { $0.chapterNumber > Double(lastReadChapterNumber) }) {
            return .continueReading(next)
        }
        return .readAgain(firstChapter)
    }

    var body: some View {
        if let state = readingState {
            NavigationLink {
                FanficReaderView(fanfic: fanfic, chapter: targetChapter(for: state))
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: iconName(for: state))
                    Text(label(for: state))
                        .font(AstralTypography.bodyMedium)
                }
                .foregroundStyle(labelColor(for: state))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(backgroundColor(for: state))
                .clipShape(Capsule())
            }
            .buttonStyle(PressButtonStyle(scale: 0.97))
        }
    }

    private func targetChapter(for state: ReadingState) -> LocalFanficChapter {
        switch state {
        case .start(let ch), .continueReading(let ch), .readAgain(let ch): return ch
        }
    }

    private func iconName(for state: ReadingState) -> String {
        switch state {
        case .start: return "book.fill"
        case .continueReading: return "arrow.right.circle.fill"
        case .readAgain: return "arrow.counterclockwise"
        }
    }

    private func label(for state: ReadingState) -> String {
        switch state {
        case .start(let ch):
            let num = ch.chapterNumber
            let formatted = num.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(num))" : "\(num)"
            return "Start Reading — Ch. \(formatted)"
        case .continueReading(let ch):
            let num = ch.chapterNumber
            let formatted = num.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(num))" : "\(num)"
            return "Continue — Ch. \(formatted)"
        case .readAgain:
            return "Read Again — Ch. 1"
        }
    }

    private func backgroundColor(for state: ReadingState) -> Color {
        switch state {
        case .start, .continueReading: return AstralColors.gold
        case .readAgain: return AstralColors.elevated
        }
    }

    private func labelColor(for state: ReadingState) -> Color {
        switch state {
        case .start, .continueReading: return .black
        case .readAgain: return AstralColors.muted
        }
    }
}

// MARK: - Previews

#Preview("With Chapters + Bookmarks") {
    let fanfic = PreviewMocks.fanfic1
    let chapters = PreviewMocks.fanfic1Chapters
    let bookmarks = PreviewMocks.sampleBookmarks.filter { $0.storyId == fanfic.id }
    return NavigationStack {
        FanficDetailView(fanfic: fanfic)
            .modelContainer(
                .previewContainer(fanfics: [fanfic], fanficChapters: chapters, bookmarks: bookmarks)
            )
    }
}

#Preview("No Chapters") {
    NavigationStack {
        FanficDetailView(fanfic: PreviewMocks.fanfic3)
            .modelContainer(.previewContainer(fanfics: [PreviewMocks.fanfic3]))
    }
}
