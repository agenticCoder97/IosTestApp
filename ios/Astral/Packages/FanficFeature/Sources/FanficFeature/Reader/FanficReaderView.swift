import SwiftUI
import SwiftData
import Core
import DesignSystem
import Networking

struct FanficReaderView: View {
    let fanfic: LocalFanfic
    let allChapters: [LocalFanficChapter]
    private let initialBookmark: LocalBookmark?
    @State private var appliedInitialBookmark = false
    private let previewContent: String?

    @State private var currentChapter: LocalFanficChapter

    init(fanfic: LocalFanfic, chapters: [LocalFanficChapter], chapter: LocalFanficChapter, previewContent: String? = nil, bookmark: LocalBookmark? = nil) {
        self.initialBookmark = bookmark
        self.fanfic = fanfic
        self.allChapters = chapters
        self.previewContent = previewContent
        _currentChapter = State(initialValue: chapter)
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.fanficNavigation) private var fanficNavigation
    @Environment(\.openURL) private var openURL

    @State private var chapterContent = ""
    @State private var preparedChapter = FanficReaderDocument(text: "")
    @State private var scrollProgress = FanficScrollProgress()
    @State private var isLoading = true
    @State private var showReaderBar = true
    @State private var showReaderSettings = false
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

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @AppStorage("readerAlwaysShowControls") private var alwaysShowControls = false
    @State private var viewportWidth: CGFloat = 0
    @State private var didRestoreAnchor = false
    @State private var pendingLayoutSignature: String?
    @State private var pendingPixelOffset: Double?
    @State private var visibleParagraph: Int?
    @State private var scrollController = ReaderScrollController()
    @State private var pullProgress = 0.0
    @State private var isTransitioning = false
    @State private var transitionError: String?
    @State private var failedChapter: LocalFanficChapter?
    @State private var previousJump: LocalFanficChapter?
    @State private var hideOrigin: Double?

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()
            if isLoading {
                ProgressView("Opening chapter…").tint(AstralColors.gold)
            } else if offlineError && chapterContent.isEmpty {
                ContentUnavailableView {
                    Label("Chapter unavailable", systemImage: "book.closed")
                } description: {
                    Text(["ao3", "ffnet"].contains(fanfic.sourceKey) ? "Return to the story and update from its source to restore the saved chapter." : "Save this chapter with a connected companion, then try again.")
                } actions: {
                    Button("Try again") { Task { await loadChapter() } }
                    Button("Back") { dismiss() }
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: paragraphSpacing) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Chapter \(chapterDisplayNum)").font(.subheadline).foregroundStyle(textColor.opacity(0.75))
                                // Untitled chapters are saved as "Chapter N"; don't print the heading twice.
                                if let title = currentChapter.title, title.caseInsensitiveCompare("Chapter \(chapterDisplayNum)") != .orderedSame {
                                    Text(title).font(fontFamily.boldFont(size: fontSize * 1.2)).foregroundStyle(textColor)
                                }
                            }
                            .padding(.bottom, 16)
                            ForEach(paragraphs.indices, id: \.self) { index in
                                let paragraph = paragraphs[index]
                                let isBreak = preparedChapter.sceneBreaks.contains(index)
                                let centered = isBreak || FanficTextMarks.isCentered(paragraph)
                                Text(isBreak ? AttributedString("* * *") : FanficTextMarks.styled(paragraph, font: fontFamily, size: fontSize))
                                    .font(fontFamily.font(size: fontSize))
                                    .lineSpacing((lineHeight - 1) * fontSize)
                                    .foregroundStyle(textColor)
                                    .multilineTextAlignment(centered ? .center : .leading)
                                    .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
                                    .id(index)
                                    .onTapGesture { toggleControls() }
                                    .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                                        bookmarkParagraphIndex = index; showBookmarkSheet = true
                                    })
                                    .accessibilityAction(named: "Bookmark passage") {
                                        bookmarkParagraphIndex = index; showBookmarkSheet = true
                                    }
                            }
                        }
                        .scrollTargetLayout()
                        .padding(.horizontal, horizontalMargin)
                        .padding(.top, 80)
                        .padding(.bottom, 90)
                        // Gaps between paragraphs, margins and the chapter end also
                        // toggle the controls; paragraph taps are handled above.
                        .contentShape(Rectangle())
                        .onTapGesture { toggleControls() }
                        .background(ReaderScrollMonitor(controller: scrollController, enabled: !isTransitioning && !showReaderSettings && !showChapterList,
                            onPosition: { fraction in
                                guard hasRestoredScroll else { return }
                                scrollProgress.fraction = fraction
                                scrollProgress.offset = scrollController.offset
                                scrollProgress.paragraph = visibleParagraph ?? 0
                                scrollProgress.layoutSignature = layoutSignature
                                hideControlsAfterReadingScroll()
                            }, onPull: { progress in
                                // No hint past the first or last chapter, where a release does nothing.
                                pullProgress = (progress > 0 ? nextChapter : previousChapter) == nil ? 0 : progress
                            }, onRelease: { next in
                                if let chapter = next ? nextChapter : previousChapter { navigateTo(chapter) }
                            }))
                    }
                    .scrollBounceBehavior(.always, axes: .vertical)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { viewportWidth = $0; restorePixelsIfCompatible() }
                    .scrollPosition(id: $visibleParagraph, anchor: .top)
                    .task(id: currentChapter.id) {
                        await Task.yield()
                        if let target = scrollTargetIndex {
                            if target == 0 { scrollController.restoreToStart() }
                            else { proxy.scrollTo(target, anchor: .top) }
                        }
                        await Task.yield()
                        didRestoreAnchor = true
                        restorePixelsIfCompatible()
                        hasRestoredScroll = true
                        // A chapter that fits on one screen never scrolls, so the readout
                        // would stay at 0%. Once it has laid out, it has been read in full.
                        try? await Task.sleep(for: .milliseconds(300))
                        if !Task.isCancelled, scrollController.contentFitsViewport { scrollProgress.fraction = 1 }
                    }
                    .id(currentChapter.id)
                    .onChange(of: scrollTargetIndex) { _, target in
                        if let target {
                            if target == 0 { scrollController.restoreToStart() }
                            else { proxy.scrollTo(target, anchor: .top) }
                        }
                    }
                }
            }
            safeAreaFade
            VStack(spacing: 0) {
                if controlsVisible { fanficTopBar.transition(.move(edge: .top).combined(with: .opacity)) }
                Spacer()
                if pullProgress != 0 { ReaderPullHint(progress: pullProgress).padding(.bottom, controlsVisible ? 16 : 40) }
                if controlsVisible { fanficBottomBar.transition(.move(edge: .bottom).combined(with: .opacity)) }
            }
            if isTransitioning { ProgressView("Opening chapter…").padding().background(.regularMaterial, in: Capsule()) }
        }
        .overlay(alignment: .bottom) { BookmarkUndoBanner().padding(.bottom, 70) }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(!controlsVisible)
        .persistentSystemOverlays(controlsVisible ? .automatic : .hidden)
        .task { await loadChapter() }
        .onAppear { startSession() }
        .onDisappear { persistReadingState(endSession: true, syncRemote: false) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { startSession() }
            else { persistReadingState(endSession: phase == .background, syncRemote: false) }
        }
        .sheet(isPresented: $showReaderSettings) {
            NavigationStack {
                ScrollView { fanficSettingsPanel }
                    .navigationTitle("Reading settings").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { showReaderSettings = false } }
                        ToolbarItem(placement: .cancellationAction) { Button("Reset") {
                            fontSize = 16; lineHeight = 1.6; paragraphSpacing = 12; horizontalMargin = 20; fontFamily = .system; background = .dark
                        } }
                    }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showBookmarkSheet) {
            FanficBookmarkSheet(
                paragraphText: bookmarkParagraphIndex.flatMap { paragraphs.indices.contains($0) ? FanficTextMarks.plain(paragraphs[$0]) : nil } ?? "",
                chapterTitle: currentChapter.title, chapterNumber: currentChapter.chapterNumber,
                wordOffset: bookmarkParagraphIndex.map { wordOffsetForParagraph($0) } ?? 0,
                onSave: { selectedText, heading, wordOffset in
                    let bookmark = LocalBookmark(contentType: "fanfic", storyId: fanfic.id,
                        chapterNumber: currentChapter.chapterNumber, scrollPercent: scrollProgress.fraction,
                        wordOffset: wordOffset, selectedText: selectedText, heading: heading)
                    modelContext.insert(bookmark)
                    BookmarkAnchorStore.save(bookmark: bookmark.id, chapter: currentChapter.id)
                    do { try modelContext.save(); Haptics.play(.bookmark) }
                    catch { transitionError = "Bookmark could not be saved: \(error.localizedDescription)" }
                })
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showChapterList) {
            FanficChapterListSheet(chapters: allChapters, currentChapterId: currentChapter.id, onSelect: { chapter in
                showChapterList = false; previousJump = currentChapter; navigateTo(chapter)
            }).presentationDetents([.medium, .large])
        }
        .alert("Chapter could not be opened", isPresented: Binding(get: { transitionError != nil }, set: { if !$0 { transitionError = nil } })) {
            if let failedChapter { Button("Retry") { navigateTo(failedChapter) } }
            Button("Keep reading", role: .cancel) { transitionError = nil }
            Button("Back") { dismiss() }
        } message: { Text(transitionError ?? "") }
    }

    private var controlsVisible: Bool { showReaderBar || alwaysShowControls || voiceOverEnabled }

    /// With the controls hidden, prose scrolling under the Dynamic Island and home
    /// indicator fades into the page colour instead of colliding with them.
    private var safeAreaFade: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                LinearGradient(stops: [.init(color: backgroundColor, location: 0), .init(color: backgroundColor, location: 0.75),
                                       .init(color: backgroundColor.opacity(0), location: 1)], startPoint: .top, endPoint: .bottom)
                    .frame(height: proxy.safeAreaInsets.top + 18)
                Spacer(minLength: 0)
                LinearGradient(colors: [backgroundColor.opacity(0), backgroundColor], startPoint: .top, endPoint: .bottom)
                    .frame(height: proxy.safeAreaInsets.bottom + 12)
            }
            // The reader measures the insets; only the drawing extends into them.
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Leaves the reader for the page in Add, or Safari when Add isn't reachable.
    private func openSourcePage(_ url: URL) {
        guard let fanficNavigation else { openURL(url); return }
        dismiss()
        fanficNavigation.openInBrowser(url)
    }

    private func toggleControls() {
        guard !alwaysShowControls else { return }
        hideOrigin = nil
        withAnimation(ReaderMotion.chrome) { showReaderBar.toggle() }
    }

    /// A deliberate forward read hides the controls; a tap brings them back.
    private func hideControlsAfterReadingScroll() {
        guard showReaderBar, !alwaysShowControls, !voiceOverEnabled, !showReaderSettings, !showChapterList,
              let offset = scrollController.offset, scrollController.isUserScrolling else { hideOrigin = nil; return }
        guard let origin = hideOrigin, offset >= origin else { hideOrigin = offset; return }
        if offset - origin > 140 {
            withAnimation(ReaderMotion.chrome) { showReaderBar = false }
            hideOrigin = nil
        }
    }
    private func startSession() {
        guard readingSession == nil || readingSession?.endedAt != nil else { return }
        let session = LocalReadingSession(contentType: "fanfic", storyId: fanfic.id)
        modelContext.insert(session); readingSession = session
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

    // MARK: - Top Bar

    private var fanficTopBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                .accessibilityLabel("Back").accessibilityIdentifier(AccessibilityID.readerBackButton)
            VStack(alignment: .leading, spacing: 2) {
                Text(fanfic.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(currentChapter.title ?? "Chapter \(chapterDisplayNum)").font(.headline).lineLimit(1)
            }
            Spacer(minLength: 0)
            Menu {
                Menu("Scroll") {
                    Button("Up one screen") { scrollController.move(forward: false) }
                    Button("Down one screen") { scrollController.move(forward: true) }
                }
                Button(fanfic.isFavorite ? "Remove favourite" : "Add favourite", systemImage: "heart") { fanfic.isFavorite.toggle(); try? modelContext.save() }
                Button("Bookmark current passage", systemImage: "bookmark") { bookmarkParagraphIndex = visibleParagraph ?? 0; showBookmarkSheet = true }
                if let previousJump { Button("Back to previous chapter") { navigateTo(previousJump); self.previousJump = nil } }
                if let previousChapter { Button("Previous chapter") { navigateTo(previousChapter) } }
                if let nextChapter { Button("Next chapter") { navigateTo(nextChapter) } }
                Button("Start chapter over") { visibleParagraph = nil; scrollTargetIndex = 0; scrollController.restoreToStart(); scrollProgress.fraction = 0; scrollProgress.offset = nil; scrollProgress.paragraph = 0 }
                Button(fanfic.completedAt == nil ? "Mark finished" : "Mark unfinished") { fanfic.completedAt = fanfic.completedAt == nil ? .now : nil; try? modelContext.save() }
                Divider()
                if let story = FanficLinks.story(fanfic) {
                    Button("Story page", systemImage: "safari") { openSourcePage(story) }
                }
                ForEach(FanficLinks.authors(fanfic), id: \.self) { name in
                    if let url = FanficLinks.author(name, sourceKey: fanfic.sourceKey) {
                        Button("\(name)'s page", systemImage: "person") { openSourcePage(url) }
                    }
                }
            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
            .accessibilityLabel("More reader actions")
        }
        .foregroundStyle(AstralColors.white).padding(.horizontal, 8).padding(.vertical, 6)
        .background(.regularMaterial)
    }

    private var chapterCountLabel: some View {
        HStack(spacing: 3) {
            Text(chapterDisplayNum)
                .foregroundStyle(AstralColors.white)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text("/")
                .foregroundStyle(AstralColors.muted)
            Text("\(fanfic.totalChapters)")
                .foregroundStyle(AstralColors.muted)
                .monospacedDigit()
        }
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .animation(AstralAnimation.quick, value: currentChapter.chapterNumber)
    }

    private var chapterDisplayNum: String {
        let n = currentChapter.chapterNumber
        return n.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(n))" : String(format: "%.1f", n)
    }

    // MARK: - Bottom Nav Bar (default when HUD is open)

    private var fanficBottomBar: some View {
        HStack {
            Button("Chapters", systemImage: "list.bullet") { showChapterList = true }
                .frame(minHeight: 44)
            Spacer()
            FanficProgressReadout(progress: scrollProgress, chapter: chapterDisplayNum, total: fanfic.totalChapters)
            Spacer()
            Button("Aa", systemImage: "textformat.size") { showReaderSettings = true }
                .labelStyle(.iconOnly).accessibilityLabel("Reading settings").frame(width: 44, height: 44)
        }
        .padding(.horizontal, 16).padding(.vertical, 6).background(.regularMaterial)
    }

    // MARK: - Settings Panel (shown when gear is tapped)

    private var fanficSettingsPanel: some View {
        VStack(spacing: 20) {
            // Typography
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader("Typography")

                VStack(alignment: .leading, spacing: 8) {
                    Text("Font family")
                        .font(AstralTypography.caption)
                        .foregroundStyle(AstralColors.muted)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(ReaderFont.allCases, id: \.self) { font in
                                Button {
                                    withAnimation(AstralAnimation.bouncy) { fontFamily = font }
                                } label: {
                                    Text(font.rawValue)
                                        .font(font.font(size: 13))
                                        .foregroundStyle(fontFamily == font ? AstralColors.gold : AstralColors.body)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(fontFamily == font ? AstralColors.gold.opacity(0.15) : AstralColors.elevated)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                HStack(spacing: 12) {
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

                Stepper(value: $lineHeight, in: 1.2...2.2, step: 0.1) {
                    labeledReadout("Line height", value: String(format: "%.1f", lineHeight))
                }
                .tint(AstralColors.gold)
            }

            // Layout
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader("Layout")

                Stepper(value: $paragraphSpacing, in: 0...36, step: 2) {
                    labeledReadout("Paragraph gap", value: "\(Int(paragraphSpacing))pt")
                }
                .tint(AstralColors.gold)

                Stepper(value: $horizontalMargin, in: 8...48, step: 2) {
                    labeledReadout("Side margins", value: "\(Int(horizontalMargin))pt")
                }
                .tint(AstralColors.gold)
            }

            // Theme
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Background")
                HStack(spacing: 16) {
                    ForEach(ReaderBackground.allCases, id: \.self) { bg in
                        Button {
                            withAnimation(AstralAnimation.bouncy) { background = bg }
                        } label: {
                            Circle()
                                .fill(bgPreviewColor(bg))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Circle()
                                        .stroke(AstralColors.gold, lineWidth: 2.5)
                                        .opacity(background == bg ? 1 : 0)
                                        .scaleEffect(background == bg ? 1 : 0.6)
                                        .animation(AstralAnimation.bouncy, value: background)
                                )
                        }
                        .buttonStyle(PressButtonStyle(scale: 0.88))
                        .accessibilityLabel(bg.rawValue + " background")
                        .accessibilityValue(background == bg ? "Selected" : "")
                    }
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 16)
        .background(.ultraThinMaterial)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(AstralTypography.captionMedium)
            .foregroundStyle(AstralColors.muted)
            .tracking(0.8)
    }

    private func labeledReadout(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(AstralTypography.body)
                .foregroundStyle(AstralColors.white)
            Spacer()
            Text(value)
                .font(AstralTypography.body)
                .foregroundStyle(AstralColors.muted)
                .monospacedDigit()
        }
    }

    private func bgPreviewColor(_ bg: ReaderBackground) -> Color {
        switch bg {
        case .dark:  AstralColors.readerDark
        case .sepia: AstralColors.readerSepia
        case .paper: AstralColors.readerPaper
        }
    }

    private var paragraphs: [String] { preparedChapter.paragraphs }

    private func wordOffsetForParagraph(_ index: Int) -> Int {
        preparedChapter.wordOffsets.indices.contains(index) ? preparedChapter.wordOffsets[index] : 0
    }

    private func persistReadingState(endSession: Bool, syncRemote: Bool) {
        if endSession { readingSession?.endedAt = .now; try? modelContext.save() }
        guard !chapterContent.isEmpty, !isLoading else { return }
        // A chapter that fits on one screen has no scroll range, so it never moves
        // past 0%; once it has been on screen it has been read in full.
        if scrollController.contentFitsViewport { scrollProgress.fraction = 1 }
        fanfic.scrollOffsetPercent = scrollProgress.fraction
        fanfic.lastReadChapterNumber = currentChapter.chapterNumber
        fanfic.lastReadAt = .now
        let order = allChapters.firstIndex { $0.id == currentChapter.id } ?? 0
        fanfic.progressPercent = min(1, (Double(order) + (fanfic.scrollOffsetPercent ?? 0)) / Double(max(1, allChapters.count)))
        ReadingPositionStore.save(.init(chapterID: currentChapter.id, chapterNumber: currentChapter.chapterNumber,
            fraction: scrollProgress.fraction, paragraph: scrollProgress.paragraph, offset: scrollProgress.offset, layoutSignature: scrollProgress.layoutSignature ?? layoutSignature), story: fanfic.id)
        if endSession { readingSession?.endedAt = .now }
        try? modelContext.save()
    }

    private func content(for chapter: LocalFanficChapter) async throws -> String {
        if let previewContent { return previewContent }
        if let path = chapter.localTextPath,
           let text = try? await FanficReaderPreparation.shared.read(URL.documentsDirectory.appendingPathComponent(path)), !text.isEmpty { return text }
        guard !["ao3", "ffnet", "local"].contains(fanfic.sourceKey), AppConfig.companionEnabled else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "This chapter is not saved on this device. Return to the story to import it."])
        }
        let result: FanficChapterResponse = try await APIClient.shared.request(.fanficChapter(fanficId: fanfic.id, chapterId: chapter.id))
        guard let text = result.content, !text.isEmpty else { throw APIError.notFound }
        return text
    }
    private func loadChapter() async {
        defer { isLoading = false }
        do {
            let text = try await content(for: currentChapter)
            let prepared = await FanficReaderPreparation.shared.prepare(text, keepsLineBreaks: fanfic.sourceKey != "local")
            chapterContent = text; preparedChapter = prepared
            restorePosition()
            offlineError = false
        } catch { offlineError = true }
    }
    private func restorePixelsIfCompatible() {
        guard didRestoreAnchor, viewportWidth > 0 else { return }
        if pendingLayoutSignature == layoutSignature, let offset = pendingPixelOffset { scrollController.restore(offset: offset) }
        pendingPixelOffset = nil; pendingLayoutSignature = nil
    }
    // Width to one decimal: layout passes can report 402.0 and 402.00000000000006
    // for the same screen, which must not discard a saved pixel position.
    private var layoutSignature: String { "\(fontFamily.rawValue)/\(fontSize)/\(lineHeight)/\(paragraphSpacing)/\(horizontalMargin)/\(String(format: "%.1f", viewportWidth))" }
    private func restorePosition() {
        didRestoreAnchor = false
        if let bookmark = initialBookmark, !appliedInitialBookmark, bookmark.chapterNumber == currentChapter.chapterNumber {
            let offset = bookmark.wordOffset ?? 0
            let index = preparedChapter.paragraphIndex(wordOffset: offset)
            visibleParagraph = index == 0 ? nil : index; scrollTargetIndex = index
            scrollProgress.fraction = bookmark.scrollPercent ?? 0
            scrollProgress.offset = nil; scrollProgress.paragraph = index; scrollProgress.layoutSignature = nil
            appliedInitialBookmark = true
            return
        }
        let saved = ReadingPositionStore.position(story: fanfic.id, chapter: currentChapter.id)
        scrollProgress.offset = saved?.offset
        scrollProgress.paragraph = saved?.paragraph ?? 0
        scrollProgress.layoutSignature = saved?.layoutSignature
        pendingPixelOffset = saved?.offset
        pendingLayoutSignature = saved?.layoutSignature
        let legacy = currentChapter.chapterNumber == fanfic.lastReadChapterNumber ? (fanfic.scrollOffsetPercent ?? 0) : 0
        scrollProgress.fraction = saved?.fraction ?? legacy
        let anchor = saved?.paragraph ?? Int(legacy * Double(max(0, paragraphs.count - 1)))
        let target = min(max(0, anchor), max(0, paragraphs.count - 1))
        // Binding paragraph zero as a scroll target aligns the prose with the
        // viewport edge, skipping the chapter heading and top content padding.
        visibleParagraph = target == 0 ? nil : target
        scrollTargetIndex = target
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
        guard chapter.id != currentChapter.id, !isTransitioning else { return }
        persistReadingState(endSession: false, syncRemote: false)
        isTransitioning = true; transitionError = nil; failedChapter = nil
        Task { @MainActor in
            defer { isTransitioning = false; pullProgress = 0 }
            do {
                let text = try await content(for: chapter)
                let prepared = await FanficReaderPreparation.shared.prepare(text, keepsLineBreaks: fanfic.sourceKey != "local")
                try Task.checkCancellation()
                hasRestoredScroll = false
                currentChapter = chapter; chapterContent = text; preparedChapter = prepared
                bookmarkParagraphIndex = nil; scrollTargetIndex = nil
                restorePosition()
                readingSession?.chaptersRead += 1
                Haptics.play(.chapterNav)
                persistReadingState(endSession: false, syncRemote: false)
            } catch {
                failedChapter = chapter; transitionError = error.localizedDescription
                showReaderBar = true
            }
        }
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
