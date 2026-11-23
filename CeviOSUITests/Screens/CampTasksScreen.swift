import XCTest

/// Task list (L5) and one task (L7).
struct CampTasksScreen: Screen {
    let app: XCUIApplication
    var anchor: XCUIElement { app.navigationBars["Aufgaben"] }

    /// The row button starts with the title; the «Weitere Aktionen für …» menu next to it only contains it.
    func row(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    /// Switches the view (Liste, Kanban, Zeitplan) in the options menu; the screen title follows the view.
    func show(_ view: String) {
        button("Ansicht, Sortierung und Filter").tap()
        app.buttons[view].firstMatch.tap()
    }

    func open(_ title: String) -> CampTaskDetailScreen {
        scrollUntilHittable(row(title)).tap()
        return CampTaskDetailScreen(app: app, title: title).waitUntilDisplayed()
    }
}

struct CampTaskDetailScreen: Screen {
    let app: XCUIApplication
    let title: String
    /// The big status button exists for everyone who may change the status.
    var anchor: XCUIElement { app.staticTexts[title].firstMatch }

    /// The wide button at the bottom; the status chip of the same name in the scroll view is narrow.
    var doneButton: XCUIElement {
        app.buttons.matching(identifier: "Erledigt").allElementsBoundByIndex.first { $0.frame.width > 200 } ?? app.buttons["Erledigt (Knopf unten)"]
    }
    var reopenButton: XCUIElement { app.buttons["Wieder öffnen"] }

    func markDone() {
        doneButton.tap()
        XCTAssertTrue(reopenButton.waitForExistence(timeout: 10), "status did not change to done")
    }

    /// Ticks a checklist item; its label says the state in words.
    func tick(_ item: String) {
        scrollUntilHittable(element(containing: "\(item), offen")).tap()
        XCTAssertTrue(element(containing: "\(item), erledigt").waitForExistence(timeout: 10), "\(item) not ticked")
    }

    func assertConflict(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.staticTexts["Jemand hat diese Aufgabe gerade geändert."].waitForExistence(timeout: 10), "no conflict dialog", file: file, line: line)
    }

    func auditConflict(file: StaticString = #filePath, line: UInt = #line) throws {
        try AccessibilityAudit.run(on: app, screen: "CampConflictScreen", file: file, line: line)
    }

    func keepMine() {
        button("Meine behalten").tap()
    }
}
