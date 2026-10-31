import XCTest

final class LaunchTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testStartShowsTheAppName() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Cevi OS"].waitForExistence(timeout: 10))
    }

    /// Apple's automatic audit: contrast, labels, hit areas, font size.
    @MainActor
    func testAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Cevi OS"].waitForExistence(timeout: 10))
        try app.performAccessibilityAudit()
    }

    /// With the largest text size the content stays present and the audit passes.
    @MainActor
    func testLargestTextSize() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Cevi OS"].waitForExistence(timeout: 10))
        try app.performAccessibilityAudit()
    }
}
