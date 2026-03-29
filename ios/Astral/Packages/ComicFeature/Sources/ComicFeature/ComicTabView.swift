import SwiftUI
import DesignSystem

public struct ComicTabView: View {
    @State private var navigation = ComicNavigation()
    @State private var showFilter = false
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
                        placeholder: "Title, tag, author, description..."
                    )

                    // Main content
                    Group {
                        switch navigation.activeSection {
                        case .library:
                            ComicLibraryView(searchText: $navigation.searchText, filterFavourites: false)
                        case .favourites:
                            ComicLibraryView(searchText: .constant(""), filterFavourites: true)
                        case .browse:
                            ComicBrowserView()
                        case .scrapes:
                            ComicScrapesView()
                        case .stats:
                            StatsView()
                        }
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
                            HStack(spacing: 8) {
                                Image(systemName: "book.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("Comics")
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
                                showFilter = true
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
            .sheet(isPresented: $showFilter) {
                ComicFilterSheet()
                    .presentationDetents([.medium])
            }
            .environment(\.comicNavigation, navigation)

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
    var isSearchActive = false

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

// MARK: - Comic Filter Sheet

private struct ComicFilterSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Comic filters coming soon.")
                    .font(AstralTypography.body)
                    .foregroundStyle(AstralColors.muted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 40)
                Spacer()
            }
            .background(AstralColors.background)
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(AstralColors.gold)
                }
            }
        }
    }
}

#Preview {
    ComicTabView()
}
