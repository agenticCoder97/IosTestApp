import SwiftUI
import DesignSystem

public struct FanficTabView: View {
    @State private var navigation = FanficNavigation()
    @State private var searchText = ""

    public init() {}

    public var body: some View {
        ZStack {
            AstralColors.background
                .ignoresSafeArea()

            NavigationStack {
                Group {
                    switch navigation.activeSection {
                    case .library:
                        FanficLibraryView(searchText: $searchText)
                    case .browse:
                        FanficBrowserView()
                    case .scrapes:
                        FanficScrapesView()
                    case .downloads:
                        FanficLibraryView(searchText: $searchText) // Filtered to downloaded
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Text("Fanfic")
                            .font(AstralTypography.title)
                            .foregroundStyle(AstralColors.white)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 16) {
                            Button {
                                // TODO: Show search
                            } label: {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(AstralColors.body)
                            }
                            Button {
                                withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                                    navigation.isSidebarOpen.toggle()
                                }
                            } label: {
                                Image(systemName: "line.3.horizontal")
                                    .foregroundStyle(AstralColors.body)
                            }
                        }
                    }
                }
            }

            FanficSidebarView(
                isOpen: $navigation.isSidebarOpen,
                activeSection: $navigation.activeSection
            )
        }
    }
}

@Observable
final class FanficNavigation {
    var activeSection: FanficSection = .library
    var isSidebarOpen = false
}

/// Architecture fix #9: Added .scrapes section — missing from original doc's fanfic sidebar.
enum FanficSection: String, CaseIterable {
    case library = "Library"
    case browse = "Browse"
    case scrapes = "Scrapes"
    case downloads = "Downloads"

    var icon: String {
        switch self {
        case .library: "books.vertical"
        case .browse: "globe"
        case .scrapes: "arrow.down.circle"
        case .downloads: "arrow.down.to.line"
        }
    }
}

#Preview {
    FanficTabView()
}
