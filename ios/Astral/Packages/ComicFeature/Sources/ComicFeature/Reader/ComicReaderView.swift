import SwiftUI
import Core
import DesignSystem
import Networking

struct ComicReaderView: View {
    let comic: LocalComic
    let chapter: LocalComicChapter

    @State private var showHUD = false
    @State private var currentPage = 1
    @State private var pages: [PageResponse] = []
    @State private var isLoading = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .tint(AstralColors.gold)
            } else if pages.isEmpty {
                EmptyStateView(
                    icon: "photo.on.rectangle.angled",
                    title: "No Pages",
                    message: "This chapter hasn't been scraped yet."
                )
            } else {
                // Page content area
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(pages) { page in
                            ComicPageView(page: page)
                        }
                    }
                }
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showHUD.toggle()
                    }
                }
            }

            // HUD overlay
            if showHUD {
                VStack {
                    // Top bar
                    HStack {
                        Text("Ch. \(chapter.chapterNumber, specifier: "%.0f")")
                            .font(AstralTypography.bodyMedium)
                        if let title = chapter.title {
                            Text("— \(title)")
                                .font(AstralTypography.body)
                                .foregroundStyle(AstralColors.muted)
                        }
                        Spacer()
                        Text("\(currentPage)/\(pages.count)")
                            .font(AstralTypography.caption)
                            .foregroundStyle(AstralColors.muted)
                    }
                    .foregroundStyle(AstralColors.white)
                    .padding()
                    .background(.ultraThinMaterial)

                    Spacer()

                    // Bottom controls
                    HStack {
                        Button("Prev") {}
                            .foregroundStyle(AstralColors.gold)
                        Spacer()
                        Button("Next") {}
                            .foregroundStyle(AstralColors.gold)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                }
                .transition(.opacity)
            }
        }
        .navigationBarHidden(true)
        .task {
            await loadPages()
        }
    }

    private func loadPages() async {
        do {
            let response: [PageResponse] = try await APIClient.shared.request(
                .chapterPages(comicId: comic.id, chapterId: chapter.id)
            )
            pages = response
        } catch {
            // Handle error
        }
        isLoading = false
    }
}

struct ComicPageView: View {
    let page: PageResponse

    var body: some View {
        // Placeholder — will load from STATIC_BASE_URL + page.filePath
        Rectangle()
            .fill(AstralColors.elevated)
            .aspectRatio(
                page.widthPx != nil && page.heightPx != nil
                    ? CGFloat(page.widthPx!) / CGFloat(page.heightPx!)
                    : 2/3,
                contentMode: .fit
            )
            .overlay {
                Image(systemName: "photo")
                    .foregroundStyle(AstralColors.muted)
            }
    }
}
