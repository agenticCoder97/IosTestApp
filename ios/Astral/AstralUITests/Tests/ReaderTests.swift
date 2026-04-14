import XCTest

/// Focused tests on reader robustness — gestures, chapter navigation, dismiss.
final class ReaderTests: BaseTestCase {

    // MARK: - Comic Reader

    func testComicReaderDoesNotHangOnChapterLoad() {
        let library = ComicLibraryScreen(app: app)
        let detail = library.tapFirstStory()
        detail.tapChapter(1)

        let reader = ComicReaderScreen(app: app)
        reader.assertVisible()

        // Verify the reader is interactive (not frozen)
        // Scrolling should not freeze the app
        reader.scrollDown()
        reader.assertVisible()
    }

    func testComicReaderPagedModeSwipe() {
        let library = ComicLibraryScreen(app: app)
        let detail = library.tapFirstStory()
        detail.tapChapter(1)

        let reader = ComicReaderScreen(app: app)
        reader.assertVisible()

        // Swipe through a few pages
        reader.swipeToNextPage()
        reader.swipeToNextPage()
        reader.swipeToPreviousPage()

        // Reader should still be responsive
        reader.assertVisible()
    }

    // MARK: - Fanfic Reader

    func testFanficReaderBackButtonAlwaysVisible() {
        // Navigate to fanfic reader
        let tabMenu = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Comics'")
        ).firstMatch
        tabMenu.waitAndTap()
        app.buttons["Fan Fiction"].waitAndTap()

        let library = FanficLibraryScreen(app: app)
        let detail = library.tapFirstStory()
        detail.tapChapter(1)

        let reader = FanficReaderScreen(app: app)
        reader.assertVisible()

        // Back button should be visible
        XCTAssertTrue(reader.backButton.exists, "Back button should be visible")

        // Tap to toggle settings bar
        reader.toggleSettingsBar()
        sleep(1) // Allow animation to complete

        // Back button should still be visible (we fixed this — always visible)
        XCTAssertTrue(reader.backButton.exists, "Back button should remain visible after settings toggle")
    }

    // MARK: - Stress: Rapid Open/Close

    func testRapidOpenCloseComicReader() {
        let library = ComicLibraryScreen(app: app)
        let detail = library.tapFirstStory()

        for i in 1...3 {
            detail.tapChapter(1)
            let reader = ComicReaderScreen(app: app)
            reader.assertVisible()
            reader.dismiss()
            // Verify we're back on detail
            detail.chaptersTab.assertExists()
            captureScreenshot(named: "rapid-open-close-\(i)")
        }
    }
}
