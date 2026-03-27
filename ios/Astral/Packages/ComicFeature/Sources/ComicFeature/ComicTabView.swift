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
                        ComicLibraryView()
                    case .read:
                        ComicLibraryView() // Filtered to in-progress reads
                    case .browse:
                        ComicBrowserView()
                    case .scrapes:
                        ComicScrapesView()
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
                            
                            Text("Comics")
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
    case read = "Read"
    case browse = "Browse"
    case scrapes = "Scrapes"

    var icon: String {
        switch self {
        case .library: "books.vertical"
        case .read: "book"
        case .browse: "globe"
        case .scrapes: "arrow.down.circle"
        }
    }
}

#Preview {
    ComicTabView()
}
