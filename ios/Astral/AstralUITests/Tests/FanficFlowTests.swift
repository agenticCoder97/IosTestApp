import XCTest

/// Tests for the fanfic reading flow: switch tab → library → detail → reader → dismiss.
final class FanficFlowTests: BaseTestCase {

    /// Helper to navigate to the fanfic tab.
    private func navigateToFanficTab() -> FanficLibraryScreen {
        // Switch from default Comic tab to Fanfic tab
        let tabMenuButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Comics'")
        ).firstMatch
        tabMenuButton.waitAndTap()
        app.buttons["Fan Fiction"].waitAndTap()
        return FanficLibraryScreen(app: app)
    }

    func testSwitchToFanficAndSeeLibrary() {
        let library = navigateToFanficTab()
        library.assertVisible()
    }

    func testOpenFanficDetailFromLibrary() {
        let library = navigateToFanficTab()

        let detail = library.tapFirstStory()
        detail.chaptersTab.assertExists()
    }

    func testOpenFanficReaderFromDetail() {
        let library = navigateToFanficTab()
        let detail = library.tapFirstStory()

        // Tap chapter 1
        detail.tapChapter(1)

        // Fanfic reader should appear (presented as fullScreenCover)
        let reader = FanficReaderScreen(app: app)
        reader.assertVisible()
    }

    func testDismissFanficReader() {
        let library = navigateToFanficTab()
        let detail = library.tapFirstStory()
        detail.tapChapter(1)

        let reader = FanficReaderScreen(app: app)
        reader.assertVisible()

        // Dismiss via floating back button
        reader.dismiss()

        // Should be back on detail view
        detail.chaptersTab.assertExists()
    }

    func testFanficReaderScrollContent() {
        let library = navigateToFanficTab()
        let detail = library.tapFirstStory()
        detail.tapChapter(1)

        let reader = FanficReaderScreen(app: app)
        reader.assertVisible()

        // Scroll through content
        reader.scrollDown()
        reader.scrollDown()
        reader.scrollDown()

        // Reader should still be responsive
        reader.assertVisible()

        captureScreenshot(named: "fanfic-reader-scrolled")
    }

    func testFanficContinueReadingButton() {
        let library = navigateToFanficTab()
        let detail = library.tapFirstStory()

        // If the story has been partially read, continue reading should appear
        if detail.continueReadingButton.waitToAppear(timeout: 5) {
            detail.tapContinueReading()

            let reader = FanficReaderScreen(app: app)
            reader.assertVisible()
            reader.dismiss()
        }
        // If not partially read, continue button may not exist — that's OK
    }
}
