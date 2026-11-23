import XCTest

/// Start of the camp view (L2 camp lead, L3 team) with the camp tab bar.
struct CampStartScreen: Screen {
    let app: XCUIApplication
    let campTitle: String
    var anchor: XCUIElement { app.staticTexts[campTitle].firstMatch }

    func tab(_ title: String) -> XCUIElement { app.tabBars.buttons[title] }

    func open(_ title: String) {
        tab(title).tap()
        assertSelected(tab(title))
    }

    func assertTabs(_ shown: [String], hidden: [String], file: StaticString = #filePath, line: UInt = #line) {
        for title in shown { XCTAssertTrue(tab(title).exists, "tab \(title)", file: file, line: line) }
        for title in hidden { XCTAssertFalse(tab(title).exists, "tab \(title) must be absent", file: file, line: line) }
    }
}
