import SwiftUI
import DesignSystem

public struct ComicTabView: View {
    @State private var navigation = ComicNavigation()
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
                        ComicLibraryView(filterFavourites: false)
                    case .favourites:
                        ComicLibraryView(filterFavourites: true)
                    case .read:
                        ComicLibraryView(filterFavourites: false)
                    case .browse:
                        ComicBrowserView()
                    case .scrapes:
                        ComicScrapesView()
                    case .search:
                        ComicSearchView(searchText: $navigation.searchText)
                    case .stats:
                        StatsView()
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button {
                                // Already on Comics tab
                            } label: {
                                Label("Comics", systemImage: "book.fill")
                            }
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    onSwitchTab()
                                }
                            } label: {
                                Label("Fan Fiction", systemImage: "scroll.fill")
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text("Comics")
                                    .font(AstralTypography.title)
                                    .foregroundStyle(AstralColors.white)
                                Image(systemName: "chevron.down")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AstralColors.muted)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(AstralColors.elevated)
                            .clipShape(Capsule())
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
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
            .environment(\.comicNavigation, navigation)

            // Sidebar overlay
            ComicSidebarView(
                isOpen: $navigation.isSidebarOpen,
                activeSection: $navigation.activeSection
            )
        }
    }
}

@Observable
final class ComicNavigation {
    var activeSection: ComicSection = .library
    var isSidebarOpen = false
    var searchText = ""

    func searchFor(_ term: String) {
        searchText = term
        activeSection = .search
    }
}

private struct ComicNavigationKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: ComicNavigation? = nil
}

extension EnvironmentValues {
    var comicNavigation: ComicNavigation? {
        get { self[ComicNavigationKey.self] }
        set { self[ComicNavigationKey.self] = newValue }
    }
}

enum ComicSection: String, CaseIterable {
    case library = "Library"
    case favourites = "Favourites"
    case read = "Continue Reading"
    case browse = "Browse"
    case scrapes = "Scrapes"
    case search = "Search"
    case stats = "Stats"

    var icon: String {
        switch self {
        case .library: "books.vertical"
        case .favourites: "heart.fill"
        case .read: "book"
        case .browse: "globe"
        case .scrapes: "arrow.down.circle"
        case .search: "magnifyingglass"
        case .stats: "chart.bar"
        }
    }
}

#Preview {
    ComicTabView()
}
