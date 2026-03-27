import SwiftUI
import DesignSystem
import ComicFeature
import FanficFeature

struct RootView: View {
    @State private var appState = AppState()

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch appState.activeTab {
                case .comic:
                    ComicTabView(onSwitchTab: { appState.activeTab = .fanfic })
                case .fanfic:
                    FanficTabView(onSwitchTab: { appState.activeTab = .comic })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        }
        .environment(appState)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    RootView()
}
