import XCTest

extension XCUIElement {

    /// Waits for the element to exist with a default timeout, then taps it.
    /// Fails the test if the element does not appear within the timeout.
    @discardableResult
    func waitAndTap(timeout: TimeInterval = BaseTestCase.defaultTimeout,
                    file: StaticString = #file, line: UInt = #line) -> Self {
        let appeared = waitForExistence(timeout: timeout)
        XCTAssertTrue(appeared, "Element \(identifier) did not appear within \(timeout)s", file: file, line: line)
        tap()
        return self
    }

    /// Waits for the element to exist. Returns `true` if it appeared.
    func waitToAppear(timeout: TimeInterval = BaseTestCase.defaultTimeout) -> Bool {
        waitForExistence(timeout: timeout)
    }

    /// Asserts that the element exists after waiting.
    func assertExists(timeout: TimeInterval = BaseTestCase.defaultTimeout,
                      file: StaticString = #file, line: UInt = #line) {
        let appeared = waitForExistence(timeout: timeout)
        XCTAssertTrue(appeared, "Expected \(identifier) to exist", file: file, line: line)
    }

    /// Asserts that the element does NOT exist after a brief wait.
    func assertNotExists(timeout: TimeInterval = 3,
                         file: StaticString = #file, line: UInt = #line) {
        let appeared = waitForExistence(timeout: timeout)
        XCTAssertFalse(appeared, "Expected \(identifier) to not exist", file: file, line: line)
    }
}
