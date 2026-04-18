import XCTest

/// Page object for the comic library (ComicTabView → ComicLibraryView).
struct ComicLibraryScreen {
    let app: XCUIApplication

    // MARK: - Elements

    var navigationTitle: XCUIElement { app.staticTexts["Comics"] }
    var sidebarToggle: XCUIElement { app.buttons["sidebar.toggle"] }
    var searchToggle: XCUIElement { app.buttons.matching(NSPredicate(format: "label CONTAINS 'magnifyingglass'")).firstMatch }

    /// Returns the first story card in the library.
    var firstStoryCard: XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library.story.'")).firstMatch
    }

    // MARK: - Actions

    /// Taps on a story card by its displayed title.
    @discardableResult
    func tapStory(title: String) -> StoryDetailScreen {
        let card = app.staticTexts[title].firstMatch
        card.waitAndTap()
        return StoryDetailScreen(app: app)
    }

    /// Taps the first available story card.
    @discardableResult
    func tapFirstStory() -> StoryDetailScreen {
        firstStoryCard.waitAndTap()
        return StoryDetailScreen(app: app)
    }

    /// Opens the sidebar.
    func openSidebar() -> SidebarScreen {
        sidebarToggle.waitAndTap()
        return SidebarScreen(app: app)
    }

    // MARK: - Assertions

    func assertVisible() {
        navigationTitle.assertExists()
    }
}
