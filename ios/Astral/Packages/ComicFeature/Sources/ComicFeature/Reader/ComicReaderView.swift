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

// MARK: - Main View

struct ComicReaderView: View {
    let comic: LocalComic
    let chapters: [LocalComicChapter]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var currentChapterIndex: Int
    @State private var pages: [PageResponse] = []
    @State private var currentPage: Int = 0
    @State private var isLoading = true
    @State private var showHUD = false
    @State private var showSettings = false
    @AppStorage("comicReaderMode") private var readingMode: ReadingMode = .webtoon
    @AppStorage("comicReaderBrightness") private var brightnessOverlay: Double = 0.0
    @State private var showPageActions = false
    @State private var longPressedPage: PageResponse?
    @Query private var bookmarks: [LocalBookmark]
    @State private var nextChapterPull: CGFloat = 0
    @State private var nextChapterTriggered = false
    @State private var atBottomOfChapter = false
    @State private var scrolledPageID: Int? = 0  // drives paged scroll position
    @State private var showRotateHint = false
    @AppStorage("hideRotateHint") private var hideRotateHint = false
    @AppStorage("forceLandscape") private var forceLandscape = true
    @State private var readingSession: LocalReadingSession?
    @State private var localPageURLs: [URL]?
    @State private var prevChapterPull: CGFloat = 0
    @State private var prevChapterTriggered = false

    // Namespaces for matched geometry
    @Namespace private var modeNS

    private let previewPages: [PageResponse]?

    init(
        comic: LocalComic,
        chapters: [LocalComicChapter],
        startingAt chapter: LocalComicChapter,
        previewPages: [PageResponse]? = nil
    ) {
        self.comic = comic
        self.chapters = chapters
        self.previewPages = previewPages
        let idx = chapters.firstIndex(where: { $0.id == chapter.id }) ?? 0
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

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Page content
            if isLoading {
                ProgressView()
                    .tint(AstralColors.gold)
                    .scaleEffect(1.2)
            } else if pages.isEmpty {
                EmptyStateView(
                    icon: "photo.on.rectangle.angled",
                    title: "No Pages",
                    message: "This chapter hasn't been scraped yet."
                )
                .foregroundStyle(AstralColors.white)
            } else {
                pageContent
            }

            // Brightness overlay
            if brightnessOverlay > 0 {
                Color.black
                    .opacity(brightnessOverlay)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // No overlay here — gestures are on the page content directly

            // Floating back button — always visible as escape hatch
            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .padding(.leading, 16)
                    .padding(.top, 54)
                    .opacity(showHUD ? 0 : 0.6)
                    Spacer()
                }
                Spacer()
            }
            .allowsHitTesting(!showHUD)

            // Top HUD — slides in from above
            VStack(spacing: 0) {
                topBar
                Spacer()
            }
            .offset(y: showHUD ? 0 : -110)
            .opacity(showHUD ? 1 : 0)
            .animation(.easeInOut(duration: 0.22), value: showHUD)
            .allowsHitTesting(showHUD)

            // Chapter + favourite overlay — top right, below the top bar
            VStack(spacing: 8) {
                chapterFavOverlay
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.top, 110)
            .padding(.trailing, 16)
            .offset(y: showHUD ? 0 : -110)
            .opacity(showHUD ? 1 : 0)
            .animation(.easeInOut(duration: 0.22), value: showHUD)
            .allowsHitTesting(showHUD)

            // Bottom HUD — slides in from below, swaps between settings and nav bar
            VStack(spacing: 0) {
                Spacer()
                ZStack(alignment: .bottom) {
                    if showSettings {
                        settingsPanel
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .trailing).combined(with: .opacity)
                            ))
                    } else {
                        bottomBar
                            .transition(.asymmetric(
                                insertion: .opacity,
                                removal: .opacity
                            ))
                    }
                }
                .animation(.spring(response: 0.38, dampingFraction: 0.85), value: showSettings)
            }
            .offset(y: showHUD ? 0 : 130)
            .opacity(showHUD ? 1 : 0)
            .animation(.easeInOut(duration: 0.22), value: showHUD)
            .allowsHitTesting(showHUD)
        }
        .ignoresSafeArea()
        .navigationBarHidden(true)
        .statusBarHidden(!showHUD)
        .task(id: currentChapterIndex) { await loadPages() }
        .onAppear {
            let session = LocalReadingSession(contentType: "comic", storyId: comic.id)
            modelContext.insert(session)
            try? modelContext.save()
            readingSession = session
            UIApplication.shared.isIdleTimerDisabled = true
            if forceLandscape {
                setLandscape(true)
            } else if !hideRotateHint, UIDevice.current.orientation.isPortrait || !UIDevice.current.orientation.isValidInterfaceOrientation {
                withAnimation { showRotateHint = true }
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation { showRotateHint = false }
                }
            }
        }
        .onDisappear {
            if let readingSession {
                readingSession.endedAt = .now
                try? modelContext.save()
            }
            UIApplication.shared.isIdleTimerDisabled = false
            if forceLandscape { setLandscape(false) }
        }
        .overlay(alignment: .top) {
            if showRotateHint {
                HStack(spacing: 8) {
                    Image(systemName: "rotate.right")
                    Text("Rotate for best reading experience")
                }
                .font(AstralTypography.caption)
                .foregroundStyle(AstralColors.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .padding(.top, 60)
                .onTapGesture {
                    withAnimation { showRotateHint = false }
                    hideRotateHint = true
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .confirmationDialog(
            "Page \(currentPage + 1)",
            isPresented: $showPageActions,
            titleVisibility: .visible
        ) {
            Button("Save to Photos") { saveCurrentPage() }
            Button("Share")          { shareCurrentPage() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Chapter / Favourite Overlay

    private var chapterFavOverlay: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 58, height: 58)
                VStack(spacing: 1) {
                    Text("\(currentChapterIndex + 1)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(AstralColors.white)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(AstralAnimation.quick, value: currentChapterIndex)
                    Capsule()
                        .fill(AstralColors.muted)
                        .frame(width: 22, height: 1.5)
                        .rotationEffect(.degrees(-45))
                    Text("\(chapters.count)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AstralColors.muted)
                        .monospacedDigit()
                }
            }

            Button {
                withAnimation(AstralAnimation.bouncy) {
                    comic.isFavorite.toggle()
                    try? modelContext.save()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 44, height: 44)
                    Image(systemName: comic.isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(comic.isFavorite ? AstralColors.error : AstralColors.white)
                        .symbolEffect(.bounce, value: comic.isFavorite)
                }
            }
            .buttonStyle(PressButtonStyle(scale: 0.88))
        }
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
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                // Previous chapter pull trigger at top of scroll content
                if !isFirstChapter {
                    PrevChapterTrigger(
                        onProgressChange: { progress in
                            prevChapterPull = progress
                            if progress >= 1.0 && !prevChapterTriggered {
                                prevChapterTriggered = true
                                let generator = UIImpactFeedbackGenerator(style: .medium)
                                generator.impactOccurred()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    goToPrevChapter()
                                    prevChapterTriggered = false
                                    prevChapterPull = 0
                                }
                            }
                        },
                        progress: prevChapterPull
                    )
                }

                if let localURLs = localPageURLs, !localURLs.isEmpty {
                    // Device-saved pages — load from local files
                    ForEach(Array(localURLs.enumerated()), id: \.offset) { index, url in
                        LocalPageView(fileURL: url)
                            .id(index)
                            .onAppear { currentPage = index; comic.lastReadPageNumber = index + 1 }
                    }
                } else {
                    // Network pages
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                        ComicPageView(page: page)
                            .id(index)
                            .onAppear { currentPage = index; comic.lastReadPageNumber = index + 1 }
                    }
                }

                // Next chapter pull trigger at bottom of scroll content
                if !isLastChapter {
                    NextChapterTrigger(
                        onProgressChange: { progress in
                            nextChapterPull = progress
                            if progress >= 1.0 && !nextChapterTriggered {
                                nextChapterTriggered = true
                                let generator = UIImpactFeedbackGenerator(style: .medium)
                                generator.impactOccurred()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    goToNextChapter()
                                    nextChapterTriggered = false
                                    nextChapterPull = 0
                                }
                            }
                        },
                        progress: nextChapterPull
                    )
                }
            }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                toggleHUD()
            }
        )
    }

    private func pagedReader(reversed: Bool) -> some View {
        let orderedPages = reversed ? pages.reversed() as [PageResponse] : pages
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(Array(orderedPages.enumerated()), id: \.element.id) { index, page in
                    ComicPageView(page: page)
                        .containerRelativeFrame(.horizontal)
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content
                                .opacity(phase.isIdentity ? 1.0 : 0.78)
                                .scaleEffect(phase.isIdentity ? 1.0 : 0.94)
                        }
                        .id(index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: Binding(
            get: { scrolledPageID },
            set: { newID in
                guard let id = newID, id != currentPage else { return }
                scrolledPageID = id
                currentPage = id
            }
        ))
        .onChange(of: currentPage) { _, new in
            guard scrolledPageID != new else { return }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                scrolledPageID = new
            }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                toggleHUD()
            }
        )
    }

    // MARK: - Tap Zones

    private var tapZoneOverlay: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                Rectangle()
                    .fill(.clear)
                    .frame(width: geo.size.width / 3)
                    .onTapGesture { handleLeftTap() }

                Rectangle()
                    .fill(.clear)
                    .frame(width: geo.size.width / 3)
                    .onTapGesture { toggleHUD() }

                Rectangle()
                    .fill(.clear)
                    .frame(width: geo.size.width / 3)
                    .onTapGesture { handleRightTap() }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                    longPressedPage = pages[safe: currentPage]
                    showPageActions = true
                }
            )
        }
        .allowsHitTesting(true)
    }

    private func handleLeftTap() {
        switch readingMode {
        case .webtoon:     toggleHUD()
        case .leftToRight: prevPage()
        case .rightToLeft: nextPage()
        }
    }

    private func handleRightTap() {
        switch readingMode {
        case .webtoon:     toggleHUD()
        case .leftToRight: nextPage()
        case .rightToLeft: prevPage()
        }
    }

    private func toggleHUD() {
        showHUD.toggle()
        if !showHUD { showSettings = false }
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
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AstralColors.white)
            }
            .buttonStyle(PressButtonStyle(scale: 0.88))

            VStack(alignment: .leading, spacing: 2) {
                Text(comic.title)
                    .font(AstralTypography.caption)
                    .foregroundStyle(AstralColors.muted)
                    .lineLimit(1)
                if let chapter = currentChapter {
                    HStack(spacing: 4) {
                        Text("Ch. \(chapter.chapterNumber, specifier: chapter.chapterNumber.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f")")
                            .font(AstralTypography.bodyMedium)
                            .foregroundStyle(AstralColors.white)
                            .contentTransition(.numericText())
                        if let title = chapter.title {
                            Text("— \(title)")
                                .font(AstralTypography.body)
                                .foregroundStyle(AstralColors.muted)
                                .lineLimit(1)
                        }
                    }
                    .animation(AstralAnimation.quick, value: currentChapterIndex)
                }
            }

            Spacer()

            Button {
                bookmarkCurrentChapter()
            } label: {
                Image(systemName: isCurrentChapterBookmarked ? "bookmark.fill" : "bookmark")
                    .font(.body.weight(.medium))
                    .foregroundStyle(isCurrentChapterBookmarked ? AstralColors.gold : AstralColors.white)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(PressButtonStyle(scale: 0.88))

            Button {
                withAnimation(AstralAnimation.snappy) { showSettings.toggle() }
            } label: {
                Image(systemName: showSettings ? "xmark" : "slider.horizontal.3")
                    .contentTransition(.symbolEffect(.replace))
                    .font(.body.weight(.medium))
                    .foregroundStyle(AstralColors.white)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(PressButtonStyle(scale: 0.88))
        }
        .padding(.horizontal, 16)
        .padding(.top, 56)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if readingMode != .webtoon && pages.count > 1 {
                HStack(spacing: 10) {
                    Text("1")
                        .font(AstralTypography.caption)
                        .foregroundStyle(AstralColors.muted)
                        .frame(minWidth: 24, alignment: .trailing)

                    Slider(
                        value: Binding(
                            get: { Double(currentPage) },
                            set: { currentPage = Int($0.rounded()) }
                        ),
                        in: 0...Double(pages.count - 1),
                        step: 1
                    )
                    .tint(AstralColors.gold)

                    Text("\(pages.count)")
                        .font(AstralTypography.caption)
                        .foregroundStyle(AstralColors.muted)
                        .frame(minWidth: 24, alignment: .leading)
                }
                .padding(.horizontal, 4)
            }

            HStack {
                Button { goToPrevChapter() } label: {
                    Label("Prev", systemImage: "chevron.left")
                        .font(AstralTypography.captionMedium)
                        .foregroundStyle(isFirstChapter ? AstralColors.muted : AstralColors.gold)
                }
                .disabled(isFirstChapter)
                .buttonStyle(PressButtonStyle(scale: 0.9))

                Spacer()

                Text("\(currentPage + 1) / \(pages.count)")
                    .font(AstralTypography.captionMedium)
                    .foregroundStyle(AstralColors.white)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(AstralAnimation.quick, value: currentPage)

                Spacer()

                Button { goToNextChapter() } label: {
                    Label("Next", systemImage: "chevron.right")
                        .labelStyle(.titleAndIcon)
                        .font(AstralTypography.captionMedium)
                        .foregroundStyle(isLastChapter ? AstralColors.muted : AstralColors.gold)
                }
                .disabled(isLastChapter)
                .buttonStyle(PressButtonStyle(scale: 0.9))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 34)
        .background(.ultraThinMaterial)
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
                                readingMode = mode
                                currentPage = 0
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
                    Image(systemName: "sun.min.fill")
                        .foregroundStyle(AstralColors.muted)
                    Slider(value: $brightnessOverlay, in: 0...0.75)
                        .tint(AstralColors.gold)
                    Image(systemName: "sun.max.fill")
                        .foregroundStyle(AstralColors.muted)
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
        .padding(.bottom, 34)
        .background(.ultraThinMaterial)
    }

    // MARK: - Page Navigation

    private func prevPage() {
        if currentPage > 0 { currentPage -= 1 } else { goToPrevChapter() }
    }

    private func nextPage() {
        if currentPage < pages.count - 1 { currentPage += 1 } else { goToNextChapter() }
    }

    private func goToPrevChapter() {
        guard !isFirstChapter else { return }
        withAnimation(AstralAnimation.quick) {
            currentChapterIndex -= 1
            currentPage = 0
        }
    }

    private func goToNextChapter() {
        guard !isLastChapter else { return }
        withAnimation(AstralAnimation.quick) {
            currentChapterIndex += 1
            currentPage = 0
        }
    }

    // MARK: - Bookmark

    private var isCurrentChapterBookmarked: Bool {
        guard let chapter = currentChapter else { return false }
        return bookmarks.contains { $0.chapterNumber == chapter.chapterNumber }
    }

    private func bookmarkCurrentChapter() {
        guard let chapter = currentChapter else { return }
        if let existing = bookmarks.first(where: { $0.chapterNumber == chapter.chapterNumber }) {
            modelContext.delete(existing)
            AstralLogger.info("Bookmark removed: ch \(chapter.chapterNumber)", context: "ComicReader")
        } else {
            let bookmark = LocalBookmark(
                contentType: "comic",
                storyId: comic.id,
                chapterNumber: chapter.chapterNumber,
                pageNumber: currentPage + 1,
                heading: chapter.title ?? "Chapter \(Int(chapter.chapterNumber))"
            )
            modelContext.insert(bookmark)
            AstralLogger.info("Bookmark added: ch \(chapter.chapterNumber) page \(currentPage + 1)", context: "ComicReader")
        }
        try? modelContext.save()
    }

    // MARK: - Long Press Actions

    private func saveCurrentPage() {}
    private func shareCurrentPage() {}

    // MARK: - Loading

    private func applyPageSkip(_ allPages: [PageResponse]) -> [PageResponse] {
        guard comic.skipFirstNPages > 0 else { return allPages }
        return Array(allPages.dropFirst(comic.skipFirstNPages))
    }

    private func loadPages() async {
        isLoading = true
        pages = []

        // Restore page position if resuming same chapter, otherwise start at 0
        let resumeChapterNumber = Int(currentChapter?.chapterNumber ?? 0)
        let savedPage = (comic.lastReadChapterNumber == resumeChapterNumber && comic.lastReadPageNumber > 0)
            ? comic.lastReadPageNumber - 1  // convert 1-based to 0-based
            : 0
        currentPage = savedPage
        scrolledPageID = savedPage

        guard let chapter = currentChapter else {
            AstralLogger.warning("loadPages: no currentChapter at index \(currentChapterIndex)", context: "ComicReader")
            isLoading = false
            return
        }

        AstralLogger.info("loadPages: chapter \(chapter.chapterNumber) (id=\(chapter.id)) for comic '\(comic.title)'", context: "ComicReader")

        // Persist reading progress
        comic.lastReadChapterNumber = Int(chapter.chapterNumber)
        comic.lastReadAt = .now
        if comic.totalChapters > 0 {
            comic.progressPercent = Double(comic.lastReadChapterNumber) / Double(comic.totalChapters)
            if comic.progressPercent >= 1.0 && comic.completedAt == nil {
                comic.completedAt = .now
            }
        }
        readingSession?.chaptersRead += 1
        try? modelContext.save()

        // Sync progress to backend (fire-and-forget)
        Task {
            let body = ComicProgressRequest(
                lastChapterNumber: Int(chapter.chapterNumber),
                lastPageNumber: currentPage + 1
            )
            let _: ProgressResponse? = try? await APIClient.shared.request(
                .updateComicProgress(storyId: comic.id, body: body)
            )
        }

        if let previewPages {
            pages = previewPages
            localPageURLs = nil
            isLoading = false
            return
        }

        // Try local files first (device-saved chapter)
        if let urls = ChapterDownloadService.shared.localPageURLs(for: chapter), !urls.isEmpty {
            localPageURLs = urls
            pages = []  // empty — webtoon reader will use localPageURLs directly
            AstralLogger.info("loadPages: using \(urls.count) local pages", context: "ComicReader")
            isLoading = false
            return
        }

        localPageURLs = nil
        do {
            let response: [PageResponse] = try await APIClient.shared.request(
                .chapterPages(comicId: comic.id, chapterId: chapter.id)
            )
            pages = applyPageSkip(response)
            AstralLogger.info("loadPages: got \(pages.count) pages", context: "ComicReader")
        } catch {
            AstralLogger.error("loadPages failed: \(error)", context: "ComicReader")
        }
        isLoading = false
    }
}

// MARK: - Page View

struct ComicPageView: View {
    let page: PageResponse
    @State private var retryID = UUID()

    var body: some View {
        AsyncImage(url: pageURL) { phase in
            switch phase {
            case .empty:
                Rectangle()
                    .fill(AstralColors.elevated)
                    .aspectRatio(aspectRatio, contentMode: .fit)
                    .overlay { ProgressView().tint(AstralColors.gold) }

            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
                    .transition(.opacity)

            case .failure:
                Rectangle()
                    .fill(AstralColors.elevated)
                    .aspectRatio(aspectRatio, contentMode: .fit)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "arrow.clockwise.circle")
                                .font(.title2)
                            Text("Tap to retry")
                                .font(AstralTypography.caption)
                        }
                        .foregroundStyle(AstralColors.muted)
                    }
                    .onTapGesture { retryID = UUID() }

            @unknown default:
                EmptyView()
            }
        }
        .id(retryID)
        .frame(maxWidth: .infinity)
    }

    private var pageURL: URL? {
        URL(string: AppConfig.staticBaseURL + page.filePath)
    }

    private var aspectRatio: CGFloat {
        if let w = page.widthPx, let h = page.heightPx, h > 0 {
            return CGFloat(w) / CGFloat(h)
        }
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

// MARK: - Helpers

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Chapter Triggers

private let chapterTriggerHeight: CGFloat = 260

/// Placed at the top of webtoon scroll content — scroll up to load previous chapter.
private struct PrevChapterTrigger: View {
    let onProgressChange: (CGFloat) -> Void
    let progress: CGFloat

    var body: some View {
        GeometryReader { geo in
            let frame = geo.frame(in: .global)
            // How much the trigger is pulled down below the top edge
            let visible = max(0, frame.maxY)
            let pct = min(visible / chapterTriggerHeight, 1.0)
            Color.clear
                .onChange(of: pct) { _, newPct in
                    onProgressChange(newPct)
                }
        }
        .frame(height: chapterTriggerHeight)
        .overlay {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(AstralColors.muted.opacity(0.3), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(AstralColors.gold, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.1), value: progress)

                    Image(systemName: progress >= 1.0 ? "checkmark" : "chevron.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(progress >= 1.0 ? AstralColors.gold : AstralColors.muted)
                }
                .frame(width: 28, height: 28)

                Text(progress >= 1.0 ? "Loading prev..." : "Previous chapter")
                    .font(AstralTypography.caption)
                    .foregroundStyle(AstralColors.muted)
            }
            .opacity(progress > 0.02 ? 1 : 0.3)
        }
    }
}

/// Placed at the bottom of webtoon scroll content — scroll down to load next chapter.
private struct NextChapterTrigger: View {
    let onProgressChange: (CGFloat) -> Void
    let progress: CGFloat

    var body: some View {
        GeometryReader { geo in
            let frame = geo.frame(in: .global)
            let screenH = UIScreen.main.bounds.height
            let visible = max(0, screenH - frame.minY)
            let pct = min(visible / chapterTriggerHeight, 1.0)
            Color.clear
                .onChange(of: pct) { _, newPct in
                    onProgressChange(newPct)
                }
        }
        .frame(height: chapterTriggerHeight)
        .overlay {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(AstralColors.muted.opacity(0.3), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(AstralColors.gold, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.1), value: progress)

                    Image(systemName: progress >= 1.0 ? "checkmark" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(progress >= 1.0 ? AstralColors.gold : AstralColors.muted)
                }
                .frame(width: 28, height: 28)

                Text(progress >= 1.0 ? "Loading next..." : "Next chapter")
                    .font(AstralTypography.caption)
                    .foregroundStyle(AstralColors.muted)
            }
            .opacity(progress > 0.02 ? 1 : 0.3)
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
