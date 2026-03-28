import SwiftUI
import SwiftData
import Core
import DesignSystem

struct ComicDetailView: View {
    let comic: LocalComic

    @Environment(\.modelContext) private var modelContext
    @Environment(\.comicNavigation) private var comicNavigation
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

    private var decodedTags: [[String: String]] {
        guard let json = comic.tagsJSON, let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: String]]
        else { return [] }
        return arr
    }

    private var decodedAuthors: [[String: String]] {
        guard let json = comic.authorsJSON, let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: String]]
        else { return [] }
        return arr
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // MARK: Hero thumbnail
                ZStack(alignment: .bottomLeading) {
                    if let path = comic.thumbnailPath, let url = thumbnailURL(path) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            default:
                                Rectangle()
                                    .fill(AstralColors.elevated)
                                    .overlay {
                                        Image(systemName: "book.fill")
                                            .font(.system(size: 48))
                                            .foregroundStyle(AstralColors.muted)
                                    }
                            }
                        }
                    } else {
                        Rectangle()
                            .fill(AstralColors.elevated)
                            .overlay {
                                Image(systemName: "book.fill")
                                    .font(.system(size: 48))
                                    .foregroundStyle(AstralColors.muted)
                            }
                    }

                    // Title overlay with gradient
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 120)
                    .frame(maxHeight: .infinity, alignment: .bottom)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(comic.title)
                            .font(AstralTypography.title)
                            .foregroundStyle(AstralColors.white)
                            .lineLimit(3)

                        HStack(spacing: 8) {
                            StatusBadge(comic.sourceKey)
                            StatusBadge(comic.status)
                            if comic.totalChapters > 0 {
                                StatusBadge("\(comic.totalChapters) ch", color: AstralColors.muted)
                            }
                        }
                    }
                    .padding(16)
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(3/4, contentMode: .fit)
                .clipped()

                // MARK: Metadata section
                VStack(alignment: .leading, spacing: 12) {
                    if let desc = comic.comicDescription, !desc.isEmpty {
                        Text(desc)
                            .font(AstralTypography.caption)
                            .foregroundStyle(AstralColors.body)
                            .lineLimit(6)
                    }

                    if let category = comic.category {
                        HStack(spacing: 6) {
                            Text("Category")
                                .font(AstralTypography.caption)
                                .foregroundStyle(AstralColors.muted)
                            Button { comicNavigation?.searchFor(category) } label: {
                                StatusBadge(category)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !decodedAuthors.isEmpty {
                        HStack(spacing: 6) {
                            Text("Authors")
                                .font(AstralTypography.caption)
                                .foregroundStyle(AstralColors.muted)
                            ForEach(decodedAuthors, id: \.self) { author in
                                if let name = author["name"] {
                                    Button { comicNavigation?.searchFor(name) } label: {
                                        StatusBadge(name, color: AstralColors.gold)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    if !decodedTags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(decodedTags, id: \.self) { tag in
                                    if let name = tag["name"] {
                                        Button { comicNavigation?.searchFor(name) } label: {
                                            StatusBadge(name, color: AstralColors.body)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)

                // MARK: Continue Reading button
                if !chapters.isEmpty {
                    ContinueReadingButton(
                        chapters: Array(chapters),
                        lastReadChapterNumber: comic.lastReadChapterNumber,
                        destination: { chapter in
                            ComicReaderView(comic: comic, chapters: chapters, startingAt: chapter)
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
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
                                    isRead: chapter.chapterNumber < Double(comic.lastReadChapterNumber),
                                    isBookmarked: bookmarks.contains { $0.chapterNumber == chapter.chapterNumber }
                                )
                            }
                            .buttonStyle(.plain)
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
        .navigationBarTitleDisplayMode(.inline)
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
    let isRead: Bool
    let isBookmarked: Bool

    private var textColor: Color {
        isRead ? AstralColors.muted : AstralColors.white
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Ch. \(chapter.chapterNumber, specifier: chapter.chapterNumber.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f")")
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

private struct ContinueReadingButton<Destination: View>: View {
    let chapters: [LocalComicChapter]
    let lastReadChapterNumber: Int
    let destination: (LocalComicChapter) -> Destination

    private enum ReadingState {
        case start(LocalComicChapter)
        case continueReading(LocalComicChapter)
        case readAgain(LocalComicChapter)
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
                destination(targetChapter(for: state))
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
            .buttonStyle(.plain)
        }
    }

    private func targetChapter(for state: ReadingState) -> LocalComicChapter {
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
