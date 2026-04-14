import XCTest

/// Tests for tab switching and sidebar navigation.
final class NavigationTests: BaseTestCase {

    func testTabSwitchComicToFanfic() {
        // Starts on Comics tab (default with --uitesting)
        let comicLibrary = ComicLibraryScreen(app: app)
        comicLibrary.assertVisible()

        // Open the tab menu and switch to Fan Fiction
        // The menu is the top-left button showing "Comics" with a chevron
        let tabMenuButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Comics' OR label CONTAINS 'Fan Fiction'")
        ).firstMatch
        tabMenuButton.waitAndTap()

        // Tap "Fan Fiction" in the menu
        app.buttons["Fan Fiction"].waitAndTap()

        // Verify we're on the fanfic tab
        let fanficLibrary = FanficLibraryScreen(app: app)
        fanficLibrary.assertVisible()
    }

    func testSidebarNavigationToStats() {
        let comicLibrary = ComicLibraryScreen(app: app)
        comicLibrary.assertVisible()

        // Open sidebar (the hamburger menu button)
        app.buttons["sidebar.toggle"].waitAndTap()

        // Tap Stats
        let sidebar = SidebarScreen(app: app)
        sidebar.tapStats()

        // Verify stats view is showing
        XCTAssertTrue(app.staticTexts["Stats"].waitForExistence(timeout: 5) ||
                      app.staticTexts["Reading Stats"].waitForExistence(timeout: 5),
                      "Stats view should be visible")
    }
}
