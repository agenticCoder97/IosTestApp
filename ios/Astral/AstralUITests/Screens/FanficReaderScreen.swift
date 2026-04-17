import XCTest

/// Page object for the FanficReaderView (full-screen cover).
struct FanficReaderScreen {
    let app: XCUIApplication

    // MARK: - Elements

    var backButton: XCUIElement { app.buttons["reader.back"] }

    /// Chapter text content — any static text in the reader's scroll view.
    var chapterText: XCUIElement { app.scrollViews.firstMatch.staticTexts.firstMatch }

    // MARK: - Actions

    /// Dismisses the reader by tapping the floating back button.
    func dismiss() {
        backButton.waitAndTap()
    }

    /// Taps the center to toggle the reader settings bar.
    func toggleSettingsBar() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// Scrolls down to read more content.
    func scrollDown() {
        app.swipeUp()
    }

    /// Swipes left to go to next chapter (horizontal paging).
    func swipeToNextChapter() {
        app.swipeLeft()
    }

    /// Swipes right to go to previous chapter (horizontal paging).
    func swipeToPreviousChapter() {
        app.swipeRight()
    }

    // MARK: - Assertions

    func assertVisible() {
        backButton.assertExists()
    }

    func assertContentLoaded() {
        let hasText = chapterText.waitToAppear(timeout: 15)
        XCTAssertTrue(hasText, "Chapter content should have loaded")
    }
}
