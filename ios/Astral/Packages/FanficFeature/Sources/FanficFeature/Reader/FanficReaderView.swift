import SwiftUI
import Core
import DesignSystem
import Networking

struct FanficReaderView: View {
    let fanfic: LocalFanfic
    let chapter: LocalFanficChapter

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
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Chapter title
                        if let title = chapter.title {
                            Text(title)
                                .font(AstralTypography.title)
                                .foregroundStyle(textColor)
                        }

                        Text("Chapter \(chapter.chapterNumber, specifier: "%.0f")")
                            .font(AstralTypography.caption)
                            .foregroundStyle(AstralColors.muted)

                        // Chapter text
                        Text(chapterContent)
                            .font(.system(size: fontSize))
                            .lineSpacing((lineHeight - 1.0) * fontSize)
                            .foregroundStyle(textColor)
                    }
                    .padding(20)
                    .padding(.bottom, 100)
                }
            }

            // Reader settings bar
            if showReaderBar {
                VStack {
                    Spacer()
                    readerSettingsBar
                }
                .transition(.move(edge: .bottom))
            }
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                showReaderBar.toggle()
            }
        }
        .task {
            await loadChapter()
        }
    }

    private var backgroundColor: Color {
        switch background {
        case .dark: AstralColors.readerDark
        case .sepia: AstralColors.readerSepia
        case .paper: AstralColors.readerPaper
        }
    }

    private var textColor: Color {
        switch background {
        case .dark: AstralColors.body
        case .sepia: Color(hex: 0xD4C5A9)
        case .paper: Color(hex: 0x2C2C2C)
        }
    }

    private var readerSettingsBar: some View {
        VStack(spacing: 12) {
            // Font size
            HStack {
                Text("Aa")
                    .font(.system(size: 14))
                    .foregroundStyle(AstralColors.muted)
                Slider(value: $fontSize, in: 14...22, step: 1)
                    .tint(AstralColors.gold)
                Text("Aa")
                    .font(.system(size: 22))
                    .foregroundStyle(AstralColors.muted)
            }

            // Line height
            HStack {
                Image(systemName: "text.line.first.and.arrowtriangle.forward")
                    .foregroundStyle(AstralColors.muted)
                Slider(value: $lineHeight, in: 1.4...1.8, step: 0.1)
                    .tint(AstralColors.gold)
            }

            // Background picker
            HStack(spacing: 16) {
                ForEach(ReaderBackground.allCases, id: \.self) { bg in
                    Button {
                        background = bg
                    } label: {
                        Circle()
                            .fill(bgPreviewColor(bg))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Circle()
                                    .stroke(
                                        background == bg ? AstralColors.gold : Color.clear,
                                        lineWidth: 2
                                    )
                            )
                    }
                }
                Spacer()
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
    }

    private func bgPreviewColor(_ bg: ReaderBackground) -> Color {
        switch bg {
        case .dark: AstralColors.readerDark
        case .sepia: AstralColors.readerSepia
        case .paper: AstralColors.readerPaper
        }
    }

    private func loadChapter() async {
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
