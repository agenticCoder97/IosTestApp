import SwiftUI
import Core
import DesignSystem

struct ComicCardView: View {
    let comic: LocalComic

    private var progressPercent: Double {
        guard comic.totalChapters > 0 else { return 0 }
        return Double(comic.lastReadChapterNumber) / Double(comic.totalChapters)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(AstralColors.elevated)

                if comic.thumbnailPath != nil {
                    // AsyncImage loading from STATIC_BASE_URL + thumbnailPath
                    Image(systemName: "photo")
                        .font(.system(size: 32))
                        .foregroundStyle(AstralColors.muted)
                } else {
                    Image(systemName: "book.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(AstralColors.muted)
                }
            }
            .aspectRatio(3/4, contentMode: .fit)
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 4) {
                    if comic.isDownloaded {
                        StatusBadge.downloaded()
                    }
                    if comic.status == "partial" {
                        StatusBadge.partial()
                    }
                }
                .padding(6)
            }

            // Title
            Text(comic.title)
                .font(AstralTypography.captionMedium)
                .foregroundStyle(AstralColors.white)
                .lineLimit(2)

            // Progress bar
            if comic.totalChapters > 0 {
                ProgressBarView(progress: progressPercent)
                Text("\(comic.lastReadChapterNumber)/\(comic.totalChapters)")
                    .font(AstralTypography.caption)
                    .foregroundStyle(AstralColors.muted)
            }
        }
        .astralCard()
    }
}
