import SwiftUI
import SwiftData
import Core
import DesignSystem
import Networking

struct ComicDetailView: View {
    let comic: LocalComic

    @Environment(\.modelContext) private var modelContext
    @Environment(\.comicNavigation) private var comicNavigation
    @Environment(\.dismiss) private var dismiss
    @Query private var storedChapters: [LocalComicChapter]
    @Query private var bookmarks: [LocalBookmark]
    @State private var selectedBookmark: LocalBookmark?
    @State private var selectedChapter: LocalComicChapter?
    @State private var downloadTask: Task<Void, Never>?
    @State private var downloadProgress: (done: Int, total: Int)?
    @State private var downloadError: String?
    @State private var activeTab: DetailTab = .chapters
    @State private var showDeleteAlert = false
    @AppStorage("comicDetail.newestFirst") private var newestFirst = false

    private enum DetailTab: String, CaseIterable {
        case chapters = "Chapters"
        case bookmarks = "Bookmarks"
    }

    init(comic: LocalComic) {
        self.comic = comic
        let id = comic.id
        _storedChapters = Query(
            filter: #Predicate<LocalComicChapter> { $0.comicId == id },
            sort: \LocalComicChapter.chapterNumber
        )
        _bookmarks = Query(
            filter: #Predicate<LocalBookmark> { $0.storyId == id && $0.contentType == "comic" },
            sort: \LocalBookmark.createdAt,
            order: .reverse
        )
    }

    // MARK: - Body

    var body: some View {
        // Reading order is computed once per update; it reads a stored order
        // map and sorts every chapter, which is too costly to repeat per row.
        let ordered = ChapterOrdering.comics(storedChapters)
        let current = currentChapter(in: ordered)
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(ordered)
                    if let current { continueButton(current, isFirstOpen: comic.lastReadAt == nil) }
                    storyDetails
                    tabBar
                    switch activeTab {
                    case .chapters: chapterSection(ordered, current: current, proxy: proxy)
                    case .bookmarks: bookmarkSection(ordered)
                    }
                }
                .padding(.bottom, 100)
            }
        }
        .background(AstralColors.background)
        .navigationTitle(comic.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { moreMenu }
        }
        .deletePermanentlyAlert(
            isPresented: $showDeleteAlert,
            storyTitle: comic.title,
            onConfirm: {
                let chaptersSnapshot = Array(storedChapters)
                dismiss()
                Task {
                    await StoryDeletionService.shared.permanentlyDelete(
                        comic: comic,
                        modelContext: modelContext,
                        deleteFiles: {
                            ChapterDownloadService.shared.deleteAllChapters(
                                comic: comic,
                                chapters: chaptersSnapshot,
                                modelContext: modelContext
                            )
                        }
                    )
                }
            }
        )
        .alert("Couldn't save chapters", isPresented: Binding(get: { downloadError != nil }, set: { if !$0 { downloadError = nil } })) {
            Button("OK") { downloadError = nil }
        } message: { Text(downloadError ?? "") }
        .fullScreenCover(item: $selectedChapter, onDismiss: { selectedBookmark = nil }) { chapter in
            ComicReaderView(comic: comic, chapters: ChapterOrdering.comics(storedChapters), startingAt: chapter, bookmark: selectedBookmark)
        }
        .onAppear {
            // Only write when something changed; a save on every appearance re-renders @Query observers.
            guard comic.seenTotalChapters != comic.totalChapters else { return }
            comic.seenTotalChapters = comic.totalChapters
            try? modelContext.save()
        }
        .task { await syncChapters() }
    }

    // MARK: - Header

    private func header(_ ordered: [LocalComicChapter]) -> some View {
        let saved = ordered.filter { $0.localPagesPath != nil }.count
        return HStack(alignment: .top, spacing: 16) {
            StoryThumbnail(path: comic.thumbnailPath, title: comic.title, width: 84, height: 112, baseURL: AppConfig.staticBaseURL)
            VStack(alignment: .leading, spacing: 6) {
                Text(comic.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AstralColors.white)
                    .lineLimit(3)
                Text([SourceLabel.name(for: comic.sourceKey), statusLabel].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(AstralColors.body)
                Text("\(ordered.count) chapters" + (saved > 0 ? " · \(saved) saved" : ""))
                    .font(.footnote)
                    .foregroundStyle(AstralColors.muted)
                if comic.sourceKey == "local" && !comic.isFullyDownloaded {
                    Text("These imported pages are missing. Importing the original folder in Add creates a separate story; restoring a library backup replaces your whole collection.")
                        .font(.caption)
                        .foregroundStyle(AstralColors.warning)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private var statusLabel: String? {
        switch comic.completionStatus {
        case "complete": "Completed"
        case "ongoing": "Ongoing"
        default: nil
        }
    }

    private func continueButton(_ chapter: LocalComicChapter, isFirstOpen: Bool) -> some View {
        let label = ComicChapterLabel(chapter)
        let position = ReadingPositionStore.position(story: comic.id, chapter: chapter.id)
        let page = position.map { $0.page + 1 }
        return Button {
            selectedChapter = chapter
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isFirstOpen ? "book.fill" : "arrow.right.circle.fill")
                Text(isFirstOpen
                     ? "Start reading — Ch. \(label.number)"
                     : "Continue — Ch. \(label.number)" + (page.map { $0 > 1 ? ", page \($0)" : "" } ?? ""))
                    .font(AstralTypography.bodyMedium)
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AstralColors.gold, in: Capsule())
        }
        .buttonStyle(PressButtonStyle(scale: 0.98))
        .accessibilityIdentifier(AccessibilityID.detailContinueReading)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 4)
    }

    // MARK: - Story details

    private var decodedTags: [[String: String]] { decodeJSON(comic.tagsJSON) }
    private var decodedAuthors: [[String: String]] { decodeJSON(comic.authorsJSON) }

    private func decodeJSON(_ json: String?) -> [[String: String]] {
        guard let json, let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else { return [] }
        return array
    }

    private var storyDetails: some View {
        DisclosureGroup("Story details") {
            VStack(alignment: .leading, spacing: 16) {
                if let description = comic.comicDescription, !description.isEmpty {
                    Text(description).font(.body).foregroundStyle(AstralColors.body).textSelection(.enabled)
                }
                if !decodedAuthors.isEmpty {
                    metadataRow(label: "Artists") {
                        ForEach(decodedAuthors, id: \.self) { author in
                            if let name = author["name"] { searchBadge(name, color: AstralColors.gold) }
                        }
                    }
                }
                if let category = comic.category, !category.isEmpty {
                    metadataRow(label: "Category") { searchBadge(category, color: AstralColors.body) }
                }
                if !decodedTags.isEmpty {
                    metadataRow(label: "Tags") {
                        ForEach(decodedTags, id: \.self) { tag in
                            if let name = tag["name"] { searchBadge(name, color: AstralColors.body) }
                        }
                    }
                }
                Divider().background(AstralColors.elevated)
                HStack(spacing: 20) {
                    infoCell(label: "Chapters", value: "\(storedChapters.count)")
                    infoCell(label: "Source", value: SourceLabel.name(for: comic.sourceKey))
                    infoCell(label: "Added", value: comic.addedAt.formatted(date: .abbreviated, time: .omitted))
                }
            }
            .padding(.vertical, 12)
        }
        .tint(AstralColors.gold)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func searchBadge(_ text: String, color: Color) -> some View {
        Button { comicNavigation?.searchFor(text); dismiss() } label: { StatusBadge(text, color: color) }
            .buttonStyle(.plain)
    }

    private func metadataRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(AstralTypography.captionMedium)
                .foregroundStyle(AstralColors.muted)
                .textCase(.uppercase)
                .tracking(0.8)
            FlowLayout(spacing: 8) { content() }
        }
    }

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

    // MARK: - Tabs

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(DetailTab.allCases, id: \.self) { tab in
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
        }
        .padding(3)
        .background(AstralColors.elevated, in: RoundedRectangle(cornerRadius: 9))
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    // MARK: - Chapters

    @ViewBuilder
    private func chapterSection(_ ordered: [LocalComicChapter], current: LocalComicChapter?, proxy: ScrollViewProxy) -> some View {
        if ordered.isEmpty {
            EmptyStateView(
                icon: "book.closed",
                title: "No chapters yet",
                message: "Update this comic from its source to load its chapters."
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
        } else {
            let listed = newestFirst ? Array(ordered.reversed()) : ordered
            let marks = bookmarkIndex
            VStack(spacing: 0) {
                chapterToolbar(ordered, current: current, proxy: proxy)
                LazyVStack(spacing: 0) {
                    ForEach(listed) { chapter in
                        let isBookmarked = marks.chapterIDs.contains(chapter.id) || marks.unanchoredNumbers.contains(chapter.chapterNumber)
                        Button {
                            selectedChapter = chapter
                        } label: {
                            ComicChapterRow(chapter: chapter, isCurrent: chapter.id == current?.id && comic.lastReadAt != nil, isBookmarked: isBookmarked)
                        }
                        .buttonStyle(.plain)
                        .id(chapter.id)
                        .accessibilityIdentifier(AccessibilityID.chapterRow(Int(chapter.chapterNumber)))
                        .contextMenu { chapterMenu(chapter, isBookmarked: isBookmarked) }

                        Divider()
                            .background(AstralColors.elevated)
                            .padding(.leading, 16)
                    }
                }
            }
        }
    }

    /// Count, progress of an active save, and the list controls.
    private func chapterToolbar(_ ordered: [LocalComicChapter], current: LocalComicChapter?, proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 4) {
            if let progress = downloadProgress {
                ProgressView().controlSize(.small).tint(AstralColors.gold)
                Text("Saving \(min(progress.done + 1, progress.total)) of \(progress.total)…")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AstralColors.body)
                Button("Cancel") { downloadTask?.cancel() }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AstralColors.gold)
                    .padding(.leading, 4)
            } else {
                Text("\(ordered.count) chapters")
                    .font(.footnote)
                    .foregroundStyle(AstralColors.muted)
            }
            Spacer()
            if let current, comic.lastReadAt != nil, ordered.count > 12 {
                Button {
                    withAnimation(AstralAnimation.smooth) { proxy.scrollTo(current.id, anchor: .center) }
                } label: {
                    Image(systemName: "scope").frame(width: 36, height: 36)
                }
                .accessibilityLabel("Jump to chapter \(ComicChapterLabel(current).number)")
            }
            Button {
                newestFirst.toggle()
            } label: {
                Image(systemName: "arrow.up.arrow.down").frame(width: 36, height: 36)
            }
            .accessibilityLabel(newestFirst ? "Showing newest first" : "Showing oldest first")
            .accessibilityHint("Reverses the chapter order")
            if comic.sourceKey != "local" { saveMenu(ordered, current: current) }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(AstralColors.body)
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
    }

    private func saveMenu(_ ordered: [LocalComicChapter], current: LocalComicChapter?) -> some View {
        let unsaved = ordered.filter { $0.localPagesPath == nil && $0.scrapeStatus == "scraped" }
        let start = current.flatMap { c in ordered.firstIndex { $0.id == c.id } } ?? 0
        // "Next" begins at the chapter being read, in reading order.
        let upcoming = ordered[start...].filter { $0.localPagesPath == nil && $0.scrapeStatus == "scraped" }
        return Menu {
            if downloadProgress != nil {
                Button("Cancel saving", systemImage: "xmark", role: .destructive) { downloadTask?.cancel() }
            } else {
                // Only offer a "next N" batch when it is smaller than "all".
                if upcoming.count > 1 && min(5, upcoming.count) < unsaved.count {
                    Button("Save next \(min(5, upcoming.count)) chapters", systemImage: "arrow.down.circle") { save(Array(upcoming.prefix(5))) }
                }
                if upcoming.count > 5 && min(10, upcoming.count) < unsaved.count {
                    Button("Save next \(min(10, upcoming.count)) chapters", systemImage: "arrow.down.circle") { save(Array(upcoming.prefix(10))) }
                }
                Button(unsaved.count == 1 ? "Save the remaining chapter" : "Save all \(unsaved.count) unsaved chapters", systemImage: "square.and.arrow.down.on.square") {
                    save(unsaved)
                }
                .disabled(unsaved.isEmpty)
            }
        } label: {
            Image(systemName: unsaved.isEmpty ? "checkmark.circle.fill" : "arrow.down.circle")
                .foregroundStyle(unsaved.isEmpty ? AstralColors.success : AstralColors.gold)
                .frame(width: 36, height: 36)
        }
        .accessibilityLabel(unsaved.isEmpty ? "All chapters saved on this device" : "Save chapters for offline reading")
    }

    @ViewBuilder
    private func chapterMenu(_ chapter: LocalComicChapter, isBookmarked: Bool) -> some View {
        Button(isBookmarked ? "Remove bookmark" : "Bookmark chapter", systemImage: isBookmarked ? "bookmark.slash" : "bookmark") {
            toggleBookmark(for: chapter)
        }
        if comic.sourceKey != "local" && chapter.localPagesPath == nil {
            Button("Save for offline reading", systemImage: "arrow.down.circle") { save([chapter]) }
                .disabled(downloadProgress != nil)
        }
    }

    // MARK: - Bookmarks

    @ViewBuilder
    private func bookmarkSection(_ ordered: [LocalComicChapter]) -> some View {
        if bookmarks.isEmpty {
            EmptyStateView(
                icon: "bookmark",
                title: "No bookmarks yet",
                message: "Bookmark a page from the reader's ••• menu, or long-press a chapter."
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(bookmarks) { bookmark in
                    HStack(spacing: 12) {
                        Button {
                            if let chapter = ordered.first(where: { $0.id == BookmarkAnchorStore.chapter(for: bookmark.id) }) ?? ordered.first(where: { $0.chapterNumber == bookmark.chapterNumber }) {
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
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button {
                            BookmarkUndoService.shared.delete(bookmark, context: modelContext)
                        } label: {
                            Image(systemName: "trash").font(.footnote).frame(width: 36, height: 36)
                        }
                        .foregroundStyle(AstralColors.muted)
                        .accessibilityLabel("Delete bookmark")
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 8)
                    .padding(.vertical, 6)

                    Divider()
                        .background(AstralColors.elevated)
                        .padding(.leading, 16)
                }
            }
        }
    }

    /// Bookmarked chapters, resolved once per update rather than per row.
    private var bookmarkIndex: (chapterIDs: Set<UUID>, unanchoredNumbers: Set<Double>) {
        var ids = Set<UUID>(), numbers = Set<Double>()
        for bookmark in bookmarks {
            if let id = BookmarkAnchorStore.chapter(for: bookmark.id) { ids.insert(id) } else { numbers.insert(bookmark.chapterNumber) }
        }
        return (ids, numbers)
    }

    private func toggleBookmark(for chapter: LocalComicChapter) {
        let existing = bookmarks.first {
            BookmarkAnchorStore.chapter(for: $0.id).map { $0 == chapter.id } ?? ($0.chapterNumber == chapter.chapterNumber)
        }
        if let existing {
            BookmarkUndoService.shared.delete(existing, context: modelContext)
        } else {
            let bookmark = LocalBookmark(contentType: "comic", storyId: comic.id, chapterNumber: chapter.chapterNumber,
                                         heading: ComicChapterLabel(chapter).heading)
            modelContext.insert(bookmark)
            BookmarkAnchorStore.save(bookmark: bookmark.id, chapter: chapter.id)
            try? modelContext.save()
            Haptics.play(.bookmark)
        }
    }

    // MARK: - More menu

    private var moreMenu: some View {
        Menu {
            if let sourceURL = UserDefaults.standard.string(forKey: "reading.source." + comic.id.uuidString).flatMap(URL.init(string:)) {
                Button("Check for new chapters", systemImage: "arrow.clockwise") {
                    comicNavigation?.sourceKey = ComicSource(rawValue: comic.sourceKey == "mangadex-device" ? "mangadex" : comic.sourceKey)
                    comicNavigation?.sourceURL = sourceURL
                    dismiss()
                    comicNavigation?.activeSection = .browse
                }
            }
            Button(comic.completedAt == nil ? "Mark as finished" : "Mark as unfinished",
                   systemImage: comic.completedAt == nil ? "checkmark.circle" : "arrow.uturn.backward.circle") {
                comic.completedAt = comic.completedAt == nil ? .now : nil
                try? modelContext.save()
            }
            Divider()
            Button(role: .destructive) {
                showDeleteAlert = true
            } label: {
                Label("Delete permanently", systemImage: "trash.slash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(AstralColors.gold)
        }
        .accessibilityLabel("More actions")
    }

    // MARK: - Helpers

    /// The chapter the reader would open: the saved position, else the legacy
    /// chapter number, else the first chapter.
    private func currentChapter(in ordered: [LocalComicChapter]) -> LocalComicChapter? {
        if let saved = ReadingPositionStore.position(story: comic.id), let chapter = ordered.first(where: { $0.id == saved.chapterID }) { return chapter }
        if comic.lastReadChapterNumber == 0 { return ordered.first }
        return ordered.first { Int($0.chapterNumber) == comic.lastReadChapterNumber }
            ?? ordered.first { $0.chapterNumber > Double(comic.lastReadChapterNumber) }
            ?? ordered.first
    }

    private func save(_ chapters: [LocalComicChapter]) {
        guard comic.sourceKey != "local", downloadProgress == nil, !chapters.isEmpty else { return }
        downloadProgress = (0, chapters.count)
        downloadTask = Task {
            let error = await ChapterDownloadService.shared.downloadAllChapters(
                comic: comic, chapters: chapters,
                modelContext: modelContext,
                onCancel: { downloadTask?.cancel() }
            ) { done, total in
                downloadProgress = (done, total)
            }
            downloadProgress = nil
            if !Task.isCancelled { downloadError = error }
        }
    }

    private func syncChapters() async {
        guard AppConfig.companionEnabled, comic.sourceKey != "local", comic.sourceKey != "mangadex-device", !DeviceComicService.sources.contains(comic.sourceKey) else { return }
        do {
            let response: ComicResponse = try await APIClient.shared.request(
                .comicDetail(id: comic.id)
            )
            guard let dtoChapters = response.chapters else { return }
            let comicID = comic.id
            let descriptor = FetchDescriptor<LocalComicChapter>(
                predicate: #Predicate<LocalComicChapter> { $0.comicId == comicID }
            )
            let existing = (try? modelContext.fetch(descriptor)) ?? []
            let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

            for dto in dtoChapters {
                if let ch = existingByID[dto.id] {
                    ch.chapterNumber = dto.chapterNumber
                    ch.title = dto.title
                    ch.totalPages = dto.totalPages
                    ch.scrapeStatus = dto.scrapeStatus
                } else {
                    let ch = LocalComicChapter(
                        id: dto.id, comicId: comicID,
                        chapterNumber: dto.chapterNumber, title: dto.title,
                        totalPages: dto.totalPages, scrapeStatus: dto.scrapeStatus
                    )
                    ch.comic = comic
                    modelContext.insert(ch)
                }
            }
            try? modelContext.save()
        } catch {
            AstralLogger.error("syncChapters failed: \(error)", context: "ComicDetail")
        }
    }
}

// MARK: - Chapter Row

private struct ComicChapterRow: View {
    let chapter: LocalComicChapter
    let isCurrent: Bool
    let isBookmarked: Bool

    var body: some View {
        let label = ComicChapterLabel(chapter)
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Ch. \(label.number)")
                        .font(AstralTypography.bodyMedium)
                        .foregroundStyle(isCurrent ? AstralColors.gold : AstralColors.white)
                    if let name = label.name {
                        Text(name)
                            .font(AstralTypography.body)
                            .foregroundStyle(AstralColors.body)
                            .lineLimit(1)
                    }
                }
                let details = [label.volume.map { "Vol. " + $0 }, label.group, chapter.totalPages > 0 ? "\(chapter.totalPages) pages" : nil].compactMap { $0 }
                if !details.isEmpty {
                    Text(details.joined(separator: " · "))
                        .font(AstralTypography.caption)
                        .foregroundStyle(AstralColors.muted)
                        .lineLimit(1)
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
            downloadStatusIcon
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
    private var downloadStatusIcon: some View {
        if chapter.localPagesPath != nil {
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
                EmptyView()
            }
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
