import XCTest

/// Switcher between program and camp view (top left) and the camp choice (L1).
struct CampSwitcherScreen: Screen {
    let app: XCUIApplication
    var anchor: XCUIElement { app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Ansicht wechseln'")).firstMatch }

    var chooserTitle: XCUIElement { app.navigationBars["Deine Lager"] }

    /// Opens the menu, goes to «Alle Lager» and picks the camp.
    func openChooser() {
        waitUntilDisplayed()
        anchor.tap()
        button(containing: "Alle Lager").tap()
        XCTAssertTrue(chooserTitle.waitForExistence(timeout: 10), "camp choice not shown")
    }

    func choose(_ camp: String) {
        scrollUntilHittable(button(containing: camp)).tap()
    }

    func auditChooser(file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertTrue(chooserTitle.waitForExistence(timeout: 10), file: file, line: line)
        waitUntilGone(element(containing: "Lädt"), file: file, line: line)
        try AccessibilityAudit.run(on: app, screen: "CampChooserScreen", file: file, line: line)
    }
}
