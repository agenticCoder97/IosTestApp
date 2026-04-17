import SwiftUI
import DesignSystem

public struct FanficTabView: View {
    @State private var navigation = FanficNavigation()
    @State private var searchText = ""
    @State private var showFilter = false
    @AppStorage("fanfic.filter.v1") private var filterPrefsJSON: String = ""
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
                        FanficLibraryView(searchText: $searchText, filterFavourites: false, filterState: navigation.filterState)
                    case .favourites:
                        FanficLibraryView(searchText: .constant(""), filterFavourites: true, filterState: navigation.filterState)
                    case .browse:
                        FanficBrowserView()
                    case .scrapes:
                        FanficScrapesView()
                    case .downloads:
                        FanficLibraryView(searchText: $searchText, filterFavourites: false, filterState: navigation.filterState)
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
                            HStack(spacing: 6) {
                                Image(systemName: "scroll.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Fan Fiction")
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
                                // TODO: Show search
                            } label: {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(AstralColors.body)
                            }
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
            .onAppear {
                if let data = filterPrefsJSON.data(using: .utf8),
                   let prefs = try? JSONDecoder().decode(FanficFilterPrefs.self, from: data) {
                    navigation.filterState.load(from: prefs)
                }
            }
            .onChange(of: navigation.filterState.snapshotForPersistence.sortBy) { _, _ in saveFilterPrefs() }
            .onChange(of: navigation.filterState.snapshotForPersistence.fandom) { _, _ in saveFilterPrefs() }
            .onChange(of: navigation.filterState.snapshotForPersistence.completionStatus) { _, _ in saveFilterPrefs() }
            .onChange(of: navigation.filterState.snapshotForPersistence.sourceKey) { _, _ in saveFilterPrefs() }
            .sheet(isPresented: $showFilter) {
                FanficFilterView(filterState: navigation.filterState)
                    .presentationDetents([.medium, .large])
            }

            FanficSidebarView(
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
final class FanficNavigation {
    var activeSection: FanficSection = .library
    var isSidebarOpen = false
    var filterState = FanficFilterState()
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
