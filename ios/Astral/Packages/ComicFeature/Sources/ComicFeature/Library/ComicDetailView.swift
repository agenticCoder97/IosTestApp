import SwiftUI
import SwiftData
import Core
import DesignSystem
import Networking

struct ComicDetailView: View {
    let comic: LocalComic

    @Environment(\.modelContext) private var modelContext
    @Environment(\.comicNavigation) private var comicNavigation
    @Query private var chapters: [LocalComicChapter]
    @Query private var bookmarks: [LocalBookmark]
    @State private var selectedChapter: LocalComicChapter?
    @State private var scrollOffset: CGFloat = 0
    @State private var isDownloading = false
    @State private var downloadProgress: (Int, Int) = (0, 0)
    @State private var activeTab: DetailTab = .chapters

    private enum DetailTab: String, CaseIterable {
        case chapters = "Chapters"
        case bookmarks = "Bookmarks"
    }

    // Height of the hero image — used to derive title opacity
    private let heroAspect: CGFloat = 3.0 / 4.0

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

    // MARK: - Decoded metadata

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

    private var formattedAddedDate: String {
        comic.addedAt.formatted(date: .abbreviated, time: .omitted)
    }

    // MARK: - Title overlay opacity

    /// Fades the title out as the user scrolls down past ~30 % of the hero height.
    /// scrollOffset is negative when scrolled down (coordinate space flips).
    private func titleOpacity(heroHeight: CGFloat) -> Double {
        // scrollOffset > 0 means pulled down (bounce) — keep full opacity.
        // scrollOffset < 0 means scrolled up — fade from 0 % scroll to 40 % of hero height.
        let fadeRange: CGFloat = heroHeight * 0.4
        guard scrollOffset < 0 else { return 1.0 }
        let progress = min(abs(scrollOffset) / fadeRange, 1.0)
        return Double(1.0 - progress)
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let heroHeight = geo.size.width / heroAspect
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // MARK: Hero + floating title
                    ZStack(alignment: .bottomLeading) {
                        heroThumbnail
                            .frame(maxWidth: .infinity)
                            .aspectRatio(heroAspect, contentMode: .fit)
                            .clipped()

                        // Full-width gradient at bottom of thumbnail
                        LinearGradient(
                            colors: [.clear, AstralColors.background],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: heroHeight * 0.55)
                        .frame(maxHeight: .infinity, alignment: .bottom)

                        // Floating title — fades on scroll
                        VStack(alignment: .leading, spacing: 6) {
                            Text(comic.title)
                                .font(AstralTypography.title)
                                .foregroundStyle(AstralColors.white)
                                .lineLimit(3)
                                .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 2)

                            HStack(spacing: 6) {
                                StatusBadge(comic.sourceKey.uppercased())
                                StatusBadge(comic.status)
                            }
                        }
                        .padding(16)
                        .opacity(titleOpacity(heroHeight: heroHeight))
                    }

                    // MARK: Metadata section
                    VStack(alignment: .leading, spacing: 16) {

                        // Authors row
                        if !decodedAuthors.isEmpty {
                            metadataRow(label: "Artists") {
                                ForEach(decodedAuthors, id: \.self) { author in
                                    if let name = author["name"] {
                                        Button {
                                            comicNavigation?.searchFor(name)
                                        } label: {
                                            StatusBadge(name, color: AstralColors.gold)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }

                        // Category row
                        if let category = comic.category, !category.isEmpty {
                            metadataRow(label: "Category") {
                                Button {
                                    comicNavigation?.searchFor(category)
                                } label: {
                                    StatusBadge(category, color: AstralColors.body)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // Tags — horizontal scroll
                        if !decodedTags.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Tags")
                                    .font(AstralTypography.captionMedium)
                                    .foregroundStyle(AstralColors.muted)
                                    .textCase(.uppercase)
                                    .tracking(0.8)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(decodedTags, id: \.self) { tag in
                                            if let name = tag["name"] {
                                                Button {
                                                    comicNavigation?.searchFor(name)
                                                } label: {
                                                    StatusBadge(name, color: AstralColors.body)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 1) // avoid clipping capsule shadows
                                }
                            }
                        }

                        Divider()
                            .background(AstralColors.elevated)

                        // Pages / Source / Added
                        HStack(spacing: 20) {
                            if comic.totalChapters > 0 {
                                infoCell(label: "Chapters", value: "\(comic.totalChapters)")
                            }
                            infoCell(label: "Source", value: comic.sourceKey.uppercased())
                            infoCell(label: "Added", value: formattedAddedDate)
                        }
                    }
                    .padding(16)

                    // MARK: Continue Reading button
                    if !chapters.isEmpty {
                        if let nextChapter = nextUnreadChapter {
                            Button {
                                AstralLogger.info("Continue button tapped: ch \(nextChapter.chapterNumber)", context: "ComicDetail")
                                selectedChapter = nextChapter
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: comic.lastReadChapterNumber == 0 ? "book.fill" : "arrow.right.circle.fill")
                                    Text(comic.lastReadChapterNumber == 0
                                         ? "Start Reading"
                                         : "Continue — Ch. \(Int(nextChapter.chapterNumber))")
                                        .font(AstralTypography.bodyMedium)
                                }
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(AstralColors.gold)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 4)
                        }
                    }

                    // MARK: Tab bar (Chapters / Bookmarks / Download)
                    HStack(spacing: 0) {
                        ForEach(DetailTab.allCases, id: \.self) { tab in
                            Button {
                                withAnimation(AstralAnimation.quick) { activeTab = tab }
                            } label: {
                                Text(tab.rawValue)
                                    .font(AstralTypography.captionMedium)
                                    .foregroundStyle(activeTab == tab ? AstralColors.gold : AstralColors.muted)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                        }

                        // Download icon button
                        Button {
                            handleDownloadTap()
                        } label: {
                            Group {
                                if isDownloading {
                                    ProgressView()
                                        .tint(AstralColors.gold)
                                        .scaleEffect(0.7)
                                } else {
                                    let savedCount = chapters.filter { $0.localPagesPath != nil }.count
                                    Image(systemName: savedCount == chapters.count && !chapters.isEmpty
                                          ? "arrow.down.circle.fill" : "arrow.down.to.line")
                                        .foregroundStyle(savedCount == chapters.count && !chapters.isEmpty
                                                         ? AstralColors.success : AstralColors.muted)
                                }
                            }
                            .frame(width: 44, height: 36)
                        }
                        .buttonStyle(.plain)
                    }
                    .background(AstralColors.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    // MARK: Tab content
                    switch activeTab {
                    case .chapters:
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
                                    Button {
                                        AstralLogger.info("Chapter tapped: \(chapter.chapterNumber) id=\(chapter.id)", context: "ComicDetail")
                                        selectedChapter = chapter
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

                    case .bookmarks:
                        if bookmarks.isEmpty {
                            EmptyStateView(
                                icon: "bookmark",
                                title: "No Bookmarks",
                                message: "Swipe a chapter or long-press a page to bookmark it."
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                        } else {
                            LazyVStack(spacing: 0) {
                                ForEach(bookmarks) { bookmark in
                                    Button {
                                        // Jump to bookmarked chapter/page
                                        if let chapter = chapters.first(where: { $0.chapterNumber == bookmark.chapterNumber }) {
                                            selectedChapter = chapter
                                        }
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: "bookmark.fill")
                                                .font(.caption)
                                                .foregroundStyle(AstralColors.gold)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(bookmark.displayLabel)
                                                    .font(AstralTypography.body)
                                                    .foregroundStyle(AstralColors.white)
                                                if let note = bookmark.note {
                                                    Text(note)
                                                        .font(AstralTypography.caption)
                                                        .foregroundStyle(AstralColors.muted)
                                                        .lineLimit(1)
                                                }
                                            }
                                            Spacer()
                                            Text(bookmark.createdAt.formatted(.dateTime.month(.abbreviated).day()))
                                                .font(AstralTypography.caption)
                                                .foregroundStyle(AstralColors.muted)
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                    }
                                    .buttonStyle(.plain)
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            deleteBookmark(bookmark)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
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
                // Track scroll offset via a background GeometryReader in the scroll coordinate space
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .preference(
                                key: ScrollOffsetKey.self,
                                value: proxy.frame(in: .named("scroll")).minY
                            )
                    }
                )
            }
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(ScrollOffsetKey.self) { value in
                scrollOffset = value
            }
        }
        .background(AstralColors.background)
        .navigationTitle(comic.title)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $selectedChapter) { chapter in
            ComicReaderView(comic: comic, chapters: chapters, startingAt: chapter)
        }
        .onAppear {
            comic.seenTotalChapters = comic.totalChapters
            comic.lastReadAt = .now
            try? modelContext.save()
        }
    }

    // MARK: - Hero thumbnail

    @ViewBuilder
    private var heroThumbnail: some View {
        if let path = comic.thumbnailPath, let url = thumbnailURL(path) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    thumbnailPlaceholder
                }
            }
        } else {
            thumbnailPlaceholder
        }
    }

    private var thumbnailPlaceholder: some View {
        Rectangle()
            .fill(AstralColors.elevated)
            .overlay {
                Image(systemName: "book.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(AstralColors.muted)
            }
    }

    // MARK: - Metadata helpers

    /// A labelled row with horizontally-wrapping badge chips inside a FlowLayout-style HStack.
    @ViewBuilder
    private func metadataRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(AstralTypography.captionMedium)
                .foregroundStyle(AstralColors.muted)
                .textCase(.uppercase)
                .tracking(0.8)

            HStack(spacing: 6) {
                content()
            }
        }
    }

    /// A small two-line stat cell (label above, value below).
    private func infoCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(AstralTypography.captionMedium)
                .foregroundStyle(AstralColors.muted)
                .textCase(.uppercase)
                .tracking(0.8)
            Text(value)
                .font(AstralTypography.bodyMedium)
                .foregroundStyle(AstralColors.white)
        }
    }

    // MARK: - Private helpers

    private var nextUnreadChapter: LocalComicChapter? {
        if comic.lastReadChapterNumber == 0 { return chapters.first }
        return chapters.first(where: { $0.chapterNumber > Double(comic.lastReadChapterNumber) }) ?? chapters.first
    }

    private func thumbnailURL(_ path: String) -> URL? {
        if path.hasPrefix("http") { return URL(string: path) }
        return URL(string: AppConfig.staticBaseURL + path)
    }

    private func handleDownloadTap() {
        let savedCount = chapters.filter { $0.localPagesPath != nil }.count
        let allSaved = savedCount == chapters.count && !chapters.isEmpty
        if allSaved {
            ChapterDownloadService.shared.deleteAllChapters(
                comic: comic, chapters: chapters, modelContext: modelContext
            )
        } else {
            isDownloading = true
            Task {
                await ChapterDownloadService.shared.downloadAllChapters(
                    comic: comic, chapters: chapters,
                    modelContext: modelContext
                ) { done, total in
                    downloadProgress = (done, total)
                }
                isDownloading = false
            }
        }
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

// MARK: - Scroll offset preference key

private struct ScrollOffsetKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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
                    if chapter.localPagesPath != nil {
                        StatusBadge.savedToDevice()
                    } else if chapter.isDownloaded {
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
