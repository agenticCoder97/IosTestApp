import XCTest

/// Launch choreography must finish by itself and leave the library usable.
final class LaunchTests: XCTestCase {
    @MainActor
    func testIllustratedIntroCoversTheLibrary() {
        let app = XCUIApplication()
        app.launchArguments = ["--intro-time=1.3"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.otherElements["launch.intro"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.buttons.matching(identifier: "Library")
            .allElementsBoundByIndex.contains { $0.isHittable })
        let artwork = XCTAttachment(screenshot: app.screenshot())
        artwork.name = "Illustrated intro"
        artwork.lifetime = .keepAlways
        add(artwork)
    }

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
