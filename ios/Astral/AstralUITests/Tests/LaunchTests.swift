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

/// The embedded browser must end above the tab bar, including its floating style.
final class AddScreenLayoutTests: XCTestCase {
    @MainActor
    func testComicAddLayoutAndFolderPicker() {
        checkAddScreen(contentType: "comic", importID: "comic.browser.fileImport")
    }

    @MainActor
    func testFanficAddLayoutAndTextPicker() {
        checkAddScreen(contentType: "fanfic", importID: "fanfic.browser.fileImport")
    }

    @MainActor
    private func checkAddScreen(contentType: String, importID: String) {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "-activeContentType", contentType]
        app.launch()
        defer { app.terminate() }
        // Bind to the native bar before the browser introduces remote WebKit AX elements.
        let bar = app.tabBars.allElementsBoundByAccessibilityElement.first { $0.buttons["Add"].isHittable }
        XCTAssertNotNil(bar)
        guard let bar else { return }
        let addTab = bar.buttons["Add"]
        addTab.tap()
        let localImport = app.buttons[importID]
        XCTAssertTrue(localImport.waitForExistence(timeout: 5))
        XCTAssertTrue(localImport.isHittable)
        XCTAssertLessThanOrEqual(localImport.frame.width, 60, "File import should remain an icon-sized toolbar action")
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 10))
        XCTAssertTrue(addTab.isHittable, "The active tab bar must remain available on Add")
        XCTAssertLessThanOrEqual(web.frame.maxY, bar.frame.minY + 1, "The tab bar must not cover the browser viewport")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Add-\(contentType)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        localImport.tap()
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "The compact import action must open Files")
        cancel.tap()
        XCTAssertTrue(localImport.waitForExistence(timeout: 5))
    }
}
