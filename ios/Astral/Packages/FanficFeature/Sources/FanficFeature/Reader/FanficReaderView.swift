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

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .tint(AstralColors.gold)
                    .scaleEffect(1.2)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let title = chapter.title {
                            Text(title)
                                .font(AstralTypography.title)
                                .foregroundStyle(textColor)
                        }

                        Text("Chapter \(chapter.chapterNumber, specifier: "%.0f")")
                            .font(AstralTypography.caption)
                            .foregroundStyle(AstralColors.muted)

                        Text(chapterContent)
                            .font(.system(size: fontSize))
                            .lineSpacing((lineHeight - 1.0) * fontSize)
                            .foregroundStyle(textColor)
                            // Live preview as sliders move
                            .animation(AstralAnimation.quick, value: fontSize)
                            .animation(AstralAnimation.quick, value: lineHeight)
                    }
                    .padding(20)
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
                    .frame(width: 54, height: 54)
                VStack(spacing: 2) {
                    Text(chapterDisplayNum)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(AstralColors.white)
                        .monospacedDigit()
                    Capsule()
                        .fill(AstralColors.muted)
                        .frame(width: 20, height: 1)
                    Text("\(fanfic.totalChapters)")
                        .font(.system(size: 11, weight: .medium))
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

    private func loadChapter() async {
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
        } catch {
            chapterContent = "Failed to load chapter."
        }
        isLoading = false
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
