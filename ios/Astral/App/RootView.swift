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
                    ComicTabView()
                case .fanfic:
                    FanficTabView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            TabBarView(activeTab: $appState.activeTab)
        }
        .environment(appState)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    RootView()
}
