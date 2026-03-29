import SwiftUI
import DesignSystem

public struct FanficTabView: View {
    @State private var navigation = FanficNavigation()
    @State private var searchText = ""
    var onSwitchTab: () -> Void

    public init(onSwitchTab: @escaping () -> Void = {}) {
        self.onSwitchTab = onSwitchTab
    }

    public var body: some View {
        ZStack {
            AstralColors.background
                .ignoresSafeArea()

            NavigationStack {
                Group {
                    switch navigation.activeSection {
                    case .library:
                        FanficLibraryView(searchText: $searchText, filterFavourites: false)
                    case .favourites:
                        FanficLibraryView(searchText: .constant(""), filterFavourites: true)
                    case .browse:
                        FanficBrowserView()
                    case .scrapes:
                        FanficScrapesView()
                    case .downloads:
                        FanficLibraryView(searchText: $searchText, filterFavourites: false)
                    case .stats:
                        FanficStatsView()
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    onSwitchTab()
                                }
                            } label: {
                                Label("Comics", systemImage: "book.fill")
                            }
                            Button {
                                // Already on Fan Fiction tab
                            } label: {
                                Label("Fan Fiction", systemImage: "scroll.fill")
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "scroll.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("Fan Fiction")
                                    .font(AstralTypography.title)
                                Image(systemName: "chevron.down")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(AstralColors.muted)
                            }
                        }
                        .tint(AstralColors.gold)
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
    case favourites = "Favourites"
    case browse = "Browse"
    case scrapes = "Scrapes"
    case downloads = "Downloads"
    case stats = "Stats"

    var icon: String {
        switch self {
        case .library: "books.vertical"
        case .favourites: "heart.fill"
        case .browse: "globe"
        case .scrapes: "arrow.down.circle"
        case .downloads: "arrow.down.to.line"
        case .stats: "chart.bar"
        }
    }
}

#Preview {
    FanficTabView()
}
