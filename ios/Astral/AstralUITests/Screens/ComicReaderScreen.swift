import XCTest

/// Page object for the ComicReaderView (full-screen cover).
struct ComicReaderScreen {
    let app: XCUIApplication

    // MARK: - Elements

    var backButton: XCUIElement { app.buttons["reader.back"] }
    var container: XCUIElement { app.otherElements["reader.comic.container"] }

    /// The first image element visible in the reader.
    var firstPageImage: XCUIElement { app.images.firstMatch }

    // MARK: - Actions

    /// Dismisses the reader by tapping the floating back button.
    func dismiss() {
        backButton.waitAndTap()
    }

    /// Taps the center of the screen to toggle the HUD.
    func toggleHUD() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// Swipes left to go to the next page (paged mode).
    func swipeToNextPage() {
        app.swipeLeft()
    }

    /// Swipes right to go to the previous page (paged mode).
    func swipeToPreviousPage() {
        app.swipeRight()
    }

    /// Scrolls down in webtoon mode.
    func scrollDown() {
        app.swipeUp()
    }

    // MARK: - Assertions

    func assertVisible() {
        backButton.assertExists()
    }
}
