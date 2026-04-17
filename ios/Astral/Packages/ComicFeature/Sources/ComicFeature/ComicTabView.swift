import SwiftUI
import DesignSystem

public struct ComicTabView: View {
    @State private var navigation = ComicNavigation()
    @State private var showFilter = false
    @AppStorage("comic.filter.v1") private var filterPrefsJSON: String = ""
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
                                Image(systemName: "book.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Comics")
                                    .font(AstralTypography.titleSmall)
                                Image(systemName: "chevron.down")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(AstralColors.muted)
                            }
                        }
                        .tint(AstralColors.gold)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 16) {
                            Button {
                                showFilter = true
                            } label: {
                                Image(systemName: navigation.filterState.isActive
                                    ? "line.3.horizontal.decrease.circle.fill"
                                    : "line.3.horizontal.decrease.circle")
                                    .foregroundStyle(navigation.filterState.isActive ? AstralColors.gold : AstralColors.body)
                            }
                            .buttonStyle(PressButtonStyle(scale: 0.88))

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
            .environment(\.comicNavigation, navigation)
            .onAppear {
                if let data = filterPrefsJSON.data(using: .utf8),
                   let prefs = try? JSONDecoder().decode(ComicFilterPrefs.self, from: data) {
                    navigation.filterState.load(from: prefs)
                }
            }
            .onChange(of: navigation.filterState.snapshotForPersistence.sortBy) { _, _ in saveFilterPrefs() }
            .onChange(of: navigation.filterState.snapshotForPersistence.showArchived) { _, _ in saveFilterPrefs() }
            .onChange(of: navigation.filterState.snapshotForPersistence.completionStatus) { _, _ in saveFilterPrefs() }
            .onChange(of: navigation.filterState.snapshotForPersistence.sourceKey) { _, _ in saveFilterPrefs() }
            .onChange(of: navigation.filterState.snapshotForPersistence.tagsKeyword) { _, _ in saveFilterPrefs() }
            .sheet(isPresented: $showFilter) {
                ComicFilterView(filterState: navigation.filterState)
                    .presentationDetents([.medium, .large])
            }

            // Sidebar overlay
            ComicSidebarView(
                isOpen: $navigation.isSidebarOpen,
                activeSection: $navigation.activeSection
            )
        }
    }

    private func saveFilterPrefs() {
        if let data = try? JSONEncoder().encode(navigation.filterState.snapshotForPersistence),
           let str = String(data: data, encoding: .utf8) {
            filterPrefsJSON = str
        }
    }
}

@Observable
final class ComicNavigation {
    var activeSection: ComicSection = .library
    var isSidebarOpen = false
    var searchText = ""
    var filterState = ComicFilterState()

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
