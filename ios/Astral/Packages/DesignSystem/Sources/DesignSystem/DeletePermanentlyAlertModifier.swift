import SwiftUI

public struct DeletePermanentlyAlertModifier: ViewModifier {
    @Binding public var isPresented: Bool
    public let storyTitle: String
    public let onConfirm: () -> Void

    public init(isPresented: Binding<Bool>, storyTitle: String, onConfirm: @escaping () -> Void) {
        self._isPresented = isPresented
        self.storyTitle = storyTitle
        self.onConfirm = onConfirm
    }

    public func body(content: Content) -> some View {
        content.alert("Delete Permanently?", isPresented: $isPresented) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { onConfirm() }
        } message: {
            Text("This will permanently delete \"\(storyTitle)\" and all local data. This cannot be undone.")
        }
    }
}

public extension View {
    func deletePermanentlyAlert(
        isPresented: Binding<Bool>,
        storyTitle: String,
        onConfirm: @escaping () -> Void
    ) -> some View {
        modifier(DeletePermanentlyAlertModifier(isPresented: isPresented, storyTitle: storyTitle, onConfirm: onConfirm))
    }
}
