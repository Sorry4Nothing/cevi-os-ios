import XCTest

final class StartTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testStartzeigtDenAppNamen() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Cevi OS"].waitForExistence(timeout: 10))
    }

    /// Apples automatische Prüfung: Kontrast, Beschriftungen, Tippflächen, Schriftgrösse.
    @MainActor
    func testBarrierefreiheitsPruefung() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Cevi OS"].waitForExistence(timeout: 10))
        try app.performAccessibilityAudit()
    }

    /// Mit der grössten Schriftstufe bleibt der Inhalt vorhanden und die Prüfung besteht.
    @MainActor
    func testGroessteSchriftstufe() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Cevi OS"].waitForExistence(timeout: 10))
        try app.performAccessibilityAudit()
    }
}
