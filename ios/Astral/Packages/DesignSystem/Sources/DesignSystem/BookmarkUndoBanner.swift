import SwiftUI
import Core

public struct BookmarkUndoBanner: View {
    public init() {}
    public var body: some View {
        if let message = BookmarkUndoService.shared.message {
            HStack {
                Text(message).font(.callout)
                Spacer()
                if BookmarkUndoService.shared.canUndo { Button("Undo") { BookmarkUndoService.shared.undo() } }
                Button("Dismiss", systemImage: "xmark") { BookmarkUndoService.shared.dismiss() }.labelStyle(.iconOnly)
            }
            .padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal)
        }
    }
}
