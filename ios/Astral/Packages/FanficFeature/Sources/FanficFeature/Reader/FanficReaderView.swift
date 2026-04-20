import SwiftUI
import SwiftData
import Core
import DesignSystem
import Networking

struct FanficReaderView: View {
    let fanfic: LocalFanfic
    let allChapters: [LocalFanficChapter]
    private let previewContent: String?

    @State private var currentChapter: LocalFanficChapter

    init(fanfic: LocalFanfic, chapters: [LocalFanficChapter], chapter: LocalFanficChapter, previewContent: String? = nil) {
        self.fanfic = fanfic
        self.allChapters = chapters
        self.previewContent = previewContent
        _currentChapter = State(initialValue: chapter)
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var chapterContent = ""
    @State private var isLoading = true
    @State private var showReaderBar = false
    @AppStorage("fanficReaderFontSize") private var fontSize: Double = 16
    @AppStorage("fanficReaderLineHeight") private var lineHeight: Double = 1.6
    @AppStorage("fanficReaderBackground") private var background: ReaderBackground = .dark
    @AppStorage("fanficReaderFontFamily") private var fontFamily: ReaderFont = .system
    @AppStorage("fanficReaderParagraphSpacing") private var paragraphSpacing: Double = 12
    @AppStorage("fanficReaderHorizontalMargin") private var horizontalMargin: Double = 20
    @State private var showBookmarkSheet = false
    @State private var bookmarkParagraphIndex: Int?
    @State private var showChapterList = false
    @State private var readingSession: LocalReadingSession?
    @State private var hasRestoredScroll = false
    @State private var scrollTargetIndex: Int?
    @State private var offlineError = false
    @State private var horizontalPage: String? = "current"

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .tint(AstralColors.gold)
                    .scaleEffect(1.2)
            } else if offlineError && chapterContent.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "cloud.slash")
                        .font(.system(size: 44))
                        .foregroundStyle(AstralColors.muted)
                    Text("Chapter not available offline")
                        .font(AstralTypography.body)
                        .foregroundStyle(AstralColors.body)
                    Text("Download this chapter or connect to read")
                        .font(AstralTypography.caption)
                        .foregroundStyle(AstralColors.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Horizontal paging: prev chapter | current chapter | next chapter
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        // Previous chapter placeholder
                        if let prev = previousChapter {
                            chapterPlaceholder(chapter: prev, direction: "Previous Chapter", icon: "chevron.left")
                                .containerRelativeFrame([.horizontal, .vertical])
                                .id("prev")
                        }

                        // Current chapter — vertical scroll content
                        ScrollViewReader { proxy in
                            ScrollView {
                                VStack(alignment: .leading, spacing: paragraphSpacing) {
                                    // Chapter header
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Chapter \(currentChapter.chapterNumber, specifier: "%.0f")")
                                            .font(fontFamily.font(size: fontSize * 0.75))
                                            .tracking(1.5)
                                            .textCase(.uppercase)
                                            .foregroundStyle(AstralColors.muted)

                                        if let title = currentChapter.title {
                                            Text(title)
                                                .font(fontFamily.boldFont(size: fontSize * 1.2))
                                                .foregroundStyle(textColor)
                                        }


                                    }
                                    .padding(.bottom, 8)

                                    // Divider between header and content
                                    HStack(spacing: 8) {
                                        Rectangle().fill(AstralColors.muted.opacity(0.3)).frame(height: 0.5)
                                        Image(systemName: "diamond.fill")
                                            .font(.system(size: 5))
                                            .foregroundStyle(AstralColors.muted.opacity(0.5))
                                        Rectangle().fill(AstralColors.muted.opacity(0.3)).frame(height: 0.5)
                                    }
                                    .padding(.bottom, 4)

                                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                                        if isSceneBreak(paragraph) {
                                            // Scene break — centered ornament
                                            HStack {
                                                Spacer()
                                                Text("* * *")
                                                    .font(fontFamily.font(size: fontSize))
                                                    .tracking(6)
                                                    .foregroundStyle(AstralColors.muted.opacity(0.6))
                                                Spacer()
                                            }
                                            .padding(.vertical, 8)
                                            .id(index)
                                        } else {
                                            Text(paragraph)
                                                .font(fontFamily.font(size: fontSize))
                                                .lineSpacing((lineHeight - 1.0) * fontSize)
                                                .foregroundStyle(textColor)
                                                .id(index)
                                                .onAppear {
                                                    guard hasRestoredScroll else { return }
                                                    if paragraphs.count > 1 {
                                                        fanfic.scrollOffsetPercent = Double(index) / Double(paragraphs.count - 1)
                                                    }
                                                }
                                                .simultaneousGesture(
                                                    LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                                                        bookmarkParagraphIndex = index
                                                        showBookmarkSheet = true
                                                    }
                                                )
                                        }
                                    }

                                    // Chapter navigation footer
                                    chapterNavigationFooter
                                }
                                .padding(.horizontal, horizontalMargin)
                                .padding(.vertical, 20)
                                .animation(AstralAnimation.quick, value: fontSize)
                                .animation(AstralAnimation.quick, value: lineHeight)
                                .animation(AstralAnimation.quick, value: horizontalMargin)
                                .padding(.bottom, 100)
                            }
                            .onAppear {
                                guard !hasRestoredScroll else { return }
                                if let target = scrollTargetIndex {
                                    proxy.scrollTo(target, anchor: .top)
                                    hasRestoredScroll = true
                                } else {
                                    hasRestoredScroll = true
                                }
                            }
                            .onChange(of: scrollTargetIndex) { _, newTarget in
                                guard !hasRestoredScroll, let target = newTarget else { return }
                                proxy.scrollTo(target, anchor: .top)
                                hasRestoredScroll = true
                            }
                        }
                        .containerRelativeFrame([.horizontal, .vertical])
                        .id("current")

                        // Next chapter placeholder
                        if let next = nextChapter {
                            chapterPlaceholder(chapter: next, direction: "Next Chapter", icon: "chevron.right")
                                .containerRelativeFrame([.horizontal, .vertical])
                                .id("next")
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $horizontalPage)
                .onChange(of: horizontalPage) { _, newPage in
                    guard let newPage, newPage != "current" else { return }
                    if newPage == "prev", let prev = previousChapter {
                        horizontalPage = "current"
                        navigateTo(prev)
                    } else if newPage == "next", let next = nextChapter {
                        horizontalPage = "current"
                        navigateTo(next)
                    }
                }
            }

            // Reading progress bar — always visible
            VStack {
                GeometryReader { geo in
                    Rectangle()
                        .fill(AstralColors.gold.opacity(0.6))
                        .frame(
                            width: geo.size.width * (fanfic.scrollOffsetPercent ?? 0),
                            height: 2.5
                        )
                        .animation(AstralAnimation.micro, value: fanfic.scrollOffsetPercent)
                }
                .frame(height: 2.5)
                Spacer()
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Top bar — slides in from above with reader bar
            VStack(spacing: 0) {
                fanficTopBar
                Spacer()
            }
            .offset(y: showReaderBar ? 0 : -110)
            .opacity(showReaderBar ? 1 : 0)
            .animation(.easeInOut(duration: 0.22), value: showReaderBar)
            .allowsHitTesting(showReaderBar)

            // Chapter + favourite overlay — top right
            if showReaderBar {
                chapterFavOverlay
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 56)
                    .padding(.trailing, 16)
                    .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .topTrailing)))
                    .allowsHitTesting(showReaderBar)
            }

            // Reader settings bar — spring slide from bottom
            if showReaderBar {
                VStack {
                    Spacer()
                    readerSettingsBar
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

        }
        .onTapGesture {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                showReaderBar.toggle()
            }
        }
        .task(id: currentChapter.id) { await loadChapter() }
        .onAppear {
            // Track reading session
            let session = LocalReadingSession(contentType: "fanfic", storyId: fanfic.id)
            modelContext.insert(session)
            // Persist reading progress
            fanfic.lastReadChapterNumber = currentChapter.chapterNumber
            fanfic.lastReadAt = .now
            if fanfic.totalChapters > 0 {
                fanfic.progressPercent = (fanfic.lastReadChapterNumber ?? 0) / Double(fanfic.totalChapters)
                if fanfic.progressPercent >= 1.0 && fanfic.completedAt == nil {
                    fanfic.completedAt = .now
                }
            }
            try? modelContext.save()
            readingSession = session
            // Sync progress to backend
            Task {
                let body = FanficProgressRequest(
                    lastChapterNumber: Int(currentChapter.chapterNumber),
                    scrollOffsetPercent: fanfic.scrollOffsetPercent
                )
                let _: ProgressResponse? = try? await APIClient.shared.request(
                    .updateFanficProgress(storyId: fanfic.id, body: body)
                )
            }
        }
        .onDisappear {
            // Save final scroll position to backend
            if let readingSession {
                readingSession.endedAt = .now
                Task {
                    let body = FanficProgressRequest(
                        lastChapterNumber: Int(fanfic.lastReadChapterNumber ?? 0),
                        scrollOffsetPercent: fanfic.scrollOffsetPercent
                    )
                    let _: ProgressResponse? = try? await APIClient.shared.request(
                        .updateFanficProgress(storyId: fanfic.id, body: body)
                    )
                }
                try? modelContext.save()
            }
        }
        .sheet(isPresented: $showBookmarkSheet) {
            FanficBookmarkSheet(
                paragraphText: bookmarkParagraphIndex.flatMap { paragraphs.indices.contains($0) ? paragraphs[$0] : nil } ?? "",
                chapterTitle: currentChapter.title,
                chapterNumber: currentChapter.chapterNumber,
                wordOffset: bookmarkParagraphIndex.flatMap { wordOffsetForParagraph($0) } ?? 0,
                onSave: { selectedText, heading, wordOffset in
                    let bookmark = LocalBookmark(
                        contentType: "fanfic",
                        storyId: fanfic.id,
                        chapterNumber: currentChapter.chapterNumber,
                        wordOffset: wordOffset,
                        selectedText: selectedText,
                        heading: heading
                    )
                    modelContext.insert(bookmark)
                    try? modelContext.save()
                }
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showChapterList) {
            FanficChapterListSheet(
                chapters: allChapters,
                currentChapterId: currentChapter.id,
                onSelect: { chapter in
                    showChapterList = false
                    navigateTo(chapter)
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var backgroundColor: Color {
        switch background {
        case .dark:  AstralColors.readerDark
        case .sepia: AstralColors.readerSepia
        case .paper: AstralColors.readerPaper
        }
    }

    private var textColor: Color {
        switch background {
        case .dark:  AstralColors.body
        case .sepia: Color(hex: 0xD4C5A9)
        case .paper: Color(hex: 0x2C2C2C)
        }
    }

    private var chapterFavOverlay: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 58, height: 58)
                VStack(spacing: 1) {
                    Text(chapterDisplayNum)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(AstralColors.white)
                        .monospacedDigit()
                    Capsule()
                        .fill(AstralColors.muted)
                        .frame(width: 22, height: 1.5)
                        .rotationEffect(.degrees(-45))
                    Text("\(fanfic.totalChapters)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AstralColors.muted)
                        .monospacedDigit()
                }
            }

            Button {
                showChapterList = true
            } label: {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 44, height: 44)
                    Image(systemName: "list.bullet")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AstralColors.white)
                }
            }
            .buttonStyle(PressButtonStyle(scale: 0.88))

            Button {
                withAnimation(AstralAnimation.bouncy) {
                    fanfic.isFavorite.toggle()
                    try? modelContext.save()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 44, height: 44)
                    Image(systemName: fanfic.isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(fanfic.isFavorite ? AstralColors.error : AstralColors.white)
                        .symbolEffect(.bounce, value: fanfic.isFavorite)
                }
            }
            .buttonStyle(PressButtonStyle(scale: 0.88))
        }
    }

    // MARK: - Top Bar

    private var fanficTopBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AstralColors.white)
            }
            .buttonStyle(PressButtonStyle(scale: 0.88))
            .accessibilityIdentifier(AccessibilityID.readerBackButton)

            Text(fanfic.title)
                .font(AstralTypography.bodyMedium)
                .foregroundStyle(AstralColors.white)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 56)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
    }

    private var chapterDisplayNum: String {
        let n = currentChapter.chapterNumber
        return n.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(n))" : String(format: "%.1f", n)
    }

    private var readerSettingsBar: some View {
        VStack(spacing: 16) {
            // Font size
            HStack {
                Text("Aa")
                    .font(.system(size: 14))
                    .foregroundStyle(AstralColors.muted)
                    .frame(width: 24)
                Slider(value: $fontSize, in: 12...28)
                    .tint(AstralColors.gold)
                Text("Aa")
                    .font(.system(size: 22))
                    .foregroundStyle(AstralColors.muted)
                    .frame(width: 32)
            }

            // Line height
            HStack {
                Image(systemName: "text.line.first.and.arrowtriangle.forward")
                    .foregroundStyle(AstralColors.muted)
                    .frame(width: 24)
                Slider(value: $lineHeight, in: 1.2...2.2)
                    .tint(AstralColors.gold)
            }

            // Font family
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ReaderFont.allCases, id: \.self) { font in
                        Button {
                            withAnimation(AstralAnimation.bouncy) { fontFamily = font }
                        } label: {
                            Text(font.rawValue)
                                .font(font.font(size: 13))
                                .foregroundStyle(fontFamily == font ? AstralColors.gold : AstralColors.body)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(fontFamily == font ? AstralColors.gold.opacity(0.15) : AstralColors.elevated)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Paragraph spacing
            HStack {
                Image(systemName: "text.alignleft")
                    .foregroundStyle(AstralColors.muted)
                    .frame(width: 24)
                Slider(value: $paragraphSpacing, in: 0...36)
                    .tint(AstralColors.gold)
                Text("\(Int(paragraphSpacing))pt")
                    .font(AstralTypography.caption)
                    .foregroundStyle(AstralColors.muted)
                    .frame(width: 32)
            }

            // Horizontal margins
            HStack {
                Image(systemName: "arrow.left.and.right")
                    .foregroundStyle(AstralColors.muted)
                    .frame(width: 24)
                Slider(value: $horizontalMargin, in: 8...48)
                    .tint(AstralColors.gold)
                Text("\(Int(horizontalMargin))pt")
                    .font(AstralTypography.caption)
                    .foregroundStyle(AstralColors.muted)
                    .frame(width: 32)
            }

            // Background picker — animated ring selection
            HStack(spacing: 16) {
                ForEach(ReaderBackground.allCases, id: \.self) { bg in
                    Button {
                        withAnimation(AstralAnimation.bouncy) {
                            background = bg
                        }
                    } label: {
                        Circle()
                            .fill(bgPreviewColor(bg))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Circle()
                                    .stroke(AstralColors.gold, lineWidth: 2.5)
                                    .opacity(background == bg ? 1 : 0)
                                    .scaleEffect(background == bg ? 1 : 0.6)
                                    .animation(AstralAnimation.bouncy, value: background)
                            )
                    }
                    .buttonStyle(PressButtonStyle(scale: 0.88))
                }
                Spacer()
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
    }

    private func bgPreviewColor(_ bg: ReaderBackground) -> Color {
        switch bg {
        case .dark:  AstralColors.readerDark
        case .sepia: AstralColors.readerSepia
        case .paper: AstralColors.readerPaper
        }
    }

    private var paragraphs: [String] {
        chapterContent
            .components(separatedBy: "\n\n")
            .map { block in
                // Collapse stray single newlines within a paragraph to spaces.
                // Scraped content may contain \n from inline HTML tags (<em>, <br>, etc.)
                // that should not cause mid-paragraph line breaks.
                block.replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
    }

    private func isSceneBreak(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = ["---", "***", "* * *", "—", "~~~", "- - -", "•••", "⁂", "oOo", "xxx", "XXX"]
        return patterns.contains(trimmed) || (trimmed.count <= 10 && trimmed.allSatisfy { $0 == "-" || $0 == "*" || $0 == "~" || $0 == " " })
    }

    private func wordOffsetForParagraph(_ index: Int) -> Int {
        paragraphs.prefix(index)
            .reduce(0) { $0 + $1.split(separator: " ").count }
    }

    private func loadChapter() async {
        AstralLogger.info("loadChapter: ch \(currentChapter.chapterNumber) (id=\(currentChapter.id)) for '\(fanfic.title)'", context: "FanficReader")
        offlineError = false

        if let previewContent {
            chapterContent = previewContent
            calculateScrollTarget()
            isLoading = false
            return
        }

        // 1. Try local file first (offline reading)
        if let localPath = currentChapter.localTextPath {
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(localPath)
            if let content = try? String(contentsOf: url, encoding: .utf8), !content.isEmpty {
                chapterContent = content
                AstralLogger.info("loadChapter: loaded \(content.count) chars from local file", context: "FanficReader")
                calculateScrollTarget()
                isLoading = false
                return
            } else {
                // File missing or corrupt — reset download state
                currentChapter.downloadStatus = .none
                currentChapter.localTextPath = nil
                currentChapter.isDownloaded = false
                try? modelContext.save()
                AstralLogger.warning("loadChapter: local file missing/corrupt, falling through to network", context: "FanficReader")
            }
        }

        // 2. Try network
        do {
            let response: FanficChapterResponse = try await APIClient.shared.request(
                .fanficChapter(fanficId: fanfic.id, chapterId: currentChapter.id)
            )
            guard !Task.isCancelled else { return }
            chapterContent = response.content ?? ""
            AstralLogger.info("loadChapter: got \(chapterContent.count) chars from network", context: "FanficReader")
        } catch {
            guard !Task.isCancelled else { return }
            // 3. Both local and network failed
            chapterContent = ""
            offlineError = true
            AstralLogger.error("loadChapter failed: \(error)", context: "FanficReader")
        }

        calculateScrollTarget()
        isLoading = false
    }

    private var chapterNavigationFooter: some View {
        VStack(spacing: 16) {
            // End-of-chapter divider
            HStack(spacing: 8) {
                Rectangle().fill(AstralColors.muted.opacity(0.3)).frame(height: 0.5)
                Image(systemName: "diamond.fill")
                    .font(.system(size: 5))
                    .foregroundStyle(AstralColors.muted.opacity(0.5))
                Rectangle().fill(AstralColors.muted.opacity(0.3)).frame(height: 0.5)
            }
            .padding(.top, 24)

            HStack(spacing: 12) {
                // Previous chapter
                if let prev = previousChapter {
                    Button {
                        navigateTo(prev)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 12, weight: .semibold))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Previous")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(AstralColors.muted)
                                Text(chapterLabel(prev))
                                    .font(AstralTypography.captionMedium)
                                    .lineLimit(1)
                            }
                        }
                        .foregroundStyle(AstralColors.body)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AstralColors.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(PressButtonStyle(scale: 0.95))
                } else {
                    Spacer().frame(maxWidth: .infinity)
                }

                // Next chapter
                if let next = nextChapter {
                    Button {
                        navigateTo(next)
                    } label: {
                        HStack(spacing: 6) {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Next")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(AstralColors.muted)
                                Text(chapterLabel(next))
                                    .font(AstralTypography.captionMedium)
                                    .lineLimit(1)
                            }
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(AstralColors.body)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .background(AstralColors.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(PressButtonStyle(scale: 0.95))
                } else {
                    Spacer().frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func chapterPlaceholder(chapter: LocalFanficChapter, direction: String, icon: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(AstralColors.gold)
            Text(direction)
                .font(AstralTypography.bodyMedium)
                .foregroundStyle(AstralColors.white)
            Text(chapterLabel(chapter))
                .font(AstralTypography.caption)
                .foregroundStyle(AstralColors.muted)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundColor)
    }

    private func chapterLabel(_ ch: LocalFanficChapter) -> String {
        let num = ch.chapterNumber
        let formatted = num.truncatingRemainder(dividingBy: 1) == 0 ? "Ch. \(Int(num))" : "Ch. \(num)"
        if let title = ch.title, !title.isEmpty {
            return "\(formatted): \(title)"
        }
        return formatted
    }

    private func calculateScrollTarget() {
        guard let pct = fanfic.scrollOffsetPercent, pct > 0,
              currentChapter.chapterNumber == (fanfic.lastReadChapterNumber ?? 0),
              !paragraphs.isEmpty else { return }
        scrollTargetIndex = min(Int(pct * Double(paragraphs.count - 1)), paragraphs.count - 1)
        AstralLogger.info("scrollTarget: paragraph \(scrollTargetIndex ?? -1) of \(paragraphs.count) (pct=\(pct))", context: "FanficReader")
    }

    // MARK: - Chapter Navigation

    private var previousChapter: LocalFanficChapter? {
        guard let idx = allChapters.firstIndex(where: { $0.id == currentChapter.id }), idx > 0 else { return nil }
        return allChapters[idx - 1]
    }

    private var nextChapter: LocalFanficChapter? {
        guard let idx = allChapters.firstIndex(where: { $0.id == currentChapter.id }), idx < allChapters.count - 1 else { return nil }
        return allChapters[idx + 1]
    }

    private func navigateTo(_ chapter: LocalFanficChapter) {
        // Save current position
        try? modelContext.save()
        // Reset reader state synchronously before triggering reload
        chapterContent = ""
        isLoading = true
        hasRestoredScroll = false
        scrollTargetIndex = nil
        bookmarkParagraphIndex = nil
        horizontalPage = "current"
        // Update reading progress
        fanfic.lastReadChapterNumber = chapter.chapterNumber
        fanfic.scrollOffsetPercent = nil
        fanfic.lastReadAt = .now
        if fanfic.totalChapters > 0 {
            fanfic.progressPercent = (fanfic.lastReadChapterNumber ?? 0) / Double(fanfic.totalChapters)
        }
        try? modelContext.save()
        // Changing currentChapter triggers .task(id:) to re-fire
        currentChapter = chapter
    }
}

// MARK: - Chapter List Sheet

private struct FanficChapterListSheet: View {
    let chapters: [LocalFanficChapter]
    let currentChapterId: UUID
    let onSelect: (LocalFanficChapter) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List(chapters, id: \.id) { chapter in
                    let isCurrent = chapter.id == currentChapterId
                    Button {
                        onSelect(chapter)
                    } label: {
                        HStack(spacing: 12) {
                            Text(chapterNum(chapter))
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(isCurrent ? AstralColors.gold : AstralColors.body)
                                .frame(width: 40, alignment: .center)

                            VStack(alignment: .leading, spacing: 2) {
                                if let title = chapter.title, !title.isEmpty {
                                    Text(title)
                                        .font(AstralTypography.body)
                                        .foregroundStyle(isCurrent ? AstralColors.white : AstralColors.body)
                                        .lineLimit(1)
                                }
                                if let wc = chapter.wordCount, wc > 0 {
                                    Text("\(wc.formatted()) words · \(max(1, wc / 238)) min")
                                        .font(AstralTypography.caption)
                                        .foregroundStyle(AstralColors.muted)
                                }
                            }

                            Spacer()

                            if isCurrent {
                                Image(systemName: "book.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(AstralColors.gold)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(
                        isCurrent
                            ? AstralColors.gold.opacity(0.1)
                            : Color.clear
                    )
                    .id(chapter.id)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(AstralColors.background)
                .onAppear {
                    proxy.scrollTo(currentChapterId, anchor: .center)
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

    private func chapterNum(_ ch: LocalFanficChapter) -> String {
        ch.chapterNumber.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(ch.chapterNumber))"
            : String(format: "%.1f", ch.chapterNumber)
    }
}

// MARK: - Bookmark Sheet

private struct FanficBookmarkSheet: View {
    let paragraphText: String
    let chapterTitle: String?
    let chapterNumber: Double
    let wordOffset: Int
    let onSave: (String, String?, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var heading: String = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Bookmark this passage")
                    .font(AstralTypography.bodyMedium)
                    .foregroundStyle(AstralColors.white)

                Text(snippetText)
                    .font(AstralTypography.caption)
                    .foregroundStyle(AstralColors.body)
                    .lineLimit(4)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AstralColors.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                TextField("Heading (optional)", text: $heading)
                    .textFieldStyle(.plain)
                    .font(AstralTypography.body)
                    .foregroundColor(AstralColors.white)
                    .tint(AstralColors.gold)
                    .padding(12)
                    .background(AstralColors.elevated, in: RoundedRectangle(cornerRadius: 8))

                Spacer()
            }
            .padding(16)
            .background(AstralColors.background)
            .scrollContentBackground(.hidden)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AstralColors.muted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(
                            snippetText,
                            heading.isEmpty ? chapterTitle : heading,
                            wordOffset
                        )
                        dismiss()
                    }
                    .foregroundStyle(AstralColors.gold)
                }
            }
            .onAppear {
                heading = chapterTitle ?? ""
            }
        }
    }

    private var snippetText: String {
        let words = paragraphText.split(separator: " ")
        let preview = words.prefix(20).joined(separator: " ")
        return words.count > 20 ? preview + "…" : preview
    }
}

// MARK: - Previews

#Preview("Reader - Dark") {
    FanficReaderView(
        fanfic: PreviewMocks.fanfic1,
        chapters: PreviewMocks.fanfic1Chapters,
        chapter: PreviewMocks.fanfic1Chapters[1],
        previewContent: PreviewMocks.sampleFanficChapterContent
    )
}

#Preview("Reader - Sepia") {
    FanficReaderView(
        fanfic: PreviewMocks.fanfic2,
        chapters: PreviewMocks.fanfic1Chapters,
        chapter: PreviewMocks.fanfic1Chapters[2],
        previewContent: PreviewMocks.sampleFanficChapterContent
    )
}

#Preview("Reader - No Content") {
    FanficReaderView(
        fanfic: PreviewMocks.fanfic3,
        chapters: PreviewMocks.fanfic1Chapters,
        chapter: PreviewMocks.fanfic1Chapters[4],
        previewContent: ""
    )
}
