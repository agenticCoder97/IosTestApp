import XCTest

/// Page object for both ComicDetailView and FanficDetailView.
/// Shared because both have chapters tab, continue reading, and bookmarks.
struct StoryDetailScreen {
    let app: XCUIApplication

    // MARK: - Elements

    var continueReadingButton: XCUIElement { app.buttons["detail.continue_reading"] }
    var chaptersTab: XCUIElement { app.buttons["Chapters"] }
    var bookmarksTab: XCUIElement { app.buttons["Bookmarks"] }
    var backButton: XCUIElement { app.navigationBars.buttons.firstMatch }

    /// Returns a chapter row button by chapter number.
    func chapterRow(_ number: Int) -> XCUIElement {
        app.buttons["detail.chapter.\(number)"]
    }

    // MARK: - Actions

    /// Taps the Continue Reading button.
    func tapContinueReading() {
        continueReadingButton.waitAndTap()
    }

    /// Taps a specific chapter by number.
    func tapChapter(_ number: Int) {
        chapterRow(number).waitAndTap()
    }

    /// Navigates back to the library.
    func goBack() {
        backButton.waitAndTap()
    }

    // MARK: - Assertions

    func assertChapterExists(_ number: Int) {
        chapterRow(number).assertExists()
    }

    func assertContinueReadingVisible() {
        continueReadingButton.assertExists()
    }
}
