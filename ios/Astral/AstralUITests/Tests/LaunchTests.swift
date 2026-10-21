import XCTest

/// Launch choreography must finish by itself and leave the library usable.
final class LaunchTests: XCTestCase {
    @MainActor
    func testIntroFinishesWithoutInteraction() {
        let app = XCUIApplication()
        app.launch()
        defer { app.terminate() }
        let intro = app.otherElements["launch.intro"]
        XCTAssertTrue(intro.waitForNonExistence(timeout: 8))
        XCTAssertTrue(app.tabBars.buttons["Library"].waitForExistence(timeout: 3))
        let library = app.tabBars.buttons.matching(identifier: "Library")
            .allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(library, app.debugDescription)
    }

    @MainActor
    func testUITestingBypassesIntro() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.tabBars.buttons["Library"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["launch.intro"].exists)
    }
}
