import SwiftUI
import SwiftData
import Core
import DesignSystem

public struct ComicTabView: View {
    @State private var navigation = ComicNavigation()
    @Query private var comics: [LocalComic]
    @State private var showFilter = false
    @AppStorage("comic.filter.v1") private var filterPrefsJSON = ""
    private let onSwitchTab: () -> Void
    public init(onSwitchTab: @escaping () -> Void = {}) { self.onSwitchTab = onSwitchTab }
    public var body: some View {
        TabView(selection: $navigation.activeSection) {
            NavigationStack {
                VStack(spacing: 0) {
                    AstralSearchBar(text: $navigation.searchText, isActive: $navigation.isSearchActive,
                                    placeholder: "Title, author, tag…")
                    ComicLibraryView(searchText: $navigation.searchText, filterFavourites: navigation.showFavourites)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button("Switch to Fan Fiction", action: onSwitchTab)
                        } label: { HStack(spacing: 6) { Image(systemName: "book.fill"); Text("Comics") }.font(.headline) }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 0) {
                            Button { navigation.showFavourites.toggle() } label: {
                                Image(systemName: navigation.showFavourites ? "heart.fill" : "heart")
                            }
                            .accessibilityLabel("Favourites")
                            .accessibilityValue(navigation.showFavourites ? "Showing favourites" : "Showing all")
                            .frame(minWidth: 44, minHeight: 44)
                            Button {
                                navigation.isSearchActive.toggle()
                                // A hidden search must not keep filtering the library.
                                if !navigation.isSearchActive { navigation.searchText = "" }
                            } label: { Image(systemName: "magnifyingglass") }
                                .accessibilityLabel("Search library").frame(minWidth: 44, minHeight: 44)
                            Button { showFilter = true } label: {
                                Image(systemName: navigation.filterState.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            }
                            .accessibilityLabel("Filter library").frame(minWidth: 44, minHeight: 44)
                        }
                    }
                }
            }
            .tabItem { Label("Library", systemImage: "books.vertical") }.tag(ComicSection.library)
            NavigationStack { ComicBrowserView() }
                .tabItem { Label("Add", systemImage: "plus.circle") }.tag(ComicSection.browse)
            NavigationStack {
                LocalActivityView(contentType: "comic", storyTitle: { job in comics.first { $0.id == job.storyId }?.title }, retry: { job in navigation.sourceKey = ComicSource(rawValue: job.sourceKey ?? ""); navigation.sourceURL = job.sourceUrl.flatMap(URL.init(string:)); navigation.activeSection = .browse }) { job in
                    if let story = comics.first(where: { $0.id == job.storyId }) {
                        ComicDetailView(comic: story)
                    } else { ContentUnavailableView("Story is no longer in your library", systemImage: "books.vertical") }
                }
            }
                .tabItem { Label("Activity", systemImage: "arrow.down.circle") }.tag(ComicSection.scrapes)
            NavigationStack { LibrarySettingsView { StatsView() } }
                .tabItem { Label("Settings", systemImage: "gearshape") }.tag(ComicSection.settings)
        }
        .tint(AstralColors.gold)
        .environment(\.comicNavigation, navigation)
        .onAppear {
            if let data = filterPrefsJSON.data(using: .utf8),
               let prefs = try? JSONDecoder().decode(ComicFilterPrefs.self, from: data) { navigation.filterState.load(from: prefs) }
        }
        .onChange(of: navigation.filterState.snapshotForPersistence) { _, value in
            if let data = try? JSONEncoder().encode(value), let text = String(data: data, encoding: .utf8) { filterPrefsJSON = text }
        }
        .sheet(isPresented: $showFilter) {
            ComicFilterView(filterState: navigation.filterState).presentationDetents([.medium, .large])
        }
    }
}

@Observable
final class ComicNavigation {
    var sourceURL: URL?
    var sourceKey: ComicSource?
    var activeSection: ComicSection = .library
    var isSidebarOpen = false
    var showFavourites = false
    var searchText = ""
    var isSearchActive = false
    var filterState = ComicFilterState()

    func searchFor(_ term: String) {
        searchText = term
        isSearchActive = true
        activeSection = .library
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
    ComicTabView()
}
