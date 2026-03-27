import SwiftUI
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

    @State private var currentChapterIndex: Int
    @State private var pages: [PageResponse] = []
    @State private var currentPage: Int = 0          // 0-indexed
    @State private var isLoading = true
    @State private var showHUD = false
    @State private var showSettings = false
    @State private var readingMode: ReadingMode = .webtoon
    @State private var brightnessOverlay: Double = 0.0  // 0 = none, 0.7 = dark
    @State private var showPageActions = false
    @State private var longPressedPage: PageResponse?

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
    }

    private var currentChapter: LocalComicChapter? { chapters[safe: currentChapterIndex] }
    private var isFirstChapter: Bool { currentChapterIndex <= 0 }
    private var isLastChapter:  Bool { currentChapterIndex >= chapters.count - 1 }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Page content
            if isLoading {
                ProgressView().tint(AstralColors.gold)
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

            // Brightness overlay (above pages, below tap zones)
            if brightnessOverlay > 0 {
                Color.black
                    .opacity(brightnessOverlay)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // Tap zones + long press (above pages)
            if !isLoading && !pages.isEmpty {
                tapZoneOverlay
            }

            // HUD (topmost)
            if showHUD {
                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    if showSettings {
                        settingsPanel
                    } else {
                        bottomBar
                    }
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.15), value: showSettings)
            }
        }
        .ignoresSafeArea()
        .navigationBarHidden(true)
        .statusBarHidden(!showHUD)
        .task(id: currentChapterIndex) { await loadPages() }
        .onAppear   { UIApplication.shared.isIdleTimerDisabled = true  }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
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
        return TabView(selection: $currentPage) {
            ForEach(Array(orderedPages.enumerated()), id: \.element.id) { index, page in
                ComicPageView(page: page)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    // MARK: - Tap Zones

    private var tapZoneOverlay: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                // Left zone
                Color.clear
                    .frame(width: geo.size.width / 3)
                    .contentShape(Rectangle())
                    .onTapGesture { handleLeftTap() }

                // Center zone — toggle HUD
                Color.clear
                    .frame(width: geo.size.width / 3)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showHUD.toggle()
                            if !showHUD { showSettings = false }
                        }
                    }

                // Right zone
                Color.clear
                    .frame(width: geo.size.width / 3)
                    .contentShape(Rectangle())
                    .onTapGesture { handleRightTap() }
            }
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            longPressedPage = pages[safe: currentPage]
            showPageActions = true
        }
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
        withAnimation(.easeInOut(duration: 0.15)) {
            showHUD.toggle()
            if !showHUD { showSettings = false }
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
                        if let title = chapter.title {
                            Text("— \(title)")
                                .font(AstralTypography.body)
                                .foregroundStyle(AstralColors.muted)
                                .lineLimit(1)
                        }
                    }
                }
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showSettings.toggle()
                }
            } label: {
                Image(systemName: showSettings ? "xmark" : "slider.horizontal.3")
                    .font(.body.weight(.medium))
                    .foregroundStyle(AstralColors.white)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 56) // status bar clearance
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 10) {
            // Page slider (paged modes only — in webtoon, scrolling is the primary navigation)
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

            // Chapter nav + page counter
            HStack {
                Button {
                    goToPrevChapter()
                } label: {
                    Label("Prev", systemImage: "chevron.left")
                        .font(AstralTypography.captionMedium)
                        .foregroundStyle(isFirstChapter ? AstralColors.muted : AstralColors.gold)
                }
                .disabled(isFirstChapter)

                Spacer()

                Text("\(currentPage + 1) / \(pages.count)")
                    .font(AstralTypography.captionMedium)
                    .foregroundStyle(AstralColors.white)
                    .monospacedDigit()

                Spacer()

                Button {
                    goToNextChapter()
                } label: {
                    Label("Next", systemImage: "chevron.right")
                        .labelStyle(.titleAndIcon)
                        .font(AstralTypography.captionMedium)
                        .foregroundStyle(isLastChapter ? AstralColors.muted : AstralColors.gold)
                }
                .disabled(isLastChapter)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 34) // home indicator clearance
        .background(.ultraThinMaterial)
    }

    // MARK: - Settings Panel

    private var settingsPanel: some View {
        VStack(spacing: 20) {
            // Reading mode
            VStack(alignment: .leading, spacing: 10) {
                Text("Reading Mode")
                    .font(AstralTypography.captionMedium)
                    .foregroundStyle(AstralColors.muted)

                HStack(spacing: 8) {
                    ForEach(ReadingMode.allCases, id: \.self) { mode in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
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
                            .background(
                                readingMode == mode
                                    ? AstralColors.gold.opacity(0.15)
                                    : AstralColors.elevated
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
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
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 34)
        .background(.ultraThinMaterial)
    }

    // MARK: - Page Navigation

    private func prevPage() {
        if currentPage > 0 {
            currentPage -= 1
        } else {
            goToPrevChapter()
        }
    }

    private func nextPage() {
        if currentPage < pages.count - 1 {
            currentPage += 1
        } else {
            goToNextChapter()
        }
    }

    private func goToPrevChapter() {
        guard !isFirstChapter else { return }
        currentChapterIndex -= 1
        currentPage = 0
    }

    private func goToNextChapter() {
        guard !isLastChapter else { return }
        currentChapterIndex += 1
        currentPage = 0
    }

    // MARK: - Long Press Actions

    private func saveCurrentPage() {
        // TODO: Fetch image from staticBaseURL + page.filePath and save to Photos
    }

    private func shareCurrentPage() {
        // TODO: Fetch image from staticBaseURL + page.filePath and present UIActivityViewController
    }

    // MARK: - Loading

    private func loadPages() async {
        isLoading = true
        pages = []
        currentPage = 0

        guard let chapter = currentChapter else { isLoading = false; return }

        if let previewPages {
            pages = previewPages
            isLoading = false
            return
        }

        do {
            let response: [PageResponse] = try await APIClient.shared.request(
                .chapterPages(comicId: comic.id, chapterId: chapter.id)
            )
            pages = response
        } catch {
            // pages stays empty → shows empty state
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
