import SwiftUI
import SwiftData
import Core
import DesignSystem
import Networking

struct FanficDetailView: View {
    let fanfic: LocalFanfic

    @Environment(\.modelContext) private var modelContext
    @Environment(\.fanficNavigation) private var fanficNavigation
    @Environment(\.dismiss) private var dismiss
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

    @State private var activeTab: FanficDetailTab = .chapters
    @State private var isDownloading = false
    @State private var downloadProgress: (Int, Int) = (0, 0)
    @State private var isRescraping = false
    @State private var selectedChapter: LocalFanficChapter?

    private enum FanficDetailTab: String, CaseIterable {
        case chapters = "Chapters"
        case bookmarks = "Bookmarks"
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
                        onSelect: { chapter in
                            selectedChapter = chapter
                        }
                    )
                    .padding(.horizontal, 16)
                }

                // MARK: Tab bar (Chapters / Bookmarks / Download)
                HStack(spacing: 0) {
                    ForEach(FanficDetailTab.allCases, id: \.self) { tab in
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

                    // Download to device icon
                    Button {
                        handleDownloadTap()
                    } label: {
                        Group {
                            if isDownloading {
                                ProgressView()
                                    .tint(AstralColors.gold)
                                    .scaleEffect(0.7)
                            } else {
                                let savedCount = chapters.filter { $0.localTextPath != nil }.count
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

                // MARK: Tab content
                switch activeTab {
                case .chapters:
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
                                Button {
                                    selectedChapter = chapter
                                } label: {
                                    FanficChapterRow(
                                        chapter: chapter,
                                        isLastRead: chapter.chapterNumber == Double(fanfic.lastReadChapterNumber),
                                        isRead: chapter.chapterNumber < Double(fanfic.lastReadChapterNumber),
                                        isBookmarked: bookmarks.contains { $0.chapterNumber == chapter.chapterNumber }
                                    )
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button {
                                        withAnimation(AstralAnimation.bouncy) {
                                            addBookmark(for: chapter)
                                        }
                                    } label: {
                                        Label("Bookmark", systemImage: "bookmark")
                                    }
                                }

                                Divider()
                                    .background(AstralColors.elevated)
                                    .padding(.leading, 16)
                            }
                        }
                    }

                case .bookmarks:
                    if bookmarks.isEmpty {
                        EmptyStateView(
                            icon: "bookmark",
                            title: "No Bookmarks",
                            message: "Swipe a chapter or long-press a paragraph to bookmark it."
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(bookmarks) { bookmark in
                                Button {
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
                                            if let heading = bookmark.heading {
                                                Text(heading)
                                                    .font(AstralTypography.caption)
                                                    .foregroundStyle(AstralColors.muted)
                                                    .lineLimit(1)
                                            }
                                            if let text = bookmark.selectedText, !text.isEmpty {
                                                Text(text)
                                                    .font(AstralTypography.caption)
                                                    .foregroundStyle(AstralColors.body)
                                                    .lineLimit(2)
                                                    .italic()
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
                                .contextMenu {
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
                    }
                }
            }
            .padding(.bottom, 100)
        }
        .background(AstralColors.background)
        .fullScreenCover(item: $selectedChapter) { chapter in
            FanficReaderView(fanfic: fanfic, chapters: Array(chapters), chapter: chapter)
        }
        .navigationTitle(fanfic.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    rescrape()
                } label: {
                    if isRescraping {
                        ProgressView()
                            .tint(AstralColors.gold)
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(AstralColors.gold)
                    }
                }
                .disabled(isRescraping)
            }
        }
        .onAppear {
            fanfic.seenTotalChapters = fanfic.totalChapters
            fanfic.lastReadAt = .now
            try? modelContext.save()
        }
        .task { await syncChapters() }
    }

    private func syncChapters() async {
        do {
            let response: FanficResponse = try await APIClient.shared.request(
                .fanficDetail(id: fanfic.id)
            )
            guard let dtoChapters = response.chapters else { return }
            let fid = fanfic.id
            let chapterIDs = Set(dtoChapters.map(\.id))
            let descriptor = FetchDescriptor<LocalFanficChapter>(
                predicate: #Predicate<LocalFanficChapter> { $0.fanficId == fid }
            )
            let existing = (try? modelContext.fetch(descriptor)) ?? []
            let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

            for old in existing where !chapterIDs.contains(old.id) {
                modelContext.delete(old)
            }
            for dto in dtoChapters {
                if let ch = existingByID[dto.id] {
                    ch.chapterNumber = dto.chapterNumber
                    ch.title = dto.title
                    ch.wordCount = dto.wordCount
                    ch.scrapeStatus = dto.scrapeStatus
                } else {
                    let ch = LocalFanficChapter(
                        id: dto.id, fanficId: fid,
                        chapterNumber: dto.chapterNumber, title: dto.title,
                        wordCount: dto.wordCount, scrapeStatus: dto.scrapeStatus
                    )
                    ch.fanfic = fanfic
                    modelContext.insert(ch)
                }
            }
            try? modelContext.save()
        } catch {
            AstralLogger.error("syncChapters failed: \(error)", context: "FanficDetail")
        }
    }

    private var metadataHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Author + source link
            HStack {
                if let authors = fanfic.authorsText, !authors.isEmpty {
                    Label(authors, systemImage: "person.fill")
                        .font(AstralTypography.bodyMedium)
                        .foregroundStyle(AstralColors.body)
                }
                Spacer()
                if let urlString = fanfic.sourceUrl, let url = URL(string: urlString) {
                    Link(destination: url) {
                        HStack(spacing: 4) {
                            Text(fanfic.sourceKey.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(0.5)
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 12))
                        }
                        .foregroundStyle(AstralColors.gold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AstralColors.gold.opacity(0.12))
                        .clipShape(Capsule())
                    }
                }
            }

            // Summary
            if let summary = fanfic.summary {
                Text(summary)
                    .font(AstralTypography.body)
                    .foregroundStyle(AstralColors.body)
                    .lineLimit(6)
            }

            // Status row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if let rating = fanfic.rating {
                        StatusBadge(rating, color: ratingColor(rating))
                    }
                    StatusBadge(fanfic.completionStatus, color: statusColor(fanfic.completionStatus))
                    if let wc = fanfic.wordCount {
                        StatusBadge("\(wc / 1000)K words", color: AstralColors.muted)
                    }
                    if fanfic.totalChapters > 0 {
                        StatusBadge("\(fanfic.totalChapters) ch", color: AstralColors.muted)
                    }
                }
            }

            // Stats row — unified labels across AO3 and FFNet
            if fanfic.hits != nil || fanfic.kudos != nil || fanfic.commentsCount != nil || fanfic.bookmarksCount != nil {
                HStack(spacing: 14) {
                    if let hits = fanfic.hits {
                        statPill(icon: "eye", value: formatStat(hits), label: "Views")
                    }
                    if let kudos = fanfic.kudos {
                        statPill(icon: "heart", value: formatStat(kudos), label: "Likes")
                    }
                    if let comments = fanfic.commentsCount {
                        statPill(icon: "bubble.left", value: formatStat(comments), label: "Comments")
                    }
                    if let bookmarks = fanfic.bookmarksCount {
                        statPill(icon: "bookmark", value: formatStat(bookmarks), label: "Saves")
                    }
                }
            }

            // Fandom tags
            if let fandom = fanfic.fandom, !fandom.isEmpty {
                tagRow("Fandom") {
                    ForEach(fandom.components(separatedBy: ", ").filter { !$0.isEmpty }, id: \.self) { f in
                        tappableTag(f, color: AstralColors.gold)
                    }
                }
            }

            // Relationship tags
            if let pairing = fanfic.pairing, !pairing.isEmpty {
                tagRow("Relationships") {
                    ForEach(pairing.components(separatedBy: ", ").filter { !$0.isEmpty }, id: \.self) { r in
                        tappableTag(r, color: Color(hex: 0x5C9DFF))
                    }
                }
            }

            // Character tags
            if let characters = fanfic.characters, !characters.isEmpty {
                tagRow("Characters") {
                    ForEach(characters.components(separatedBy: ", ").filter { !$0.isEmpty }, id: \.self) { c in
                        tappableTag(c, color: AstralColors.body)
                    }
                }
            }

            // Warnings
            if let warnings = fanfic.warnings, !warnings.isEmpty {
                tagRow("Warnings") {
                    ForEach(warnings.components(separatedBy: ", ").filter { !$0.isEmpty }, id: \.self) { w in
                        StatusBadge(w, color: AstralColors.error)
                    }
                }
            }

            // Freeform tags
            if let freeform = fanfic.freeformTags, !freeform.isEmpty {
                tagRow("Tags") {
                    ForEach(freeform.components(separatedBy: ", ").filter { !$0.isEmpty }, id: \.self) { tag in
                        tappableTag(tag, color: AstralColors.muted)
                    }
                }
            }

            // Dates
            HStack(spacing: 16) {
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
        .padding(12)
        .astralCard()
    }

    @ViewBuilder
    private func tagRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AstralColors.muted)
                .tracking(0.8)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) { content() }
            }
        }
    }

    private func tappableTag(_ text: String, color: Color) -> some View {
        Button {
            fanficNavigation?.searchFor(text)
            dismiss()
        } label: {
            StatusBadge(text, color: color)
        }
        .buttonStyle(.plain)
    }

    private func ratingColor(_ rating: String) -> Color {
        let r = rating.lowercased()
        if r.contains("general") || r == "g" { return AstralColors.success }
        if r.contains("teen") || r == "t" { return Color(hex: 0x5C9DFF) }
        if r.contains("mature") || r == "m" { return AstralColors.warning }
        if r.contains("explicit") || r == "e" { return AstralColors.error }
        return AstralColors.muted
    }

    private func statPill(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(value)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(AstralColors.body)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(AstralColors.muted)
        }
    }

    private func formatStat(_ value: Int) -> String {
        if value >= 1_000_000 { return "\(value / 1_000_000)M" }
        if value >= 1_000 { return "\(value / 1_000)K" }
        return "\(value)"
    }

    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "complete": AstralColors.success
        case "ongoing": AstralColors.gold
        case "abandoned": AstralColors.error
        default: AstralColors.muted
        }
    }

    private func handleDownloadTap() {
        guard !isDownloading else { return }

        let allComplete = !chapters.isEmpty && chapters.allSatisfy { $0.downloadStatus == .complete }
        if allComplete {
            FanficDownloadService.shared.deleteAllChapters(
                fanfic: fanfic,
                chapters: Array(chapters),
                modelContext: modelContext
            )
            return
        }

        isDownloading = true
        Task {
            await FanficDownloadService.shared.downloadAllChapters(
                fanfic: fanfic,
                chapters: Array(chapters),
                modelContext: modelContext,
                onProgress: { completed, total in
                    downloadProgress = (completed, total)
                }
            )
            isDownloading = false
        }
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

    private func rescrape() {
        isRescraping = true
        Task {
            let _: ScrapeJobResponse? = try? await APIClient.shared.request(
                .deltaUpdate(storyId: fanfic.id)
            )
            isRescraping = false
        }
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

            downloadStatusIcon(for: chapter)

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
    private func downloadStatusIcon(for chapter: LocalFanficChapter) -> some View {
        switch chapter.downloadStatus {
        case .complete:
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(AstralColors.success)
        case .downloading, .queued:
            ProgressView()
                .scaleEffect(0.6)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(AstralColors.error)
        case .none:
            EmptyView()
        }
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
    let onSelect: (LocalFanficChapter) -> Void

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
        // Resume the current chapter at saved scroll position (reader restores via scrollOffsetPercent)
        if let current = chapters.first(where: { Int($0.chapterNumber) == lastReadChapterNumber }) {
            return .continueReading(current)
        }
        if let next = chapters.first(where: { $0.chapterNumber > Double(lastReadChapterNumber) }) {
            return .continueReading(next)
        }
        return .readAgain(firstChapter)
    }

    var body: some View {
        if let state = readingState {
            Button {
                onSelect(targetChapter(for: state))
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
