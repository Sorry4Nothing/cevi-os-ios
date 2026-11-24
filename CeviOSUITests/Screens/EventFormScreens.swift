import XCTest

/// K1 Termin vorschlagen.
struct SuggestEventScreen: Screen {
    let app: XCUIApplication
    var anchor: XCUIElement { app.navigationBars["Termin vorschlagen"] }
    func group(_ name: String) -> XCUIElement { app.buttons[name] }
    func send() { tap("Vorschlag senden") }
}

/// K2 Raum anfragen.
struct RequestRoomScreen: Screen {
    let app: XCUIApplication
    var anchor: XCUIElement { app.navigationBars["Raum anfragen"] }
    func room(_ name: String) -> XCUIElement { button(containing: name) }
    func send() { tap("Raum anfragen") }

    /// «Meine Raumanfragen» in the bottom bar; the back button of the screen has the same title, but sits at the top.
    func openRequests() {
        let candidates = app.buttons.matching(NSPredicate(format: "label == 'Meine Raumanfragen'")).allElementsBoundByIndex
        XCTAssertTrue(app.buttons["Meine Raumanfragen"].waitForExistence(timeout: 10))
        let bar = candidates.max { $0.frame.minY < $1.frame.minY }
        bar?.tap()
    }
}

/// K3 Meine Raumanfragen.
struct MyRoomRequestsScreen: Screen {
    let app: XCUIApplication
    var anchor: XCUIElement { app.navigationBars["Meine Raumanfragen"] }
}

extension ProgramListScreen {
    /// The «+» menu of the Programme tab.
    func openMenu(_ item: String) {
        let menu = app.buttons["Termine und Räume"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.tap()
        let entry = app.buttons[item]
        XCTAssertTrue(entry.waitForExistence(timeout: 10), "menu item \(item)")
        entry.tap()
    }
}
