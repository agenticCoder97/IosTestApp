import SwiftUI
import DesignSystem
import Networking

/// Sheet shown when the backend matcher proposes a MangaDex swap for a
/// toongod/hentai20 add. AST-30 — single-user, no public attribution
/// surfaces; this dialog is the only place the user sees the swap.
struct MangaDexMatchDialog: View {
    let match: MangaDexMatchPayload
    let originalSource: String
    let onAccept: () -> Void
    let onDecline: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("MangaDex match found")
                .font(AstralTypography.title)
                .foregroundStyle(AstralColors.white)

            if let urlString = match.thumbnailUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    default:
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(AstralColors.muted)
                    }
                }
                .frame(maxHeight: 180)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(spacing: 6) {
                Text(match.title)
                    .font(AstralTypography.bodyMedium)
                    .foregroundStyle(AstralColors.white)
                    .multilineTextAlignment(.center)

                Text(
                    "Confidence \(Int(match.confidence * 100))% · "
                    + "\(match.chapterCount) chapters on MangaDex vs "
                    + "\(match.sourceChapterCount) on \(originalSource)"
                )
                .font(AstralTypography.caption)
                .foregroundStyle(AstralColors.muted)
                .multilineTextAlignment(.center)
            }

            VStack(spacing: 8) {
                Button {
                    onAccept()
                    dismiss()
                } label: {
                    Text("Use MangaDex")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(AstralColors.gold, in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)

                Button {
                    onDecline()
                    dismiss()
                } label: {
                    Text("Keep \(originalSource)")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(AstralColors.elevated, in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(AstralColors.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .background(AstralColors.background)
        .presentationDetents([.medium])
    }
}
