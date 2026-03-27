import SwiftUI

enum AppTab: String, CaseIterable {
    case comic
    case fanfic
}

@Observable
final class AppState {
    var activeTab: AppTab = .comic
    var isComicSidebarOpen = false
    var isFanficSidebarOpen = false

    func toggleSidebar() {
        switch activeTab {
        case .comic:
            isComicSidebarOpen.toggle()
            isFanficSidebarOpen = false
        case .fanfic:
            isFanficSidebarOpen.toggle()
            isComicSidebarOpen = false
        }
    }

    func closeSidebars() {
        isComicSidebarOpen = false
        isFanficSidebarOpen = false
    }
}
