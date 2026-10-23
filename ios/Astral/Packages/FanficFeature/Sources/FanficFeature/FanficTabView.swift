import SwiftUI
import SwiftData
import Core
import DesignSystem

public struct FanficTabView: View {
    @State private var navigation = FanficNavigation()
    @Query private var fanfics: [LocalFanfic]
    @State private var showFilter = false
    @AppStorage("fanfic.filter.v1") private var filterPrefsJSON = ""
    private let onSwitchTab: () -> Void
    public init(onSwitchTab: @escaping () -> Void = {}) { self.onSwitchTab = onSwitchTab }
    public var body: some View {
        TabView(selection: $navigation.activeSection) {
            NavigationStack {
                VStack(spacing: 0) {
                    AstralSearchBar(text: $navigation.searchText, isActive: $navigation.isSearchActive,
                                    placeholder: "Title, author, tag…")
                    FanficLibraryView(searchText: $navigation.searchText, filterFavourites: navigation.showFavourites, filterState: navigation.filterState)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button("Switch to Comics", action: onSwitchTab)
                        } label: { HStack(spacing: 6) { Image(systemName: "scroll.fill"); Text("Fan Fiction") }.font(.headline) }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 0) {
                            Button { navigation.showFavourites.toggle() } label: {
                                Image(systemName: navigation.showFavourites ? "heart.fill" : "heart")
                            }
                            .accessibilityLabel("Favourites")
                            .accessibilityValue(navigation.showFavourites ? "Showing favourites" : "Showing all")
                            .frame(minWidth: 44, minHeight: 44)
                            Button { navigation.isSearchActive.toggle() } label: { Image(systemName: "magnifyingglass") }
                                .accessibilityLabel("Search library").frame(minWidth: 44, minHeight: 44)
                            Button { showFilter = true } label: {
                                Image(systemName: navigation.filterState.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            }
                            .accessibilityLabel("Filter library").frame(minWidth: 44, minHeight: 44)
                        }
                    }
                }
            }
            .tabItem { Label("Library", systemImage: "books.vertical") }.tag(FanficSection.library)
            NavigationStack { FanficBrowserView() }
                .tabItem { Label("Add", systemImage: "plus.circle") }.tag(FanficSection.browse)
            NavigationStack {
                LocalActivityView(contentType: "fanfic", storyTitle: { job in fanfics.first { $0.id == job.storyId }?.title }, retry: { job in navigation.ao3WorkURL = job.sourceUrl.flatMap(URL.init(string:)); navigation.activeSection = .browse }) { job in
                    if let story = fanfics.first(where: { $0.id == job.storyId }) {
                        FanficDetailView(fanfic: story)
                    } else { ContentUnavailableView("Story is no longer in your library", systemImage: "books.vertical") }
                }
            }
                .tabItem { Label("Activity", systemImage: "arrow.down.circle") }.tag(FanficSection.scrapes)
            NavigationStack { LibrarySettingsView { FanficStatsView() } }
                .tabItem { Label("Settings", systemImage: "gearshape") }.tag(FanficSection.settings)
        }
        .tint(AstralColors.gold)
        .environment(\.fanficNavigation, navigation)
        .onAppear {
            if let data = filterPrefsJSON.data(using: .utf8),
               let prefs = try? JSONDecoder().decode(FanficFilterPrefs.self, from: data) { navigation.filterState.load(from: prefs) }
        }
        .onChange(of: navigation.filterState.snapshotForPersistence) { _, value in
            if let data = try? JSONEncoder().encode(value), let text = String(data: data, encoding: .utf8) { filterPrefsJSON = text }
        }
        .sheet(isPresented: $showFilter) {
            FanficFilterView(filterState: navigation.filterState).presentationDetents([.medium, .large])
        }
    }
}

@Observable
final class FanficNavigation {
    var ao3WorkURL: URL?
    var activeSection: FanficSection = .library
    var isSidebarOpen = false
    var showFavourites = false
    var searchText = ""
    var isSearchActive = false
    var filterState = FanficFilterState()

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
    case browse = "Add"
    case scrapes = "Activity"
    case stats = "Stats"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .library: "books.vertical"
        case .favourites: "heart.fill"
        case .browse: "globe"
        case .scrapes: "arrow.down.circle"
        case .stats: "chart.bar"
        case .settings: "gearshape"
        }
    }
}

#Preview {
    FanficTabView()
}
