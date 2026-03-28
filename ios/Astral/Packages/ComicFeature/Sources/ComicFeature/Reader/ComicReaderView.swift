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
    @State private var readingMode: ReadingMode = .webtoon
    @State private var brightnessOverlay: Double = 0.0
    @State private var showPageActions = false
    @State private var longPressedPage: PageResponse?
    @State private var scrolledPageID: Int? = 0  // drives paged scroll position
    @State private var showRotateHint = false
    @AppStorage("hideRotateHint") private var hideRotateHint = false

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
        _readingMode = State(initialValue: comic.sourceKey == "nhentai" ? .rightToLeft : .webtoon)
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

            // Tap zones + long press
            if !isLoading && !pages.isEmpty {
                tapZoneOverlay
            }

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
            UIApplication.shared.isIdleTimerDisabled = true
            if !hideRotateHint, UIDevice.current.orientation.isPortrait || !UIDevice.current.orientation.isValidInterfaceOrientation {
                withAnimation { showRotateHint = true }
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation { showRotateHint = false }
                }
            }
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
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
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                    ComicPageView(page: page)
                        .id(index)
                        .onAppear { currentPage = index }
                }
            }
        }
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
    }

    // MARK: - Tap Zones

    private var tapZoneOverlay: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: geo.size.width / 3)
                    .contentShape(Rectangle())
                    .onTapGesture { handleLeftTap() }

                Color.clear
                    .frame(width: geo.size.width / 3)
                    .contentShape(Rectangle())
                    .onTapGesture { toggleHUD() }

                Color.clear
                    .frame(width: geo.size.width / 3)
                    .contentShape(Rectangle())
                    .onTapGesture { handleRightTap() }
            }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                longPressedPage = pages[safe: currentPage]
                showPageActions = true
            }
        )
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
                    Image(systemName: "sun.max.fill")
                        .foregroundStyle(AstralColors.muted)
                    Slider(value: $brightnessOverlay, in: 0...0.75)
                        .tint(AstralColors.gold)
                    Image(systemName: "sun.min.fill")
                        .foregroundStyle(AstralColors.muted)
                }
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
        currentPage = 0
        scrolledPageID = 0

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
        }
        try? modelContext.save()

        if let previewPages {
            pages = previewPages
            isLoading = false
            return
        }

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
                            Image(systemName: "photo.badge.exclamationmark")
                                .font(.title2)
                            Text("Failed to load")
                                .font(AstralTypography.caption)
                        }
                        .foregroundStyle(AstralColors.muted)
                    }

            @unknown default:
                EmptyView()
            }
        }
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

// MARK: - Helpers

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
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
