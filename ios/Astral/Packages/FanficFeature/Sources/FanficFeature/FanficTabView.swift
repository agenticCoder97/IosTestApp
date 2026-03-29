import SwiftUI
import DesignSystem

public struct FanficTabView: View {
    @State private var navigation = FanficNavigation()
    var onSwitchTab: () -> Void

    public init(onSwitchTab: @escaping () -> Void = {}) {
        self.onSwitchTab = onSwitchTab
    }

    public var body: some View {
        ZStack {
            AstralColors.background
                .ignoresSafeArea()

            NavigationStack {
                VStack(spacing: 0) {
                    // Search bar — slides in when active
                    AstralSearchBar(
                        text: $navigation.searchText,
                        isActive: $navigation.isSearchActive,
                        placeholder: "Title, fandom, character, relationship..."
                    )

                    // Main content
                    Group {
                        switch navigation.activeSection {
                        case .library:
                            FanficLibraryView(searchText: $navigation.searchText, filterFavourites: false)
                        case .favourites:
                            FanficLibraryView(searchText: .constant(""), filterFavourites: true)
                        case .browse:
                            FanficBrowserView()
                        case .scrapes:
                            FanficScrapesView()
                        case .stats:
                            FanficStatsView()
                        }
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
                        HStack(spacing: 14) {
                            // Search toggle
                            Button {
                                withAnimation(AstralAnimation.quick) {
                                    navigation.isSearchActive.toggle()
                                    if !navigation.isSearchActive {
                                        navigation.searchText = ""
                                    }
                                }
                            } label: {
                                Image(systemName: navigation.isSearchActive ? "magnifyingglass.circle.fill" : "magnifyingglass")
                                    .foregroundStyle(navigation.isSearchActive ? AstralColors.gold : AstralColors.body)
                            }

                            // Filter
                            Button {
                                navigation.showFilter = true
                            } label: {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                                    .foregroundStyle(AstralColors.body)
                            }

                            // Sidebar
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
            .environment(\.fanficNavigation, navigation)

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
    var searchText = ""
    var isSearchActive = false
    var showFilter = false

    func searchFor(_ term: String) {
        searchText = term
        isSearchActive = true
        activeSection = .library
    }
}

private struct FanficNavigationKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: FanficNavigation? = nil
}

extension EnvironmentValues {
    var fanficNavigation: FanficNavigation? {
        get { self[FanficNavigationKey.self] }
        set { self[FanficNavigationKey.self] = newValue }
    }
}

enum FanficSection: String, CaseIterable {
    case library = "Library"
    case favourites = "Favourites"
    case browse = "Browse"
    case scrapes = "Scrapes"
    case stats = "Stats"

    var icon: String {
        switch self {
        case .library: "books.vertical"
        case .favourites: "heart.fill"
        case .browse: "globe"
        case .scrapes: "arrow.down.circle"
        case .stats: "chart.bar"
        }
    }
}

#Preview {
    FanficTabView()
}
