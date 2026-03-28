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
                    case .stats:
                        StatsView()
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        HStack(spacing: 12) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    onSwitchTab()
                                }
                            } label: {
                                Image(systemName: "scroll.fill")
                                    .font(.title3)
                                    .foregroundStyle(AstralColors.body)
                            }

                            Text(navigation.activeSection.rawValue)
                                .font(AstralTypography.title)
                                .foregroundStyle(AstralColors.white)
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
}

enum ComicSection: String, CaseIterable {
    case library = "Library"
    case favourites = "Favourites"
    case read = "Continue Reading"
    case browse = "Browse"
    case scrapes = "Scrapes"
    case stats = "Stats"

    var icon: String {
        switch self {
        case .library: "books.vertical"
        case .favourites: "heart.fill"
        case .read: "book"
        case .browse: "globe"
        case .scrapes: "arrow.down.circle"
        case .stats: "chart.bar"
        }
    }
}

#Preview {
    ComicTabView()
}
