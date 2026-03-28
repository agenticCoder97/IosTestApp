import SwiftUI
import SwiftData
import Core
import DesignSystem
import Networking

struct FanficReaderView: View {
    let fanfic: LocalFanfic
    let chapter: LocalFanficChapter
    private let previewContent: String?

    init(fanfic: LocalFanfic, chapter: LocalFanficChapter, previewContent: String? = nil) {
        self.fanfic = fanfic
        self.chapter = chapter
        self.previewContent = previewContent
    }

    @Environment(\.modelContext) private var modelContext

    @State private var chapterContent = ""
    @State private var isLoading = true
    @State private var showReaderBar = false
    @State private var fontSize: CGFloat = 16
    @State private var lineHeight: CGFloat = 1.6
    @State private var background: ReaderBackground = .dark
    @State private var fontFamily: ReaderFont = .system
    @State private var paragraphSpacing: CGFloat = 12
    @State private var horizontalMargin: CGFloat = 20
    @State private var showBookmarkSheet = false
    @State private var bookmarkParagraphIndex: Int?

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .tint(AstralColors.gold)
                    .scaleEffect(1.2)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: paragraphSpacing) {
                        if let title = chapter.title {
                            Text(title)
                                .font(AstralTypography.title)
                                .foregroundStyle(textColor)
                        }

                        Text("Chapter \(chapter.chapterNumber, specifier: "%.0f")")
                            .font(AstralTypography.caption)
                            .foregroundStyle(AstralColors.muted)

                        ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                            Text(paragraph)
                                .font(fontFamily.font(size: fontSize))
                                .lineSpacing((lineHeight - 1.0) * fontSize)
                                .foregroundStyle(textColor)
                                .simultaneousGesture(
                                    LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                                        bookmarkParagraphIndex = index
                                        showBookmarkSheet = true
                                    }
                                )
                        }
                    }
                    .padding(.horizontal, horizontalMargin)
                    .padding(.vertical, 20)
                    .animation(AstralAnimation.quick, value: fontSize)
                    .animation(AstralAnimation.quick, value: lineHeight)
                    .animation(AstralAnimation.quick, value: horizontalMargin)
                    .padding(.bottom, 100)
                }
            }

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
        .task { await loadChapter() }
        .sheet(isPresented: $showBookmarkSheet) {
            FanficBookmarkSheet(
                paragraphText: bookmarkParagraphIndex.flatMap { paragraphs.indices.contains($0) ? paragraphs[$0] : nil } ?? "",
                chapterTitle: chapter.title,
                chapterNumber: chapter.chapterNumber,
                wordOffset: bookmarkParagraphIndex.flatMap { wordOffsetForParagraph($0) } ?? 0,
                onSave: { selectedText, heading, wordOffset in
                    let bookmark = LocalBookmark(
                        contentType: "fanfic",
                        storyId: fanfic.id,
                        chapterNumber: chapter.chapterNumber,
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

    private var chapterDisplayNum: String {
        let n = chapter.chapterNumber
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
                Slider(value: $fontSize, in: 14...22, step: 1)
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
                Slider(value: $lineHeight, in: 1.4...1.8, step: 0.1)
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
                Slider(value: $paragraphSpacing, in: 4...28, step: 2)
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
                Slider(value: $horizontalMargin, in: 12...40, step: 4)
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
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func wordOffsetForParagraph(_ index: Int) -> Int {
        paragraphs.prefix(index)
            .reduce(0) { $0 + $1.split(separator: " ").count }
    }

    private func loadChapter() async {
        AstralLogger.info("loadChapter: ch \(chapter.chapterNumber) (id=\(chapter.id)) for '\(fanfic.title)'", context: "FanficReader")
        if let previewContent {
            chapterContent = previewContent
            isLoading = false
            return
        }
        do {
            let response: FanficChapterResponse = try await APIClient.shared.request(
                .fanficChapter(fanficId: fanfic.id, chapterId: chapter.id)
            )
            chapterContent = response.content ?? ""
            AstralLogger.info("loadChapter: got \(chapterContent.count) chars", context: "FanficReader")
        } catch {
            chapterContent = "Failed to load chapter."
            AstralLogger.error("loadChapter failed: \(error)", context: "FanficReader")
        }
        isLoading = false
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
        chapter: PreviewMocks.fanfic1Chapters[1],
        previewContent: PreviewMocks.sampleFanficChapterContent
    )
}

#Preview("Reader - Sepia") {
    FanficReaderView(
        fanfic: PreviewMocks.fanfic2,
        chapter: PreviewMocks.fanfic1Chapters[2],
        previewContent: PreviewMocks.sampleFanficChapterContent
    )
}

#Preview("Reader - No Content") {
    FanficReaderView(
        fanfic: PreviewMocks.fanfic3,
        chapter: PreviewMocks.fanfic1Chapters[4],
        previewContent: ""
    )
}
