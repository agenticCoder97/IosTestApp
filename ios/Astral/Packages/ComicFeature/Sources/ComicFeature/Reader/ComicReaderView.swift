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

/// Keep frequent geometry changes out of SwiftUI view state. Offsets are relative
/// to a source page, so lazy image sizing before that page cannot move the anchor.
private struct ComicWebtoonFrame: Equatable {
    var rect: CGRect
    var scrollOffset: Double?
}

@MainActor private final class ComicWebtoonPosition {
    var chapterID: UUID?
    var frames: [Int: ComicWebtoonFrame] = [:]
    /// Page tops in scroll-content coordinates; a change means a page above moved it.
    var contentTops: [Int: Double] = [:]
    var pending: (page: Int, offset: Double, signature: String)?
    var recorded: (page: Int, offset: Double, signature: String)?
    var lastReadingOffset: Double?
    var atEnd = false
    /// Set while a page's height change is still propagating to the pages after it.
    var layoutSettling = false
    var settleGeneration = 0
    var isRestoring = false
    var isScrollReady = false
    var isSourceAnchorReady = false

    func reset() {
        chapterID = nil
        isScrollReady = false
        isSourceAnchorReady = false
        frames.removeAll(); contentTops.removeAll()
        pending = nil; recorded = nil; lastReadingOffset = nil; atEnd = false; layoutSettling = false
    }
}

// MARK: - Main View

struct ComicReaderView: View {
    let comic: LocalComic
    let chapters: [LocalComicChapter]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale

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
    @State private var loadErrorMessage: String?
    @State private var appliedSkip = 0
    @State private var saveChapterTask: Task<Void, Never>?
    @State private var isSavingChapter = false
    @State private var saveError: String?
    @State private var imagePipeline = ComicImagePipeline()
    @State private var imagePixelWidth = 1536
    @State private var pageReferrer: String?

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
    private var nextChapterIndex: Int? { ComicChapterNavigation.neighbor(of: currentChapterIndex, in: chapters, forward: true) }
    private var previousChapterIndex: Int? { ComicChapterNavigation.neighbor(of: currentChapterIndex, in: chapters, forward: false) }
    private var isFirstChapter: Bool { previousChapterIndex == nil }
    private var isLastChapter:  Bool { nextChapterIndex == nil }
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
    @State private var readerViewport: CGSize = .zero
    @State private var webtoonPosition = ComicWebtoonPosition()
    @State private var preparedNext: (index: Int, source: ChapterPages, at: Date)?
    @State private var scrubPage: Double?
    @State private var chromeHideOrigin: Double?
    @State private var jumpTask: Task<Void, Never>?

    private var chromeVisible: Bool { showHUD || alwaysShowControls || voiceOverEnabled }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if isLoading {
                ProgressView("Opening chapter…").tint(AstralColors.gold)
            } else if pageSource.pageCount == 0 {
                ContentUnavailableView {
                    Label("Chapter unavailable", systemImage: offlineError ? "wifi.exclamationmark" : "book.closed")
                } description: {
                    Text(loadErrorMessage ?? "Save this chapter from a supported source or connected companion.")
                } actions: {
                    Button("Try again") { isLoading = true; Task { await loadPages() } }
                        .buttonStyle(.borderedProminent).tint(AstralColors.gold)
                    Button("Back") { dismiss() }
                }
            } else {
                pageContent.id(currentChapterIndex)
            }
            if brightnessOverlay > 0 { Color.black.opacity(brightnessOverlay).ignoresSafeArea().allowsHitTesting(false) }
            VStack(spacing: 0) {
                if chromeVisible { topBar.transition(.move(edge: .top).combined(with: .opacity)) }
                Spacer()
                if pullProgress != 0 { ReaderPullHint(progress: pullProgress).padding(.bottom, chromeVisible ? 16 : 40) }
                if chromeVisible { bottomBar.transition(.move(edge: .bottom).combined(with: .opacity)) }
            }
            if isTransitioning { ProgressView("Opening chapter…").padding().background(.regularMaterial, in: Capsule()) }
        }
        .overlay(alignment: .bottom) { BookmarkUndoBanner().padding(.bottom, 70) }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(!chromeVisible)
        .persistentSystemOverlays(chromeVisible ? .automatic : .hidden)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            let pipeline = imagePipeline
            Task { await pipeline.dropCache() }
        }
        .onChange(of: currentPage) { _, _ in prepareNextChapterIfNeeded() }
        .onGeometryChange(for: Int.self) { [displayScale] geometry in
            // Bucket widths to avoid invalidating requests for tiny layout changes.
            min(2560, max(1024, Int(ceil(geometry.size.width * displayScale * 1.5 / 256)) * 256))
        } action: { imagePixelWidth = $0 }
        .onGeometryChange(for: CGSize.self) { $0.size } action: {
            readerViewport = $0
            restoreWebtoonPositionIfReady()
        }
        .task { await loadPages() }
        .task(id: prefetchRequests) {
            let requests = prefetchRequests
            let pipeline = imagePipeline
            guard let current = requests.first else { return }
            _ = try? await pipeline.image(for: current)
            guard !Task.isCancelled else { return }
            await withTaskGroup(of: Void.self) { group in
                for request in requests.dropFirst() {
                    group.addTask { _ = try? await pipeline.image(for: request, prefetch: true) }
                }
            }
        }
        .onChange(of: currentChapter?.localPagesPath) { _, _ in useSavedPagesIfAvailable() }
        .onAppear {
            startSession()
            UIApplication.shared.isIdleTimerDisabled = true
            if forceLandscape { setLandscape(true) }
        }
        .onDisappear {
            autoScrollActive = false
            scrollController.cancelRestore()
            persistReadingState(endSession: true, syncRemote: false)
            let pipeline = imagePipeline
            Task { await pipeline.clear() }
            UIApplication.shared.isIdleTimerDisabled = false
            if forceLandscape { setLandscape(false) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { startSession() }
            else { autoScrollActive = false; persistReadingState(endSession: phase == .background, syncRemote: false) }
        }
        .onChange(of: readingMode) { _, _ in
            autoScrollActive = false; isZoomed = false
            scrollController.cancelRestore()
            webtoonPosition.reset()
            webtoonPosition.chapterID = currentChapter?.id
            scrolledPageID = currentPage
        }
        .onChange(of: showHUD) { _, visible in if visible { autoScrollActive = false } }
        .onChange(of: showSettings) { _, visible in if visible { autoScrollActive = false } }
        .onChange(of: showChapterList) { _, visible in if visible { autoScrollActive = false } }
        .sheet(isPresented: $showSettings, onDismiss: {
            autoScrollActive = false
            let sourceCount = pageSource.pageCount + appliedSkip
            let requestedSkip = min(max(0, comic.skipFirstNPages), max(0, sourceCount - 1))
            // Mode, brightness and orientation update in place. Reopening the
            // same source pages would unnecessarily replay an older saved anchor.
            if requestedSkip != appliedSkip { Task { await loadPages() } }
        }) {
            NavigationStack {
                ScrollView { settingsPanel }
                    .navigationTitle("Display settings").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { showSettings = false } }
                        ToolbarItem(placement: .cancellationAction) { Button("Reset") {
                            resumePageForLayout = currentPage
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
        let offsetSnapshot = scrollController.offsetSnapshot
        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(0..<pageSource.pageCount, id: \.self) { index in
                        pageView(index)
                            .id(index)
                            .onGeometryChange(for: ComicWebtoonFrame.self) {
                                ComicWebtoonFrame(rect: $0.frame(in: .named("comicWebtoonViewport")),
                                    scrollOffset: offsetSnapshot.offset)
                            } action: { frame in
                                recordWebtoonFrame(frame, page: index)
                            }
                    }
                }
                .scrollTargetLayout()
                .padding(.top, 70).padding(.bottom, 90)
                .background(ReaderScrollMonitor(controller: scrollController, reportsProgrammaticChanges: autoScrollActive, enabled: !autoScrollActive && !isZoomed && !isTransitioning && !showSettings && !showChapterList,
                    onPosition: { fraction in
                        webtoonPosition.atEnd = fraction >= 0.995
                        recordWebtoonMovement()
                        hideChromeAfterReadingScroll()
                        if fraction >= 0.999 { autoScrollActive = false }
                    },
                    onPull: { pullProgress = $0 },
                    onRelease: { next in if next { goToNextChapter() } else { goToPrevChapter() } },
                    onReady: webtoonScrollReady))
                .modifier(AutoScrollModifier(isActive: autoScrollActive && !showSettings && !showChapterList && scenePhase == .active, speed: autoScrollSpeed))
            }
            .coordinateSpace(name: "comicWebtoonViewport")
            .scrollBounceBehavior(.always, axes: .vertical)
            .scrollDisabled(isZoomed)
            .task(id: appliedSkip) {
                // One owner performs programmatic scrolling. A simultaneous
                // scrollPosition binding can reassert its page anchor after a
                // proxy jump or a precise UIKit pixel movement.
                webtoonPosition.isSourceAnchorReady = false
                await Task.yield()
                if resumePageForLayout == 0 {
                    webtoonPosition.isRestoring = true
                    scrollController.restoreToStart()
                    webtoonPosition.isRestoring = false
                    await Task.yield()
                } else {
                    await settleJump(to: resumePageForLayout) { proxy.scrollTo($0, anchor: .top) }
                }
                guard !Task.isCancelled else { return }
                webtoonPosition.isSourceAnchorReady = true
                restoreWebtoonPositionIfReady()
                adoptSettledPosition()
            }
            .onChange(of: pendingScrollToPage) { _, target in
                if let target {
                    // SwiftUI proxy jumps are intentionally excluded from the
                    // scroll monitor. Discard the previous pixel anchor here so
                    // Start chapter over and page selection resume at their target.
                    webtoonPosition.pending = nil
                    webtoonPosition.recorded = nil
                    webtoonPosition.lastReadingOffset = nil
                    scrollController.cancelRestore()
                    currentPage = target; pendingScrollToPage = nil
                    jumpTask?.cancel()
                    jumpTask = Task {
                        if target == 0 {
                            scrollController.restoreToStart()
                            try? await Task.sleep(for: .milliseconds(80))
                        } else {
                            await settleJump(to: target) { proxy.scrollTo($0, anchor: .top) }
                        }
                        guard !Task.isCancelled else { return }
                        adoptSettledPosition()
                    }
                }
            }
        }
    }

    @ViewBuilder private func pageView(_ index: Int) -> some View {
        ZoomablePageView(onSingleTap: toggleHUD, onZoom: { isZoomed = $0 }) {
            if let request = imageRequest(at: index) {
                ComicPageView(request: request, pipeline: imagePipeline, aspectRatio: pageAspectRatio(at: index), onImageReady: { ratio in
                    ComicPageRatios.shared[request.url] = ratio
                    guard readingMode == .webtoon else { return }
                    restoreWebtoonPositionIfReady()
                })
            }
        }
    }

    private static func pageURL(_ page: PageResponse) -> URL? {
        let path = page.filePath
        return URL(string: path.hasPrefix("https://") || path.hasPrefix("http://") ? path : AppConfig.staticBaseURL + path)
    }

    private func imageRequest(at index: Int) -> ComicImagePipeline.Request? {
        if let localPageURLs, localPageURLs.indices.contains(index) {
            return .init(url: localPageURLs[index], referrer: nil, pixelWidth: imagePixelWidth)
        }
        guard pages.indices.contains(index), let url = Self.pageURL(pages[index]) else { return nil }
        return .init(url: url, referrer: pageReferrer, pixelWidth: imagePixelWidth)
    }

    private var prefetchRequests: [ComicImagePipeline.Request] {
        ComicImagePipeline.prefetchIndices(page: currentPage, count: pageSource.pageCount).compactMap { imageRequest(at: $0) }
    }

    private func pageAspectRatio(at index: Int) -> CGFloat {
        if pages.indices.contains(index), let width = pages[index].widthPx, let height = pages[index].heightPx, height > 0 {
            return CGFloat(width) / CGFloat(height)
        }
        if let url = imageRequest(at: index)?.url, let ratio = ComicPageRatios.shared[url] { return ratio }
        return 2.0 / 3.0
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
                Text(currentChapter.map { ComicChapterLabel($0).heading } ?? "").font(.headline).lineLimit(1)
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
                    Button("Return to page \(page + appliedSkip + 1)") { jumpToPage(page); previousPageJump = nil }
                }
                Button("Start chapter over") {
                    currentPage = 0; scrolledPageID = 0
                    if readingMode == .webtoon { pendingScrollToPage = 0 }
                }
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
        VStack(spacing: 0) {
            if pageSource.pageCount > 1 { pageScrubber }
            HStack(spacing: 0) {
                Button { showChapterList = true } label: {
                    Label("Chapters", systemImage: "list.bullet").lineLimit(1).fixedSize()
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                Button { goToPrevChapter() } label: { Image(systemName: "chevron.backward").frame(width: 44, height: 44) }
                    .disabled(isFirstChapter || isTransitioning).accessibilityLabel("Previous chapter")
                Text("Page \(displayedPage + appliedSkip + 1) of \(pageSource.pageCount + appliedSkip)")
                    .font(.footnote).monospacedDigit().foregroundStyle(AstralColors.body).fixedSize()
                    .accessibilityLabel("Page \(displayedPage + appliedSkip + 1) of \(pageSource.pageCount + appliedSkip)")
                Button { goToNextChapter() } label: { Image(systemName: "chevron.forward").frame(width: 44, height: 44) }
                    .disabled(isLastChapter || isTransitioning).accessibilityLabel("Next chapter")
                Button("Display", systemImage: "slider.horizontal.3") { persistReadingState(endSession: false, syncRemote: false); showSettings = true }
                    .labelStyle(.iconOnly).accessibilityLabel("Display settings")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .trailing)
            }
        }
        .tint(AstralColors.gold)
        .padding(.horizontal, 16).padding(.vertical, 4).background(.regularMaterial)
    }

    private var displayedPage: Int { scrubPage.map { Int($0.rounded()) } ?? currentPage }

    /// Drag to preview the page number; the reader moves when the drag ends.
    private var pageScrubber: some View {
        Slider(value: Binding(get: { scrubPage ?? Double(currentPage) }, set: { scrubPage = $0 }),
               in: 0...Double(max(1, pageSource.pageCount - 1)), step: 1) { editing in
            guard !editing, let value = scrubPage else { return }
            scrubPage = nil
            jumpToPage(Int(value.rounded()))
        }
        .environment(\.layoutDirection, readingMode == .rightToLeft ? .rightToLeft : .leftToRight)
        .accessibilityLabel("Page")
        .accessibilityValue("\(displayedPage + appliedSkip + 1) of \(pageSource.pageCount + appliedSkip)")
        .padding(.top, 6)
    }

    private func jumpToPage(_ index: Int) {
        let target = min(max(0, index), max(0, pageSource.pageCount - 1))
        guard target != currentPage else { return }
        previousPageJump = currentPage
        currentPage = target; scrolledPageID = target
        if readingMode == .webtoon { pendingScrollToPage = target }
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
                    Text("Auto-scroll Speed")
                        .font(AstralTypography.captionMedium)
                        .foregroundStyle(AstralColors.muted)
                    Slider(value: $autoScrollSpeed, in: 0.5...5, step: 0.5).tint(AstralColors.gold).accessibilityLabel("Auto-scroll speed")
                    Text("Start or pause auto-scroll from ••• in the reader. It pauses when you open a sheet or leave Astral.")
                        .font(AstralTypography.caption).foregroundStyle(AstralColors.muted)
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
    private func goToPrevChapter() { if let previousChapterIndex { requestChapter(previousChapterIndex) } }
    private func goToNextChapter() { if let nextChapterIndex { requestChapter(nextChapterIndex) } }
    // MARK: - Bookmark

    private var isCurrentChapterBookmarked: Bool {
        guard let chapter = currentChapter else { return false }
        return bookmarks.contains { bookmarkMatches($0, chapter: chapter) }
    }

    private func bookmarkMatches(_ bookmark: LocalBookmark, chapter: LocalComicChapter) -> Bool {
        if let chapterID = BookmarkAnchorStore.chapter(for: bookmark.id) { return chapterID == chapter.id }
        return bookmark.chapterNumber == chapter.chapterNumber
    }

    private func bookmarkCurrentChapter() {
        guard let chapter = currentChapter else { return }
        if let existing = bookmarks.first(where: { bookmarkMatches($0, chapter: chapter) }) {
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
        let anchor = webtoonPosition.recorded
        let hasExactAnchor = readingMode == .webtoon && anchor?.page == currentPage && anchor?.signature == webtoonLayoutSignature
        ReadingPositionStore.save(.init(chapterID: chapter.id, chapterNumber: chapter.chapterNumber,
            page: currentPage + appliedSkip, offset: hasExactAnchor ? anchor?.offset : nil,
            layoutSignature: hasExactAnchor ? anchor?.signature : nil), story: comic.id)
        if endSession { readingSession?.endedAt = .now }
        try? modelContext.save()
    }

    private var webtoonLayoutSignature: String {
        // One decimal: layout passes report the same width as 402.0 and
        // 402.00000000000006, which must not invalidate a saved anchor.
        "comic-webtoon-page-v1/\(String(format: "%.1f", readerViewport.width))/\(String(format: "%.1f", readerViewport.height))/\(appliedSkip)/\(pageSource.pageCount)"
    }

    private func recordWebtoonFrame(_ frame: ComicWebtoonFrame, page: Int) {
        // Geometry can arrive before the UIKit probe attaches. Keep that frame;
        // attachment does not necessarily cause another geometry notification.
        var sample = frame
        if !webtoonPosition.isScrollReady { sample.scrollOffset = nil }
        if let previous = webtoonPosition.frames[page], abs(previous.rect.height - sample.rect.height) > 0.5 {
            // Geometry for the following pages arrives in the same pass; wait for
            // all of it before choosing the page being read.
            webtoonPosition.layoutSettling = true
            webtoonPosition.settleGeneration += 1
            let generation = webtoonPosition.settleGeneration
            Task { @MainActor in
                await Task.yield()
                guard webtoonPosition.settleGeneration == generation else { return }
                webtoonPosition.layoutSettling = false
            }
        }
        webtoonPosition.frames[page] = sample
        if let offset = sample.scrollOffset { keepReadingAnchor(page: page, contentTop: Double(sample.rect.minY) + offset) }
        restoreWebtoonPositionIfReady()
        captureWebtoonPosition()
    }

    /// Streamed pages often finish loading after the reader has scrolled past them.
    /// When a page above the one being read changes height, move the scroll offset by
    /// the same amount so the content under the reader's eyes stays still.
    private func keepReadingAnchor(page: Int, contentTop: Double) {
        let previous = webtoonPosition.contentTops[page]
        webtoonPosition.contentTops[page] = contentTop
        guard let previous, abs(contentTop - previous) > 0.5,
              let anchor = webtoonPosition.recorded, anchor.page == page,
              webtoonPosition.pending == nil, !webtoonPosition.isRestoring,
              !scrollController.isRestoringPosition, !isZoomed, !isTransitioning else { return }
        scrollController.shift(by: contentTop - previous)
        webtoonPosition.lastReadingOffset = scrollController.offset
    }

    /// `ScrollViewReader` positions unvisited pages from size estimates, and a
    /// streamed strip can be many screens taller than its estimate, so a jump can
    /// land several pages early or past the end. Measure where the target page
    /// actually is and correct until its top sits at the top of the viewport.
    private func settleJump(to target: Int, scroll: (Int) -> Void) async {
        scroll(target)
        for _ in 0..<12 {
            try? await Task.sleep(for: .milliseconds(70))
            guard !Task.isCancelled, readingMode == .webtoon, !scrollController.isUserScrolling else { return }
            guard let offset = scrollController.offset, let frame = webtoonPosition.frames[target],
                  frame.scrollOffset == offset else { scroll(target); continue }
            if abs(frame.rect.minY) < 1.5 { return }
            scrollController.jump(to: offset + Double(frame.rect.minY))
            // Clamped at the end of the chapter: the page top cannot move further.
            if scrollController.offset == offset { return }
        }
    }

    /// Page jumps are excluded from the scroll monitor. Once a jump has settled,
    /// adopt it as the reading position so anchoring protects it while pages load.
    private func adoptSettledPosition() {
        guard readingMode == .webtoon, webtoonPosition.pending == nil,
              webtoonPosition.isScrollReady, webtoonPosition.isSourceAnchorReady else { return }
        webtoonPosition.lastReadingOffset = scrollController.offset
        captureWebtoonPosition()
    }

    /// A deliberate forward read hides the controls; a tap brings them back.
    private func hideChromeAfterReadingScroll() {
        guard showHUD, !alwaysShowControls, !voiceOverEnabled, !showSettings, !showChapterList,
              let offset = scrollController.offset, scrollController.isUserScrolling else { chromeHideOrigin = nil; return }
        guard let origin = chromeHideOrigin, offset >= origin else { chromeHideOrigin = offset; return }
        if offset - origin > 140 {
            withAnimation(ReaderMotion.chrome) { showHUD = false }
            chromeHideOrigin = nil
        }
    }

    private func webtoonScrollReady() {
        guard let offset = scrollController.offset else { return }
        webtoonPosition.isScrollReady = true
        for (page, frame) in webtoonPosition.frames where frame.scrollOffset == nil {
            webtoonPosition.frames[page] = ComicWebtoonFrame(rect: frame.rect, scrollOffset: offset)
        }
        restoreWebtoonPositionIfReady()
    }

    private func recordWebtoonMovement() {
        guard webtoonPosition.isScrollReady, webtoonPosition.isSourceAnchorReady,
              !webtoonPosition.isRestoring, !scrollController.isRestoringPosition else { return }
        // A real drag or explicit scroll command takes precedence over a pending
        // restore, including while the requested image is still loading.
        webtoonPosition.pending = nil
        scrollController.cancelRestore()
        webtoonPosition.lastReadingOffset = scrollController.offset
        captureWebtoonPosition()
    }

    private func captureWebtoonPosition() {
        guard readingMode == .webtoon, webtoonPosition.isScrollReady, webtoonPosition.isSourceAnchorReady,
              !isZoomed, !webtoonPosition.isRestoring, !webtoonPosition.layoutSettling,
              webtoonPosition.pending == nil,
              let offset = scrollController.offset,
              offset == webtoonPosition.lastReadingOffset else { return }
        // Only use frames measured at this actual offset. Cached offscreen
        // geometry can be stale when a lazy stack changes its size estimates.
        let visible = webtoonPosition.frames.filter { _, frame in
            frame.scrollOffset == offset && frame.rect.maxY > 0 && frame.rect.minY < readerViewport.height
        }
        // A page that just finished loading reports its new height before the
        // pages after it report their new positions. Choosing from that mixed
        // set would move the reading anchor onto the page that grew.
        let ordered = visible.sorted { $0.key < $1.key }
        for (upper, lower) in zip(ordered, ordered.dropFirst()) where lower.key == upper.key + 1 {
            if abs(upper.value.rect.maxY - lower.value.rect.minY) > 1 { return }
        }
        // The page being read is the one under a line 40% down the screen, not
        // the tail of the previous page still showing behind the top bar.
        let line = readerViewport.height * 0.4
        let lastPage = pageSource.pageCount - 1
        // Until every visible page has reported this offset, the line may fall in
        // a page whose frame is still stale; keep the current page meanwhile.
        let chosen = webtoonPosition.atEnd && visible[lastPage] != nil
            ? (key: lastPage, value: visible[lastPage]!)
            : visible.first { $0.value.rect.minY <= line && $0.value.rect.maxY > line }
                ?? (webtoonPosition.recorded == nil ? visible.min { $0.value.rect.minY < $1.value.rect.minY } : nil)
        guard let (page, frame) = chosen else { return }
        currentPage = page
        webtoonPosition.recorded = (page, -Double(frame.rect.minY), webtoonLayoutSignature)
    }

    private func restoreWebtoonPositionIfReady() {
        guard readingMode == .webtoon, webtoonPosition.isScrollReady, webtoonPosition.isSourceAnchorReady,
              !isZoomed, let pending = webtoonPosition.pending,
              readerViewport.width > 0, readerViewport.height > 0 else { return }
        guard pending.signature == webtoonLayoutSignature else { webtoonPosition.pending = nil; return }
        guard let frame = webtoonPosition.frames[pending.page],
              let url = imageRequest(at: pending.page)?.url,
              let ratio = ComicPageRatios.shared[url], ratio > 0,
              abs(frame.rect.height - frame.rect.width / ratio) < 2,
              let offset = scrollController.offset, frame.scrollOffset == offset else { return }
        webtoonPosition.pending = nil
        webtoonPosition.isRestoring = true
        // The geometry may precede the latest scroll event. Account for that
        // delta before asking the controller to move to the saved point.
        let currentWithinPage = -Double(frame.rect.minY) + offset - (frame.scrollOffset ?? offset)
        scrollController.restore(offset: offset + pending.offset - currentWithinPage)
        webtoonPosition.isRestoring = false
        webtoonPosition.lastReadingOffset = scrollController.offset
        webtoonPosition.recorded = pending
        currentPage = pending.page
    }

    private struct ChapterPages {
        let network: [PageResponse]
        let local: [URL]?
        var count: Int { local?.count ?? network.count }
    }
    private func fetchPages(_ chapter: LocalComicChapter) async throws -> ChapterPages {
        let source = try await sourcePages(chapter)
        // Known sizes for saved and previously cached pages keep the strip from
        // reflowing as their images decode.
        await ComicPageRatios.shared.learn(source.local ?? source.network.compactMap(Self.pageURL))
        return source
    }
    private func sourcePages(_ chapter: LocalComicChapter) async throws -> ChapterPages {
        if let previewPages { return .init(network: previewPages, local: nil) }
        if let urls = ChapterDownloadService.shared.localPageURLs(for: chapter),
           !urls.isEmpty, chapter.totalPages == 0 || chapter.totalPages == urls.count {
            return .init(network: [], local: urls)
        }
        if let prepared = preparedNext, chapters.indices.contains(prepared.index), chapters[prepared.index].id == chapter.id,
           Date().timeIntervalSince(prepared.at) < 600 {
            return prepared.source
        }
        if comic.sourceKey == "mangadex-device" { return .init(network: try await MangaDexDeviceService.pages(chapter.id), local: nil) }
        if DeviceComicService.sources.contains(comic.sourceKey) { return .init(network: try await DeviceComicService.pages(comic: comic, chapter: chapter), local: nil) }
        guard comic.sourceKey != "local", AppConfig.companionEnabled else { throw APIError.companionUnavailable }
        let response: [PageResponse] = try await APIClient.shared.request(.chapterPages(comicId: comic.id, chapterId: chapter.id))
        guard !response.isEmpty else { throw APIError.notFound }
        return .init(network: response, local: nil)
    }

    /// Near the end of a streamed chapter, fetch the next chapter's page list and
    /// its first pages so a pull or Next opens without a wait.
    private func prepareNextChapterIfNeeded() {
        guard previewPages == nil, !isLoading, !isTransitioning, pageSource.pageCount > 0,
              currentPage >= pageSource.pageCount - 3, let index = nextChapterIndex,
              preparedNext?.index != index else { return }
        let chapter = chapters[index]
        guard ChapterDownloadService.shared.localPageURLs(for: chapter)?.isEmpty != false,
              comic.sourceKey == "mangadex-device" else { return }
        preparedNext = (index, .init(network: [], local: nil), .distantPast)
        let referrer = pageReferrer
        Task { @MainActor in
            // A failure keeps the empty placeholder: one attempt per chapter, so
            // retries can't queue ahead of the reader's own request when rate limited.
            guard let pages = try? await MangaDexDeviceService.pages(chapter.id), !pages.isEmpty else { return }
            guard preparedNext?.index == index else { return }
            preparedNext = (index, .init(network: pages, local: nil), .now)
            let skip = min(max(0, comic.skipFirstNPages), pages.count - 1)
            for url in pages.dropFirst(skip).prefix(2).compactMap(Self.pageURL) {
                await ComicImagePreparation.warm(url, referrer: referrer)
            }
        }
    }
    private func apply(_ source: ChapterPages, chapter: LocalComicChapter) {
        scrollController.cancelRestore()
        let skip = min(max(0, comic.skipFirstNPages), max(0, source.count - 1))
        let sameChapter = webtoonPosition.chapterID == chapter.id
        if !sameChapter || appliedSkip != skip {
            let wasScrollReady = webtoonPosition.isScrollReady
            let wasSourceAnchorReady = webtoonPosition.isSourceAnchorReady
            webtoonPosition.reset()
            // A skip change keeps the chapter's scroll view mounted; its probe
            // will not attach again just because the source-page indices change.
            if sameChapter {
                webtoonPosition.isScrollReady = wasScrollReady
                webtoonPosition.isSourceAnchorReady = wasSourceAnchorReady
            }
        } else {
            // Closing display settings can reload identical page requests; their
            // views then keep the same geometry and do not load their images again.
            webtoonPosition.pending = nil
            webtoonPosition.recorded = nil
            webtoonPosition.lastReadingOffset = nil
        }
        webtoonPosition.chapterID = chapter.id
        pageReferrer = UserDefaults.standard.string(forKey: "reading.chapterSource." + chapter.id.uuidString)
            ?? UserDefaults.standard.string(forKey: "reading.source." + comic.id.uuidString)
        appliedSkip = skip
        pages = Array(source.network.dropFirst(appliedSkip))
        localPageURLs = source.local.map { Array($0.dropFirst(appliedSkip)) }
        let saved = ReadingPositionStore.position(story: comic.id, chapter: chapter.id)
        let legacy = comic.lastReadChapterNumber == Int(chapter.chapterNumber) ? max(0, comic.lastReadPageNumber - 1) : 0
        currentPage = min(max(0, (saved?.page ?? legacy) - appliedSkip), max(0, source.count - appliedSkip - 1))
        if let bookmark = initialBookmark, !appliedInitialBookmark, bookmarkMatches(bookmark, chapter: chapter) {
            currentPage = min(max(0, (bookmark.pageNumber ?? 1) - appliedSkip - 1), max(0, source.count - appliedSkip - 1))
            appliedInitialBookmark = true
        } else if readingMode == .webtoon, let offset = saved?.offset, let signature = saved?.layoutSignature {
            webtoonPosition.pending = (currentPage, offset, signature)
            webtoonPosition.recorded = (currentPage, offset, signature)
        }
        resumePageForLayout = currentPage
        scrolledPageID = currentPage
        isZoomed = false; offlineError = false
        restoreWebtoonPositionIfReady()
    }
    private func loadPages() async {
        guard let chapter = currentChapter else { isLoading = false; return }
        do { let source = try await fetchPages(chapter); apply(source, chapter: chapter); loadErrorMessage = nil }
        catch {
            offlineError = (error as? URLError) != nil
            loadErrorMessage = error.localizedDescription
        }
        isLoading = false
    }
    private func useSavedPagesIfAvailable() {
        guard let chapter = currentChapter, chapter.downloadStatus == .complete,
              let urls = ChapterDownloadService.shared.localPageURLs(for: chapter),
              !urls.isEmpty, chapter.totalPages == 0 || chapter.totalPages == urls.count else { return }
        let saved = Array(urls.dropFirst(appliedSkip))
        guard saved != localPageURLs else { return }
        // Keep page IDs, scroll position and zoom state. Updating request URLs
        // cancels remote work and starts local preparation without reopening.
        localPageURLs = saved
    }
    private func saveCurrentChapter() {
        guard let chapter = currentChapter, !isSavingChapter, !chapter.isDownloaded else { return }
        isSavingChapter = true
        saveChapterTask = Task { @MainActor in
            saveError = await ChapterDownloadService.shared.downloadAllChapters(
                comic: comic, chapters: [chapter], modelContext: modelContext,
                onCancel: { saveChapterTask?.cancel() }, onProgress: { _, _ in }
            )
            if saveError == nil, currentChapter?.id == chapter.id { useSavedPagesIfAvailable() }
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
                preparedNext = nil
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
    let request: ComicImagePipeline.Request
    let pipeline: ComicImagePipeline
    let aspectRatio: CGFloat
    var onImageReady: (CGFloat) -> Void = { _ in }
    @State private var retryID = UUID()
    @State private var image: UIImage?
    @State private var measuredRatio: CGFloat?
    @State private var failed = false
    private struct LoadID: Hashable {
        let request: ComicImagePipeline.Request
        let retry: UUID
    }

    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else {
                // Keep the measured height while the image is released offscreen.
                Rectangle().fill(AstralColors.elevated.opacity(0.6)).aspectRatio(measuredRatio ?? aspectRatio, contentMode: .fit)
                    .overlay {
                        if failed {
                            VStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle").font(.title3)
                                Text("Page didn't load").font(.footnote)
                                Button("Retry") { retryID = UUID() }
                                    .buttonStyle(.bordered).tint(AstralColors.gold)
                            }
                            .foregroundStyle(AstralColors.muted)
                        } else { ProgressView().tint(AstralColors.gold) }
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .task(id: LoadID(request: request, retry: retryID)) {
            failed = false
            do {
                let prepared = try await pipeline.image(for: request)
                try Task.checkCancellation()
                let ratio = CGFloat(prepared.width) / CGFloat(prepared.height)
                measuredRatio = ratio
                image = UIImage(cgImage: prepared)
                onImageReady(ratio)
            } catch is CancellationError { } catch { if !Task.isCancelled { failed = true } }
        }
        .onDisappear { image = nil }
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
                        let label = ComicChapterLabel(chapter)
                        HStack(spacing: 12) {
                            // Chapter number pill
                            Text(label.number)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(index == currentIndex ? AstralColors.gold : AstralColors.body)
                                .frame(width: 44, alignment: .center)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(label.name ?? "Chapter \(label.number)")
                                    .font(AstralTypography.body)
                                    .foregroundStyle(index == currentIndex ? AstralColors.white : AstralColors.body)
                                    .lineLimit(1)
                                Text([chapter.totalPages > 0 ? "\(chapter.totalPages) pages" : nil, label.group].compactMap { $0 }.joined(separator: " · "))
                                    .font(AstralTypography.caption)
                                    .foregroundStyle(AstralColors.muted)
                                    .lineLimit(1)
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
