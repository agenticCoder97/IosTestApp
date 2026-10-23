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
    @State private var downloadTask: Task<Void, Never>?
    @State private var isDownloading = false
    @State private var downloadProgress: (Int, Int) = (0, 0)
    @State private var isRescraping = false
    @State private var selectedBookmark: LocalBookmark?
    @State private var selectedChapter: LocalFanficChapter?
    @State private var showDeleteAlert = false

    private enum FanficDetailTab: String, CaseIterable {
        case chapters = "Chapters"
        case bookmarks = "Bookmarks"
    }

    var body: some View {
        let current = currentChapter
        let marks = bookmarkIndex
        let allSaved = !chapters.isEmpty && chapters.allSatisfy { $0.localTextPath != nil || $0.isDownloaded }
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if fanfic.sourceKey == "local" && !fanfic.isFullyDownloaded {
                    Text("This imported text is missing. Importing the original file in Add creates a separate story; restoring a library backup replaces your whole collection.")
                        .font(.footnote).foregroundStyle(AstralColors.warning).padding(.horizontal, 16)
                }
                if let current {
                    continueButton(current)
                        .accessibilityIdentifier(AccessibilityID.detailContinueReading)
                        .padding(.horizontal, 16)
                }

                // Metadata header
                if fanfic.summary != nil || fanfic.fandom != nil || fanfic.wordCount != nil {
                    DisclosureGroup("Story details") { metadataHeader }
                        .tint(AstralColors.gold)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }

                // MARK: Tab bar (Chapters / Bookmarks / Download)
                HStack(spacing: 0) {
                    ForEach(FanficDetailTab.allCases, id: \.self) { tab in
                        Button {
                            withAnimation(AstralAnimation.quick) { activeTab = tab }
                        } label: {
                            Text(tab == .bookmarks && !bookmarks.isEmpty ? "Bookmarks (\(bookmarks.count))" : tab.rawValue)
                                .font(AstralTypography.captionMedium)
                                .foregroundStyle(activeTab == tab ? AstralColors.gold : AstralColors.muted)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(activeTab == tab ? AstralColors.gold.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(activeTab == tab ? .isSelected : [])
                    }

                    if !["ao3", "ffnet"].contains(fanfic.sourceKey) {
                        Button("Download", systemImage: "arrow.down.to.line") { handleDownloadTap() }
                            .labelStyle(.iconOnly).frame(width: 44, height: 44)
                            .disabled(fanfic.sourceKey == "local" || isDownloading || fanfic.isFullyDownloaded)
                            .accessibilityLabel(fanfic.isFullyDownloaded ? "Saved on this device" : "Download chapters")
                    }

                }
                .padding(3)
                .background(AstralColors.elevated, in: RoundedRectangle(cornerRadius: 9))
                .padding(.horizontal, 16)

                // MARK: Tab content
                switch activeTab {
                case .chapters:
                    if chapters.isEmpty {
                        EmptyStateView(
                            icon: "scroll",
                            title: "No chapters yet",
                            message: "Open this story in Add and import it to load its chapters."
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
                                        isCurrent: chapter.id == current?.id && fanfic.lastReadAt != nil,
                                        showsSavedState: !allSaved,
                                        isBookmarked: marks.chapterIDs.contains(chapter.id) || marks.unanchoredNumbers.contains(chapter.chapterNumber)
                                    )
                                }
                                .accessibilityIdentifier(AccessibilityID.chapterRow(Int(chapter.chapterNumber)))
                                .buttonStyle(.plain)
                                .contextMenu {
                                    let isBookmarked = marks.chapterIDs.contains(chapter.id) || marks.unanchoredNumbers.contains(chapter.chapterNumber)
                                    Button(isBookmarked ? "Remove bookmark" : "Bookmark chapter", systemImage: isBookmarked ? "bookmark.slash" : "bookmark") {
                                        toggleBookmark(for: chapter)
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
                            title: "No bookmarks yet",
                            message: "Long-press a paragraph in the reader, or long-press a chapter here."
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(bookmarks) { bookmark in
                                Button {
                                    if let chapter = chapters.first(where: { $0.id == BookmarkAnchorStore.chapter(for: bookmark.id) }) ?? chapters.first(where: { $0.chapterNumber == bookmark.chapterNumber }) {
                                        selectedBookmark = bookmark
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
                                    .padding(.leading, 16)
                                    .padding(.trailing, 52)
                                    .padding(.vertical, 10)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .overlay(alignment: .trailing) {
                                    Button { deleteBookmark(bookmark) } label: {
                                        Image(systemName: "trash").font(.footnote).frame(width: 36, height: 36)
                                    }
                                    .foregroundStyle(AstralColors.muted)
                                    .padding(.trailing, 8)
                                    .accessibilityLabel("Delete bookmark")
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        deleteBookmark(bookmark)
                                    } label: {
                                        Label("Delete bookmark", systemImage: "trash")
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
        .fullScreenCover(item: $selectedChapter, onDismiss: { selectedBookmark = nil }) { chapter in
            FanficReaderView(fanfic: fanfic, chapters: Array(chapters), chapter: chapter, bookmark: selectedBookmark)
        }
        .navigationTitle(fanfic.title)
        .navigationBarTitleDisplayMode(.inline)
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
                .disabled(isRescraping || fanfic.sourceKey == "local")
                .accessibilityLabel(["ao3", "ffnet"].contains(fanfic.sourceKey) ? "Update from source" : "Refresh story")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        Label("Delete permanently", systemImage: "trash.slash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(AstralColors.gold)
                }
            }
        }
        .deletePermanentlyAlert(
            isPresented: $showDeleteAlert,
            storyTitle: fanfic.title,
            onConfirm: {
                let chaptersSnapshot = Array(chapters)
                dismiss()
                Task {
                    await StoryDeletionService.shared.permanentlyDelete(
                        fanfic: fanfic,
                        modelContext: modelContext,
                        deleteFiles: {
                            FanficDownloadService.shared.deleteAllChapters(
                                fanfic: fanfic,
                                chapters: chaptersSnapshot,
                                modelContext: modelContext
                            )
                        }
                    )
                }
            }
        )
        .onAppear {
            fanfic.seenTotalChapters = fanfic.totalChapters
            try? modelContext.save()
        }
        .task { await syncChapters() }
    }

    private func syncChapters() async {
        guard !["ao3", "ffnet"].contains(fanfic.sourceKey), AppConfig.companionEnabled else { return }
        do {
            let response: FanficResponse = try await APIClient.shared.request(
                .fanficDetail(id: fanfic.id)
            )
            guard let dtoChapters = response.chapters else { return }
            let fid = fanfic.id
            let descriptor = FetchDescriptor<LocalFanficChapter>(
                predicate: #Predicate<LocalFanficChapter> { $0.fanficId == fid }
            )
            let existing = (try? modelContext.fetch(descriptor)) ?? []
            let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

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

    // MARK: - Header and continue

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            StoryThumbnail(path: fanfic.thumbnailPath, title: fanfic.title, icon: "scroll.fill", width: 84, height: 112, baseURL: AppConfig.staticBaseURL)
            VStack(alignment: .leading, spacing: 6) {
                Text(fanfic.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AstralColors.white)
                    .lineLimit(3)
                if let authors = fanfic.authorsText, !authors.isEmpty {
                    Text("by \(authors)")
                        .font(.subheadline)
                        .foregroundStyle(AstralColors.body)
                        .lineLimit(1)
                }
                Text([SourceLabel.name(for: fanfic.sourceKey), fanfic.rating, fanfic.completionStatus.capitalized].compactMap { $0 }.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(AstralColors.muted)
                    .lineLimit(2)
                Text(["\(chapters.count) chapter\(chapters.count == 1 ? "" : "s")", fanfic.wordCount.map { "\($0.formatted()) words" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(AstralColors.muted)
                if let warnings = fanfic.warnings, !warnings.isEmpty {
                    // Source warnings stay visible before reading. AO3's "no
                    // warnings" values are information, not a caution.
                    let real = warnings.components(separatedBy: ", ").filter {
                        !["No Archive Warnings Apply", "Creator Chose Not To Use Archive Warnings"].contains($0)
                    }
                    Label(real.isEmpty ? warnings : real.joined(separator: ", "),
                          systemImage: real.isEmpty ? "info.circle" : "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(real.isEmpty ? AstralColors.muted : AstralColors.warning)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func continueButton(_ chapter: LocalFanficChapter) -> some View {
        let isFirstOpen = fanfic.lastReadAt == nil
        let number = chapter.chapterNumber.formatted(.number.grouping(.never).precision(.fractionLength(0...1)))
        let fraction = ReadingPositionStore.position(story: fanfic.id, chapter: chapter.id)?.fraction ?? 0
        let percent = Int((fraction * 100).rounded())
        return Button {
            selectedChapter = chapter
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isFirstOpen ? "book.fill" : "arrow.right.circle.fill")
                Text(isFirstOpen ? "Start reading — Ch. \(number)"
                                 : "Continue — Ch. \(number)" + (percent > 0 && percent < 100 ? " · \(percent)%" : ""))
                    .font(AstralTypography.bodyMedium)
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AstralColors.gold, in: Capsule())
        }
        .buttonStyle(PressButtonStyle(scale: 0.98))
    }

    /// The chapter the reader would open: the saved position, else the legacy
    /// chapter number, else the first chapter.
    private var currentChapter: LocalFanficChapter? {
        if let saved = ReadingPositionStore.position(story: fanfic.id), let chapter = chapters.first(where: { $0.id == saved.chapterID }) { return chapter }
        if let number = fanfic.lastReadChapterNumber, number > 0 {
            return chapters.first { $0.chapterNumber == number } ?? chapters.first { $0.chapterNumber > number } ?? chapters.first
        }
        return chapters.first
    }

    /// Bookmarked chapters, resolved once per update rather than per row.
    private var bookmarkIndex: (chapterIDs: Set<UUID>, unanchoredNumbers: Set<Double>) {
        var ids = Set<UUID>(), numbers = Set<Double>()
        for bookmark in bookmarks {
            if let id = BookmarkAnchorStore.chapter(for: bookmark.id) { ids.insert(id) } else { numbers.insert(bookmark.chapterNumber) }
        }
        return (ids, numbers)
    }

    private func toggleBookmark(for chapter: LocalFanficChapter) {
        let existing = bookmarks.first {
            BookmarkAnchorStore.chapter(for: $0.id).map { $0 == chapter.id } ?? ($0.chapterNumber == chapter.chapterNumber)
        }
        if let existing { deleteBookmark(existing) }
        else { addBookmark(for: chapter); Haptics.play(.bookmark) }
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
                FlowLayout(spacing: 14) {
                    if let hits = fanfic.hits {
                        statPill(icon: "eye", value: formatStat(hits), label: "Views")
                    }
                    if let kudos = fanfic.kudos {
                        statPill(icon: "heart", value: formatStat(kudos), label: "Kudos")
                    }
                    if let comments = fanfic.commentsCount {
                        statPill(icon: "bubble.left", value: formatStat(comments), label: "Comments")
                    }
                    if let bookmarks = fanfic.bookmarksCount {
                        statPill(icon: "bookmark", value: formatStat(bookmarks), label: "Source bookmarks")
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
            FlowLayout(spacing: 8) { content() }
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
        guard fanfic.sourceKey != "local" else { return }
        guard !isDownloading else { return }

        if ["ao3", "ffnet"].contains(fanfic.sourceKey) {
            // The imported files are the only local copy. Updating them is
            // an explicit reimport; never toggle the saved copy off here.
            openAO3Import()
            return
        }

        let allComplete = !chapters.isEmpty && chapters.allSatisfy { $0.downloadStatus == .complete }
        guard !allComplete else { return }

        isDownloading = true
        downloadTask = Task {
            await FanficDownloadService.shared.downloadAllChapters(
                fanfic: fanfic,
                chapters: Array(chapters),
                modelContext: modelContext,
                onCancel: { downloadTask?.cancel() },
                onProgress: { completed, total in
                    downloadProgress = (completed, total)
                }
            )
            isDownloading = false
        }
    }

    private func addBookmark(for chapter: LocalFanficChapter) {
        // A chapter bookmark opens the chapter at its start.
        let bookmark = LocalBookmark(
            contentType: "fanfic",
            storyId: fanfic.id,
            chapterNumber: chapter.chapterNumber,
            heading: chapter.title
        )
        modelContext.insert(bookmark)
        BookmarkAnchorStore.save(bookmark: bookmark.id, chapter: chapter.id)
        try? modelContext.save()
    }

    private func rescrape() {
        if ["ao3", "ffnet"].contains(fanfic.sourceKey) {
            openAO3Import()
            return
        }
        isRescraping = true
        Task {
            let _: ScrapeJobResponse? = try? await APIClient.shared.request(
                .deltaUpdate(storyId: fanfic.id)
            )
            isRescraping = false
        }
    }

    private func openAO3Import() {
        guard let url = fanfic.sourceUrl.flatMap(URL.init(string:)),
              (AO3ImportService.workURL(from: url) ?? AO3ImportService.ffnetURL(from: url)) != nil else { return }
        fanficNavigation?.ao3WorkURL = url
        dismiss()
        fanficNavigation?.activeSection = .browse
    }

    private func deleteBookmark(_ bookmark: LocalBookmark) {
        BookmarkUndoService.shared.delete(bookmark, context: modelContext)
    }
}

// MARK: - Chapter Row

private struct FanficChapterRow: View {
    let chapter: LocalFanficChapter
    let isCurrent: Bool
    /// Only meaningful when some chapters are saved and others are not.
    let showsSavedState: Bool
    let isBookmarked: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Ch. \(chapter.chapterNumber.formatted(.number.grouping(.never).precision(.fractionLength(0...1))))")
                        .font(AstralTypography.bodyMedium)
                        .foregroundStyle(isCurrent ? AstralColors.gold : AstralColors.white)
                    if let title = chapter.title, !title.isEmpty {
                        Text(title)
                            .font(AstralTypography.body)
                            .foregroundStyle(AstralColors.body)
                            .lineLimit(1)
                    }
                }
                if let words = chapter.wordCount, words > 0 {
                    Text("\(words.formatted()) words · \(max(1, words / 238)) min")
                        .font(AstralTypography.caption)
                        .foregroundStyle(AstralColors.muted)
                }
            }
            Spacer(minLength: 8)
            if isCurrent {
                Text("Reading")
                    .font(AstralTypography.caption)
                    .foregroundStyle(AstralColors.gold)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(AstralColors.gold.opacity(0.15), in: Capsule())
            }
            if isBookmarked {
                Image(systemName: "bookmark.fill")
                    .font(.caption)
                    .foregroundStyle(AstralColors.gold)
                    .accessibilityLabel("Bookmarked")
            }
            if showsSavedState {
                savedStateIcon
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(AstralColors.muted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isCurrent ? AstralColors.gold.opacity(0.05) : .clear)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var savedStateIcon: some View {
        if chapter.localTextPath != nil || chapter.isDownloaded {
            Image(systemName: "arrow.down.circle.fill")
                .font(.caption)
                .foregroundStyle(AstralColors.success)
                .accessibilityLabel("Saved on this device")
        } else {
            switch chapter.downloadStatus {
            case .downloading, .queued:
                ProgressView().controlSize(.mini)
            case .failed:
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(AstralColors.error)
                    .accessibilityLabel("Couldn't save")
            case .complete, .none:
                Image(systemName: "icloud")
                    .font(.caption)
                    .foregroundStyle(AstralColors.muted)
                    .accessibilityLabel("Not saved")
            }
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
