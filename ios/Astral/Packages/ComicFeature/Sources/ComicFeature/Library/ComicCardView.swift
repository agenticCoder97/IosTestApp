import SwiftUI
import Core
import DesignSystem

struct ComicCardView: View {
    let comic: LocalComic

    @Environment(\.modelContext) private var modelContext

    private func thumbnailURL(_ path: String) -> URL? {
        if path.hasPrefix("http") { return URL(string: path) }
        return URL(string: AppConfig.staticBaseURL + path)
    }

    private var progressPercent: Double {
        guard comic.totalChapters > 0 else { return 0 }
        return Double(comic.lastReadChapterNumber) / Double(comic.totalChapters)
    }

    private var sourceIcon: String {
        switch comic.sourceKey {
        case "nhentai": "n.square.fill"
        case "toongod": "t.square.fill"
        case "hentai20": "h.square.fill"
        case "mangadex": "m.square.fill"
        default: "questionmark.square.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(AstralColors.elevated)

                if let path = comic.thumbnailPath, let url = thumbnailURL(path) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                                .clipped()
                        default:
                            Image(systemName: "book.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(AstralColors.muted)
                        }
                    }
                } else {
                    Image(systemName: "book.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(AstralColors.muted)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .aspectRatio(0.7, contentMode: .fit)
            .saturation(comic.isArchived ? 0 : 1)
            .overlay(alignment: .top) {
                if comic.isArchived {
                    Text("ARCHIVED")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(AstralColors.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AstralColors.muted.opacity(0.8))
                        .clipShape(Capsule())
                        .padding(.top, 6)
                } else if comic.isArchiving {
                    HStack(spacing: 4) {
                        ProgressView().tint(.white).scaleEffect(0.6)
                        Text("Archiving")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(AstralColors.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AstralColors.warning.opacity(0.8))
                    .clipShape(Capsule())
                    .padding(.top, 6)
                } else if comic.isUnarchiving {
                    HStack(spacing: 4) {
                        ProgressView().tint(.white).scaleEffect(0.6)
                        Text("Restoring")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(AstralColors.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AstralColors.gold.opacity(0.8))
                    .clipShape(Capsule())
                    .padding(.top, 6)
                }
            }
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 4) {
                    if comic.isDownloaded {
                        StatusBadge.savedToDevice()
                    }
                    if comic.status == "partial" {
                        StatusBadge.partial()
                    }
                }
                .padding(6)
            }
            // New chapter badge — pops in/out with a spring scale
            .overlay(alignment: .topLeading) {
                if comic.newChapterCount > 0 {
                    Text("+\(comic.newChapterCount)")
                        .font(AstralTypography.caption)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AstralColors.gold)
                        .clipShape(Capsule())
                        .padding(6)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .animation(AstralAnimation.bouncy, value: comic.newChapterCount)
            // Source icon
            .overlay(alignment: .bottomLeading) {
                Image(systemName: sourceIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AstralColors.white)
                    .padding(6)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(6)
            }
            // Favourite heart — bouncy toggle with symbol morph
            .overlay(alignment: .bottomTrailing) {
                Button {
                    withAnimation(AstralAnimation.bouncy) {
                        comic.isFavorite.toggle()
                    }
                    try? modelContext.save()
                } label: {
                    Image(systemName: comic.isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 14))
                        .foregroundStyle(comic.isFavorite ? AstralColors.error : AstralColors.muted)
                        .contentTransition(.symbolEffect(.replace.downUp))
                        .scaleEffect(comic.isFavorite ? 1.18 : 1.0)
                        .animation(AstralAnimation.bouncy, value: comic.isFavorite)
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(6)
            }

            // Title
            Text(comic.title)
                .font(AstralTypography.captionMedium)
                .foregroundStyle(AstralColors.white)
                .lineLimit(2)

            // Progress
            if comic.totalChapters > 0 {
                HStack(spacing: 6) {
                    // Circular progress
                    ZStack {
                        Circle()
                            .stroke(AstralColors.muted.opacity(0.2), lineWidth: 2.5)
                        Circle()
                            .trim(from: 0, to: progressPercent)
                            .stroke(AstralColors.gold, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .rotationEffect(.degrees(-135))
                    }
                    .frame(width: 22, height: 22)

                    Text("\(comic.lastReadChapterNumber)/\(comic.totalChapters)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AstralColors.body)
                }
            }
        }
        .astralCard()
    }
}

// MARK: - Previews

#Preview("In Progress + Favourite + Badge") {
    ComicCardView(comic: PreviewMocks.comic1)
        .frame(width: 180)
        .padding()
        .background(AstralColors.background)
        .modelContainer(.previewContainer(comics: [PreviewMocks.comic1]))
}

#Preview("Complete + Downloaded") {
    ComicCardView(comic: PreviewMocks.comic2)
        .frame(width: 180)
        .padding()
        .background(AstralColors.background)
        .modelContainer(.previewContainer(comics: [PreviewMocks.comic2]))
}

#Preview("Freshly Added") {
    ComicCardView(comic: PreviewMocks.comic3)
        .frame(width: 180)
        .padding()
        .background(AstralColors.background)
        .modelContainer(.previewContainer(comics: [PreviewMocks.comic3]))
}
