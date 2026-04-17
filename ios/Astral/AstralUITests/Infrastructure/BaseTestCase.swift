import XCTest

/// Base class for all Astral UI tests.
/// Launches the app with `--uitesting` to skip the landing animation
/// and configures shared timeout/cleanup behavior.
class BaseTestCase: XCTestCase {

    var app: XCUIApplication!

    /// Default timeout for element existence checks.
    static let defaultTimeout: TimeInterval = 10

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    override func tearDownWithError() throws {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Teardown-\(name)"
        attachment.lifetime = .deleteOnSuccess
        add(attachment)
        app = nil
    }

    /// Captures a screenshot and attaches it to the test report.
    func captureScreenshot(named name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
