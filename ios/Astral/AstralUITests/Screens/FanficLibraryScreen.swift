import XCTest

/// Page object for the fanfic library (FanficTabView → FanficLibraryView).
struct FanficLibraryScreen {
    let app: XCUIApplication

    // MARK: - Elements

    var navigationTitle: XCUIElement { app.staticTexts["Fan Fiction"] }

    var firstStoryCard: XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library.story.'")).firstMatch
    }

    // MARK: - Actions

    @discardableResult
    func tapStory(title: String) -> StoryDetailScreen {
        let card = app.staticTexts[title].firstMatch
        card.waitAndTap()
        return StoryDetailScreen(app: app)
    }

    @discardableResult
    func tapFirstStory() -> StoryDetailScreen {
        firstStoryCard.waitAndTap()
        return StoryDetailScreen(app: app)
    }

    // MARK: - Assertions

    func assertVisible() {
        navigationTitle.assertExists()
    }
}
