import SwiftUI
import SwiftData
import Core
import DesignSystem
import Networking

// MARK: - Reading Mode

enum ReadingMode: String, CaseIterable {
    case webtoon     = "Webtoon"
    case leftToRight = "L → R"
    case rightToLeft = "R ← L"

    var icon: String {
        switch self {
        case .webtoon:     "arrow.down"
        case .leftToRight: "arrow.right"
        case .rightToLeft: "arrow.left"
        }
    }
}

enum ComicChapterPullTrigger {
    static func shouldFire(progress: CGFloat, hasTriggered: Bool) -> Bool {
        progress >= 1.0 && !hasTriggered
    }
}

struct ComicReaderPageSource {
    let networkPageCount: Int
    let localPageURLs: [URL]?

    var usesLocalPages: Bool {
        guard let localPageURLs else { return false }
        return !localPageURLs.isEmpty
    }

    var pageCount: Int {
        if let localPageURLs, !localPageURLs.isEmpty {
            return localPageURLs.count
        }
        return networkPageCount
    }
}

// MARK: - Main View

struct ComicReaderView: View {
    let comic: LocalComic
    let chapters: [LocalComicChapter]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var currentChapterIndex: Int
    @State private var pages: [PageResponse] = []
    @State private var currentPage: Int = 0
    @State private var resumePageForLayout = 0
    @State private var previousPageJump: Int?
    @State private var isLoading = true
    @State private var showHUD = true
    @State private var showSettings = false
    @AppStorage("comicReaderMode") private var readingMode: ReadingMode = .webtoon
    @AppStorage("comicReaderBrightness") private var brightnessOverlay: Double = 0.0
    @Query private var bookmarks: [LocalBookmark]
    @State private var nextChapterPull: CGFloat = 0
    @State private var nextChapterTriggered = false
    @State private var atBottomOfChapter = false
    @State private var scrolledPageID: Int? = 0  // drives paged scroll position
    @State private var showRotateHint = false
    @AppStorage("hideRotateHint") private var hideRotateHint = false
    @AppStorage("forceLandscape") private var forceLandscape = false
    @State private var readingSession: LocalReadingSession?
    @State private var localPageURLs: [URL]?
    @State private var prevChapterPull: CGFloat = 0
    @State private var prevChapterTriggered = false
    // AST-65 arming: edge-visibility timestamps drive a 0.5s arm delay.
    // nil = edge not visible. Once armed, pull can fire the trigger.
    @State private var topEdgeVisibleSince: Date? = nil
    @State private var topEdgeArmedAt: Date? = nil
    @State private var bottomEdgeVisibleSince: Date? = nil
    @State private var bottomEdgeArmedAt: Date? = nil
    @State private var hasCompletedInitialLayout = false
    @State private var pageThrottle = ThrottledSetter<Int>(interval: 0.08)
    @State private var pendingScrollToPage: Int?
    @State private var showChapterList = false
    @State private var autoScrollActive = false
    @AppStorage("autoScrollSpeed") private var autoScrollSpeed: Double = 1.5
    @State private var offlineError = false
    @State private var appliedSkip = 0
    @State private var saveChapterTask: Task<Void, Never>?
    @State private var isSavingChapter = false
    @State private var saveError: String?

    // Namespaces for matched geometry
    @Namespace private var modeNS

    private let initialBookmark: LocalBookmark?
    @State private var appliedInitialBookmark = false
    private let previewPages: [PageResponse]?

    init(
        comic: LocalComic,
        chapters: [LocalComicChapter],
        startingAt chapter: LocalComicChapter,
        previewPages: [PageResponse]? = nil,
        bookmark: LocalBookmark? = nil
    ) {
        self.initialBookmark = bookmark
        self.comic = comic
        let orderedChapters = ChapterOrdering.comics(chapters)
        self.chapters = orderedChapters
        self.previewPages = previewPages
        let idx = orderedChapters.firstIndex(where: { $0.id == chapter.id }) ?? 0
        _currentChapterIndex = State(initialValue: idx)
        let comicId = comic.id
        _bookmarks = Query(
            filter: #Predicate<LocalBookmark> { $0.storyId == comicId && $0.contentType == "comic" },
            sort: \LocalBookmark.createdAt,
            order: .reverse
        )
    }

    private var currentChapter: LocalComicChapter? { chapters[safe: currentChapterIndex] }
    private var isFirstChapter: Bool { currentChapterIndex <= 0 }
    private var isLastChapter:  Bool { currentChapterIndex >= chapters.count - 1 }
    private var pageSource: ComicReaderPageSource {
        ComicReaderPageSource(networkPageCount: pages.count, localPageURLs: localPageURLs)
    }

    private var chapterProgress: Double {
        let count = pageSource.pageCount
        guard count > 1 else { return count == 0 ? 0 : 1 }
        return Double(currentPage) / Double(count - 1)
    }

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @AppStorage("readerAlwaysShowControls") private var alwaysShowControls = false
    @State private var isZoomed = false
    @State private var isTransitioning = false
    @State private var transitionError: String?
    @State private var failedIndex: Int?
    @State private var previousJumpIndex: Int?
    @State private var scrollController = ReaderScrollController()
    @State private var pullProgress = 0.0
    @State private var visiblePageID: Int?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if isLoading {
                ProgressView("Opening chapter…").tint(AstralColors.gold)
            } else if pageSource.pageCount == 0 {
                ContentUnavailableView {
                    Label("Chapter unavailable", systemImage: "book.closed")
                } description: {
                    Text("Save this chapter from a supported source or connected companion.")
                } actions: {
                    Button("Try again") { Task { await loadPages() } }
                    Button("Back") { dismiss() }
                }
            } else {
                pageContent.id(currentChapterIndex)
            }
            if brightnessOverlay > 0 { Color.black.opacity(brightnessOverlay).ignoresSafeArea().allowsHitTesting(false) }
            VStack {
                if showHUD || alwaysShowControls || voiceOverEnabled { topBar }
                Spacer()
                if pullProgress != 0 { ReaderPullHint(progress: pullProgress).padding(.bottom, 100) }
                if showHUD || alwaysShowControls || voiceOverEnabled { bottomBar }
            }
            if isTransitioning { ProgressView("Opening chapter…").padding().background(.regularMaterial, in: Capsule()) }
        }
        .overlay(alignment: .bottom) { BookmarkUndoBanner().padding(.bottom, 70) }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .task { await loadPages() }
        .onAppear {
            startSession()
            UIApplication.shared.isIdleTimerDisabled = true
            if forceLandscape { setLandscape(true) }
        }
        .onDisappear {
            autoScrollActive = false
            persistReadingState(endSession: true, syncRemote: false)
            UIApplication.shared.isIdleTimerDisabled = false
            if forceLandscape { setLandscape(false) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { startSession() }
            else { autoScrollActive = false; persistReadingState(endSession: phase == .background, syncRemote: false) }
        }
        .onChange(of: readingMode) { _, _ in autoScrollActive = false; isZoomed = false; visiblePageID = currentPage; scrolledPageID = currentPage }
        .onChange(of: showHUD) { _, visible in if visible { autoScrollActive = false } }
        .onChange(of: showSettings) { _, visible in if visible { autoScrollActive = false } }
        .onChange(of: showChapterList) { _, visible in if visible { autoScrollActive = false } }
        .sheet(isPresented: $showSettings, onDismiss: { autoScrollActive = false; Task { await loadPages() } }) {
            NavigationStack {
                ScrollView { settingsPanel }
                    .navigationTitle("Display settings").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { showSettings = false } }
                        ToolbarItem(placement: .cancellationAction) { Button("Reset") {
                            readingMode = .webtoon; brightnessOverlay = 0; autoScrollActive = false; autoScrollSpeed = 1.5; forceLandscape = false
                        } }
                    }
            }.presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showChapterList) {
            ComicChapterListSheet(chapters: chapters, currentIndex: currentChapterIndex, onSelect: { index in
                showChapterList = false; previousJumpIndex = currentChapterIndex; requestChapter(index)
            }).presentationDetents([.medium, .large])
        }
        .alert(saveError == nil ? "Chapter could not be opened" : "Chapter could not be saved", isPresented: Binding(get: { transitionError != nil || saveError != nil }, set: { if !$0 { transitionError = nil; saveError = nil } })) {
            if saveError != nil { Button("OK", role: .cancel) { saveError = nil } } else {
            if let failedIndex { Button("Retry") { requestChapter(failedIndex) } }
            Button("Keep reading", role: .cancel) { transitionError = nil }
            Button("Back") { dismiss() }
            }
        } message: { Text(saveError ?? transitionError ?? "") }
    }

    private func startSession() {
        guard readingSession == nil || readingSession?.endedAt != nil else { return }
        let session = LocalReadingSession(contentType: "comic", storyId: comic.id)
        modelContext.insert(session); readingSession = session
    }

    // MARK: - Page Content

    @ViewBuilder
    private var pageContent: some View {
        switch readingMode {
        case .webtoon:
            webtoonReader
        case .leftToRight:
            pagedReader(reversed: false)
        case .rightToLeft:
            pagedReader(reversed: true)
        }
    }

    private var webtoonReader: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(0..<pageSource.pageCount, id: \.self) { index in
                        pageView(index)
                            .id(index)
                    }
                }
                .scrollTargetLayout()
                .padding(.top, 70).padding(.bottom, 90)
                .background(ReaderScrollMonitor(controller: scrollController, reportsProgrammaticChanges: autoScrollActive, enabled: !autoScrollActive && !isZoomed && !isTransitioning && !showSettings && !showChapterList,
                    onPosition: { fraction in if fraction >= 0.999 { autoScrollActive = false } },
                    onPull: { pullProgress = $0 },
                    onRelease: { next in if next { goToNextChapter() } else { goToPrevChapter() } }))
                .modifier(AutoScrollModifier(isActive: autoScrollActive && !showSettings && !showChapterList && scenePhase == .active, speed: autoScrollSpeed))
            }
            .scrollBounceBehavior(.always, axes: .vertical)
            .scrollDisabled(isZoomed)
            .scrollPosition(id: $visiblePageID, anchor: .top)
            .onChange(of: visiblePageID) { _, id in
                if let id, id >= 0 { currentPage = id }
            }
            .onChange(of: pendingScrollToPage) { _, target in
                if let target { proxy.scrollTo(target, anchor: .top); currentPage = target; pendingScrollToPage = nil }
            }
        }
    }

    @ViewBuilder private func pageView(_ index: Int) -> some View {
        ZoomablePageView(onSingleTap: toggleHUD, onZoom: { isZoomed = $0 }) {
            if let local = localPageURLs, local.indices.contains(index) { LocalPageView(fileURL: local[index]) }
            else if pages.indices.contains(index) { ComicPageView(page: pages[index], referrer: UserDefaults.standard.string(forKey: "reading.chapterSource." + (currentChapter?.id.uuidString ?? "")) ?? UserDefaults.standard.string(forKey: "reading.source." + comic.id.uuidString)) }
        }
    }

    private func pagedReader(reversed: Bool) -> some View {
        // IDs are source page indices. RTL changes spatial direction only.
        ScrollViewReader { proxy in
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(0..<pageSource.pageCount, id: \.self) { index in
                    pageView(index).padding(.vertical, 70).containerRelativeFrame(.horizontal).id(index)
                }
            }
            .scrollTargetLayout()
            .background(ReaderScrollMonitor(axis: .horizontal, reversed: reversed,
                enabled: !isZoomed && !isTransitioning && !showSettings && !showChapterList,
                onPosition: { _ in }, onPull: { pullProgress = $0 },
                onRelease: { next in if next { goToNextChapter() } else { goToPrevChapter() } }))
        }
        .scrollBounceBehavior(.always, axes: .horizontal)
        .environment(\.layoutDirection, reversed ? .rightToLeft : .leftToRight)
        .scrollDisabled(isZoomed)
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $scrolledPageID, anchor: .center)
        .onChange(of: scrolledPageID) { _, id in if let id, id >= 0 { currentPage = id } }
        .onChange(of: currentPage) { _, page in if scrolledPageID != page { scrolledPageID = page } }
        .task(id: readingMode) {
            await Task.yield()
            proxy.scrollTo(resumePageForLayout, anchor: .center)
        }
        }
    }

    private func toggleHUD() {
        guard !alwaysShowControls else { return }
        withAnimation(ReaderMotion.chrome) {
            showHUD.toggle()
            if !showHUD { showSettings = false }
        }
        Haptics.play(.chromeToggle)
    }

    private func setLandscape(_ landscape: Bool) {
        if landscape {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape))
        } else {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .all))
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                .accessibilityLabel("Back").accessibilityIdentifier(AccessibilityID.readerBackButton)
            VStack(alignment: .leading, spacing: 2) {
                Text(comic.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(currentChapter?.title ?? "Chapter \((currentChapter?.chapterNumber ?? 0).formatted())").font(.headline).lineLimit(2)
            }
            Spacer(minLength: 0)
            Menu {
                if readingMode == .webtoon {
                    Menu("Scroll") {
                        Button("Up one screen") { scrollController.move(forward: false) }
                        Button("Down one screen") { scrollController.move(forward: true) }
                    }
                }
                Button(comic.isFavorite ? "Remove favourite" : "Add favourite", systemImage: "heart") { comic.isFavorite.toggle(); try? modelContext.save() }
                Button("Bookmark current page", systemImage: "bookmark") { bookmarkCurrentChapter() }
                if comic.sourceKey != "local" {
                    Button(isSavingChapter ? "Saving chapter…" : (currentChapter?.isDownloaded == true ? "Saved on this device" : "Save chapter for offline reading"), systemImage: "arrow.down.circle") {
                        saveCurrentChapter()
                    }.disabled(isLoading || isTransitioning || isSavingChapter || currentChapter?.isDownloaded == true || currentChapter?.downloadStatus == .queued || currentChapter?.downloadStatus == .downloading)
                }
                if let previousJumpIndex { Button("Back to previous chapter") { requestChapter(previousJumpIndex); self.previousJumpIndex = nil } }
                if !isFirstChapter { Button("Previous chapter") { goToPrevChapter() } }
                if !isLastChapter { Button("Next chapter") { goToNextChapter() } }
                if let page = previousPageJump {
                    Button("Return to previous page") { currentPage = page; scrolledPageID = page; pendingScrollToPage = page; previousPageJump = nil }
                }
                Button("Start chapter over") { currentPage = 0; scrolledPageID = 0; pendingScrollToPage = 0 }
                if readingMode == .webtoon {
                    Button(autoScrollActive ? "Pause auto-scroll" : "Start auto-scroll", systemImage: "arrow.down") {
                        autoScrollActive.toggle(); if autoScrollActive { showHUD = false }
                    }
                }
                Button(comic.completedAt == nil ? "Mark finished" : "Mark unfinished") { comic.completedAt = comic.completedAt == nil ? .now : nil; try? modelContext.save() }
            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
            .accessibilityLabel("More reader actions")
        }
        .foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 6).background(.regularMaterial)
    }
    private var bottomBar: some View {
        HStack {
            Button("Chapters", systemImage: "list.bullet") { showChapterList = true }.frame(minHeight: 44)
            Spacer()
            Menu {
                ForEach(0..<pageSource.pageCount, id: \.self) { index in
                    Button("Page \(index + appliedSkip + 1)") { previousPageJump = currentPage; currentPage = index; scrolledPageID = index; pendingScrollToPage = index }
                }
            } label: {
                Text("Page \(currentPage + appliedSkip + 1) of \(pageSource.pageCount + appliedSkip)").font(.caption).monospacedDigit().frame(minHeight: 44)
            }.accessibilityLabel("Choose page").accessibilityValue("Page \(currentPage + appliedSkip + 1) of \(pageSource.pageCount + appliedSkip)")
            Spacer()
            Button("Display", systemImage: "slider.horizontal.3") { persistReadingState(endSession: false, syncRemote: false); showSettings = true }
                .labelStyle(.iconOnly).accessibilityLabel("Display settings").frame(width: 44, height: 44)
        }
        .padding(.horizontal, 16).padding(.vertical, 6).background(.regularMaterial)
    }

    // MARK: - Settings Panel

    private var settingsPanel: some View {
        VStack(spacing: 20) {
            // Reading mode — sliding indicator via matchedGeometryEffect
            VStack(alignment: .leading, spacing: 10) {
                Text("Reading Mode")
                    .font(AstralTypography.captionMedium)
                    .foregroundStyle(AstralColors.muted)

                HStack(spacing: 8) {
                    ForEach(ReadingMode.allCases, id: \.self) { mode in
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                resumePageForLayout = currentPage
                                readingMode = mode
                            }
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: mode.icon)
                                    .font(.title3)
                                Text(mode.rawValue)
                                    .font(AstralTypography.caption)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(readingMode == mode ? AstralColors.gold : AstralColors.body)
                            .background {
                                if readingMode == mode {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(AstralColors.gold.opacity(0.15))
                                        .matchedGeometryEffect(id: "modeIndicator", in: modeNS)
                                } else {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(AstralColors.elevated)
                                }
                            }
                        }
                        .buttonStyle(PressButtonStyle(scale: 0.94))
                    }
                }
            }

            // Page skip
            VStack(alignment: .leading, spacing: 10) {
                Text("Skip First Pages")
                    .font(AstralTypography.captionMedium)
                    .foregroundStyle(AstralColors.muted)

                Stepper(value: Binding(
                    get: { comic.skipFirstNPages },
                    set: { newVal in
                        comic.skipFirstNPages = newVal
                        try? modelContext.save()
                    }
                ), in: 0...10) {
                    Text("\(comic.skipFirstNPages) page\(comic.skipFirstNPages == 1 ? "" : "s")")
                        .font(AstralTypography.body)
                        .foregroundStyle(AstralColors.white)
                }
                .tint(AstralColors.gold)
            }

            // Brightness dim
            VStack(alignment: .leading, spacing: 10) {
                Text("Brightness")
                    .font(AstralTypography.captionMedium)
                    .foregroundStyle(AstralColors.muted)

                HStack(spacing: 12) {
                    Image(systemName: "sun.max.fill")
                        .foregroundStyle(AstralColors.muted)
                    Slider(value: $brightnessOverlay, in: 0...0.75)
                        .tint(AstralColors.gold)
                    Image(systemName: "sun.min.fill")
                        .foregroundStyle(AstralColors.muted)
                }
            }

            if readingMode == .webtoon {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Auto-scroll speed").font(.headline)
                    Slider(value: $autoScrollSpeed, in: 0.5...5, step: 0.5).accessibilityLabel("Auto-scroll speed")
                    Text("Start or pause auto-scroll from More in the reader. It pauses when you open a sheet or leave Astral.").font(.footnote).foregroundStyle(.secondary)
                }
            }

            // Landscape lock toggle
            HStack {
                Image(systemName: "rectangle.landscape.rotate")
                    .foregroundStyle(AstralColors.muted)
                Text("Force Landscape")
                    .font(AstralTypography.body)
                    .foregroundStyle(AstralColors.white)
                Spacer()
                Toggle("", isOn: $forceLandscape)
                    .tint(AstralColors.gold)
                    .labelsHidden()
            }
            .onChange(of: forceLandscape) { _, newVal in
                setLandscape(newVal)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 16)
        .background(.ultraThinMaterial)
    }

    // MARK: - Page Navigation

    private func prevPage() { if currentPage > 0 { currentPage -= 1 } }
    private func nextPage() { if currentPage < pageSource.pageCount - 1 { currentPage += 1 } }
    private func goToPrevChapter() { requestChapter(currentChapterIndex - 1) }
    private func goToNextChapter() { requestChapter(currentChapterIndex + 1) }
    // MARK: - Bookmark

    private var isCurrentChapterBookmarked: Bool {
        guard let chapter = currentChapter else { return false }
        return bookmarks.contains { $0.chapterNumber == chapter.chapterNumber }
    }

    private func bookmarkCurrentChapter() {
        guard let chapter = currentChapter else { return }
        if let existing = bookmarks.first(where: { $0.chapterNumber == chapter.chapterNumber }) {
            BookmarkUndoService.shared.delete(existing, context: modelContext)
            AstralLogger.info("Bookmark removed: ch \(chapter.chapterNumber)", context: "ComicReader")
        } else {
            let bookmark = LocalBookmark(
                contentType: "comic",
                storyId: comic.id,
                chapterNumber: chapter.chapterNumber,
                pageNumber: currentPage + appliedSkip + 1,
                heading: chapter.title ?? "Chapter \(Int(chapter.chapterNumber))"
            )
            modelContext.insert(bookmark)
            BookmarkAnchorStore.save(bookmark: bookmark.id, chapter: chapter.id)
            AstralLogger.info("Bookmark added: ch \(chapter.chapterNumber) page \(currentPage + 1)", context: "ComicReader")
        }
        try? modelContext.save()
        Haptics.play(.bookmark)
    }

    // MARK: - Long Press Actions


    // MARK: - Loading

    private func persistReadingState(endSession: Bool, syncRemote: Bool) {
        if endSession { readingSession?.endedAt = .now; try? modelContext.save() }
        guard let chapter = currentChapter, !isLoading, pageSource.pageCount > 0 else { return }
        comic.lastReadChapterNumber = Int(chapter.chapterNumber) // legacy display fallback only
        comic.lastReadPageNumber = currentPage + appliedSkip + 1
        comic.lastReadAt = .now
        comic.progressPercent = min(1, (Double(currentChapterIndex) + Double(currentPage) / Double(max(1, pageSource.pageCount))) / Double(max(1, chapters.count)))
        ReadingPositionStore.save(.init(chapterID: chapter.id, chapterNumber: chapter.chapterNumber,
            page: currentPage + appliedSkip), story: comic.id)
        if endSession { readingSession?.endedAt = .now }
        try? modelContext.save()
    }

    private struct ChapterPages {
        let network: [PageResponse]
        let local: [URL]?
        var count: Int { local?.count ?? network.count }
    }
    private func fetchPages(_ chapter: LocalComicChapter) async throws -> ChapterPages {
        if let previewPages { return .init(network: previewPages, local: nil) }
        if let urls = ChapterDownloadService.shared.localPageURLs(for: chapter),
           !urls.isEmpty, chapter.totalPages == 0 || chapter.totalPages == urls.count {
            return .init(network: [], local: urls)
        }
        if comic.sourceKey == "mangadex-device" { return .init(network: try await MangaDexDeviceService.pages(chapter.id), local: nil) }
        if DeviceComicService.sources.contains(comic.sourceKey) { return .init(network: try await DeviceComicService.pages(comic: comic, chapter: chapter), local: nil) }
        guard comic.sourceKey != "local", AppConfig.companionEnabled else { throw APIError.companionUnavailable }
        let response: [PageResponse] = try await APIClient.shared.request(.chapterPages(comicId: comic.id, chapterId: chapter.id))
        guard !response.isEmpty else { throw APIError.notFound }
        return .init(network: response, local: nil)
    }
    private func apply(_ source: ChapterPages, chapter: LocalComicChapter) {
        appliedSkip = min(max(0, comic.skipFirstNPages), max(0, source.count - 1))
        pages = Array(source.network.dropFirst(appliedSkip))
        localPageURLs = source.local.map { Array($0.dropFirst(appliedSkip)) }
        let saved = ReadingPositionStore.position(story: comic.id, chapter: chapter.id)
        let legacy = comic.lastReadChapterNumber == Int(chapter.chapterNumber) ? max(0, comic.lastReadPageNumber - 1) : 0
        currentPage = min(max(0, (saved?.page ?? legacy) - appliedSkip), max(0, source.count - appliedSkip - 1))
        if let bookmark = initialBookmark, !appliedInitialBookmark, bookmark.chapterNumber == chapter.chapterNumber {
            currentPage = min(max(0, (bookmark.pageNumber ?? 1) - appliedSkip - 1), max(0, source.count - appliedSkip - 1))
            appliedInitialBookmark = true
        }
        resumePageForLayout = currentPage
        scrolledPageID = currentPage; visiblePageID = currentPage
        isZoomed = false; offlineError = false
    }
    private func loadPages() async {
        guard let chapter = currentChapter else { isLoading = false; return }
        do { let source = try await fetchPages(chapter); apply(source, chapter: chapter) }
        catch { offlineError = true }
        isLoading = false
    }
    private func saveCurrentChapter() {
        guard let chapter = currentChapter, !isSavingChapter, !chapter.isDownloaded else { return }
        isSavingChapter = true
        saveChapterTask = Task { @MainActor in
            saveError = await ChapterDownloadService.shared.downloadAllChapters(
                comic: comic, chapters: [chapter], modelContext: modelContext,
                onCancel: { saveChapterTask?.cancel() }, onProgress: { _, _ in }
            )
            isSavingChapter = false
        }
    }
    private func requestChapter(_ index: Int) {
        guard chapters.indices.contains(index), index != currentChapterIndex, !isTransitioning else { return }
        persistReadingState(endSession: false, syncRemote: false)
        isTransitioning = true; transitionError = nil; failedIndex = nil; autoScrollActive = false
        Task { @MainActor in
            defer { isTransitioning = false; pullProgress = 0 }
            do {
                let chapter = chapters[index]
                let source = try await fetchPages(chapter)
                try Task.checkCancellation()
                currentChapterIndex = index
                apply(source, chapter: chapter)
                readingSession?.chaptersRead += 1
                persistReadingState(endSession: false, syncRemote: false)
                Haptics.play(.chapterNav)
            } catch { failedIndex = index; transitionError = error.localizedDescription; showHUD = true }
        }
    }

}

// MARK: - Page View

struct ComicPageView: View {
    let page: PageResponse
    var referrer: String? = nil
    @State private var retryID = UUID()
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else {
                Rectangle().fill(AstralColors.elevated).aspectRatio(aspectRatio, contentMode: .fit)
                    .overlay {
                        if failed {
                            Button("Retry page", systemImage: "arrow.clockwise.circle") { retryID = UUID() }
                                .foregroundStyle(AstralColors.muted).frame(minHeight: 44)
                        } else { ProgressView().tint(AstralColors.gold) }
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .task(id: page.filePath + retryID.uuidString) {
            image = nil; failed = false
            do {
                guard let url = URL(string: page.filePath.hasPrefix("https://") ? page.filePath : AppConfig.staticBaseURL + page.filePath) else { throw APIError.invalidURL }
                let (data, response) = try await SourceImageTransport.session.data(for: SourceImageTransport.request(url, referrer: referrer))
                try Task.checkCancellation()
                guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode), let decoded = UIImage(data: data) else { throw APIError.invalidResponse }
                image = decoded
            } catch is CancellationError { } catch { if !Task.isCancelled { failed = true } }
        }
    }
    private var aspectRatio: CGFloat {
        if let w = page.widthPx, let h = page.heightPx, h > 0 { return CGFloat(w) / CGFloat(h) }
        return 2.0 / 3.0
    }
}

/// Renders a page image from a local file URL (device-saved chapters).
private struct LocalPageView: View {
    let fileURL: URL

    var body: some View {
        if let uiImage = UIImage(contentsOfFile: fileURL.path) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
        } else {
            Rectangle()
                .fill(AstralColors.elevated)
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .overlay {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.title2)
                        Text("Failed to load")
                            .font(AstralTypography.caption)
                    }
                    .foregroundStyle(AstralColors.muted)
                }
        }
    }
}

// MARK: - Auto-Scroll Modifier

/// Finds the nearest UIScrollView ancestor and drives smooth continuous scrolling via CADisplayLink.
private struct AutoScrollModifier: ViewModifier {
    let isActive: Bool
    let speed: Double  // points per frame at 60fps

    func body(content: Content) -> some View {
        content
            .background(AutoScrollFinder(isActive: isActive, speed: speed))
    }
}

/// UIViewRepresentable that finds the enclosing UIScrollView and attaches a CADisplayLink.
private struct AutoScrollFinder: UIViewRepresentable {
    let isActive: Bool
    let speed: Double

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.speed = speed

        if isActive {
            context.coordinator.startScrolling(in: uiView)
        } else {
            context.coordinator.stopScrolling()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(speed: speed)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) { coordinator.stopScrolling() }

    @MainActor
    class Coordinator {
        var speed: Double
        private var displayLink: CADisplayLink?
        private weak var scrollView: UIScrollView?

        init(speed: Double) {
            self.speed = speed
        }

        func startScrolling(in view: UIView) {
            guard displayLink == nil else { return }
            scrollView = findScrollView(in: view)
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        func stopScrolling() {
            displayLink?.invalidate()
            displayLink = nil
        }

        @objc private func tick() {
            guard let sv = scrollView else { return }
            let maxY = sv.contentSize.height - sv.bounds.height + sv.contentInset.bottom
            guard maxY > 0 else { stopScrolling(); return }
            let newY = min(sv.contentOffset.y + speed, maxY)
            sv.contentOffset.y = newY
            if newY >= maxY { stopScrolling() }
        }

        private func findScrollView(in view: UIView) -> UIScrollView? {
            var current: UIView? = view
            while let v = current {
                if let sv = v as? UIScrollView { return sv }
                current = v.superview
            }
            return nil
        }

        nonisolated deinit {
            // stopScrolling() handles cleanup; deinit is a safety net.
            // CADisplayLink is invalidated in stopScrolling() which is
            // always called from updateUIView before deallocation.
        }
    }
}

// MARK: - Zoomable Page Wrapper

/// Wraps a comic page view with pinch-to-zoom and double-tap-to-zoom.
private struct ZoomablePageView<Content: View>: View {
    let content: Content
    let onSingleTap: () -> Void
    let onZoom: (Bool) -> Void
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var size: CGSize = .zero
    init(onSingleTap: @escaping () -> Void, onZoom: @escaping (Bool) -> Void, @ViewBuilder content: () -> Content) {
        self.onSingleTap = onSingleTap; self.onZoom = onZoom; self.content = content()
    }
    private func clamped(_ value: CGSize) -> CGSize {
        let x = size.width * (scale - 1) / 2, y = size.height * (scale - 1) / 2
        return CGSize(width: min(x, max(-x, value.width)), height: min(y, max(-y, value.height)))
    }
    var body: some View {
        content
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .scaleEffect(scale).offset(offset)
            .simultaneousGesture(MagnifyGesture().onChanged { value in
                scale = min(5, max(1, lastScale * value.magnification)); onZoom(scale > 1)
            }.onEnded { _ in lastScale = scale; offset = clamped(offset); lastOffset = offset })
            .highPriorityGesture(scale > 1 ? DragGesture().onChanged { value in
                offset = clamped(CGSize(width: lastOffset.width + value.translation.width, height: lastOffset.height + value.translation.height))
            }.onEnded { _ in lastOffset = offset } : nil)
            .gesture(TapGesture(count: 2).exclusively(before: TapGesture()).onEnded { result in
                switch result {
                case .first:
                    scale = scale > 1 ? 1 : 2.5; lastScale = scale; offset = .zero; lastOffset = .zero; onZoom(scale > 1)
                case .second: onSingleTap()
                }
            })
            .onDisappear { onZoom(false) }
    }
}

// MARK: - Helpers

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Chapter List Sheet

private struct ComicChapterListSheet: View {
    let chapters: [LocalComicChapter]
    let currentIndex: Int
    let onSelect: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
                    Button {
                        onSelect(index)
                    } label: {
                        HStack(spacing: 12) {
                            // Chapter number pill
                            Text(chapterNum(chapter))
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(index == currentIndex ? AstralColors.gold : AstralColors.body)
                                .frame(width: 40, alignment: .center)

                            VStack(alignment: .leading, spacing: 2) {
                                if let title = chapter.title, !title.isEmpty {
                                    Text(title)
                                        .font(AstralTypography.body)
                                        .foregroundStyle(index == currentIndex ? AstralColors.white : AstralColors.body)
                                        .lineLimit(1)
                                }
                                Text("\(chapter.totalPages) pages")
                                    .font(AstralTypography.caption)
                                    .foregroundStyle(AstralColors.muted)
                            }

                            Spacer()

                            if index == currentIndex {
                                Image(systemName: "book.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(AstralColors.gold)
                            }

                            if chapter.isDownloaded {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(AstralColors.success)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(
                        index == currentIndex
                            ? AstralColors.gold.opacity(0.1)
                            : Color.clear
                    )
                    .id(index)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(AstralColors.background)
                .onAppear {
                    proxy.scrollTo(currentIndex, anchor: .center)
                }
            }
            .navigationTitle("Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(AstralColors.gold)
                }
            }
            .toolbarBackground(AstralColors.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    private func chapterNum(_ ch: LocalComicChapter) -> String {
        ch.chapterNumber.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(ch.chapterNumber))"
            : String(format: "%.1f", ch.chapterNumber)
    }
}

// MARK: - Previews

#Preview("Webtoon Mode") {
    let comic    = PreviewMocks.comic1
    let chapters = PreviewMocks.comic1Chapters
    return ComicReaderView(
        comic: comic,
        chapters: chapters,
        startingAt: chapters[0],
        previewPages: PreviewMocks.samplePages
    )
}

#Preview("Paged L→R") {
    let comic    = PreviewMocks.comic1
    let chapters = PreviewMocks.comic1Chapters
    return ComicReaderView(
        comic: comic,
        chapters: chapters,
        startingAt: chapters[0],
        previewPages: PreviewMocks.samplePages
    )
}

#Preview("Empty Chapter") {
    let comic    = PreviewMocks.comic1
    let chapters = PreviewMocks.comic1Chapters
    return ComicReaderView(
        comic: comic,
        chapters: chapters,
        startingAt: chapters[3],
        previewPages: []
    )
}
