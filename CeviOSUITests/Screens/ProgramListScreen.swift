import XCTest

/// Programs of the next months by day.
struct ProgramListScreen: Screen {
    let app: XCUIApplication
    var anchor: XCUIElement { app.navigationBars["Programme"] }

    /// A program card; multi-day programs have one per day.
    func row(_ title: String) -> XCUIElement { button(containing: title) }

    /// The card says everything in words: time, unit, status and every child's answer.
    func assertRow(_ title: String, shows parts: String..., file: StaticString = #filePath, line: UInt = #line) {
        let card = scrollUntilHittable(row(title), file: file, line: line)
        for part in parts {
            wait(for: card, "label CONTAINS %@", part, file: file, line: line)
        }
        assertHitArea(card, file: file, line: line)
    }

    func assertMultiDay(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let cards = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title))
        scrollUntilHittable(cards.element(boundBy: 1), file: file, line: line)
        XCTAssertGreaterThanOrEqual(cards.count, 2, "\(title) must show on each day", file: file, line: line)
    }

    func open(_ title: String) -> ProgramDetailScreen {
        scrollUntilHittable(row(title)).tap()
        return ProgramDetailScreen(app: app, title: title).waitUntilDisplayed()
    }
}
