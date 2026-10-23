import SwiftUI
import Core

public struct BookmarkUndoBanner: View {
    public init() {}
    public var body: some View {
        if let message = BookmarkUndoService.shared.message {
            HStack(spacing: 14) {
                Text(message).font(.callout).foregroundStyle(AstralColors.white)
                Spacer()
                if BookmarkUndoService.shared.canUndo {
                    Button("Undo") { BookmarkUndoService.shared.undo() }
                        .font(.callout.weight(.semibold))
                }
                Button("Dismiss", systemImage: "xmark") { BookmarkUndoService.shared.dismiss() }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(AstralColors.muted)
            }
            .tint(AstralColors.gold)
            .padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal)
        }
    }
}
