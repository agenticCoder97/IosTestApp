import XCTest

/// Tests for app launch behavior.
/// With `--uitesting`, the landing screen is skipped and the app
/// goes directly to the default tab (Comics).
final class LaunchTests: BaseTestCase {

    func testAppLaunchesDirectlyToComicLibrary() {
        // With --uitesting, landing is skipped
        let comicLibrary = ComicLibraryScreen(app: app)
        comicLibrary.assertVisible()
    }

    func testLandingScreenAppearsWithoutTestFlag() {
        // Launch without --uitesting to verify landing still works
        let freshApp = XCUIApplication()
        freshApp.launchArguments = []
        freshApp.launch()

        let landing = LandingScreen(app: freshApp)
        // The landing animation takes ~4.2 seconds before tap zones appear
        XCTAssertTrue(landing.comicOrb.waitForExistence(timeout: 8),
                      "Landing comic orb should appear after animation")
        freshApp.terminate()
    }
}
