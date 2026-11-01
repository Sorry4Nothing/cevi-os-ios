import XCTest

/// Sheet for parents: which unit leaders get the message.
struct NewMessageScreen: Screen {
    let app: XCUIApplication
    var anchor: XCUIElement { app.navigationBars["Neue Nachricht"] }

    func write(for child: String, unit: String) -> ChatScreen {
        assertShows("An welche Stufenleitung")
        let row = button(containing: "Stufenleitung \(unit)", "Für \(child)")
        assertHitArea(row)
        row.tap()
        return ChatScreen(app: app, title: "Stufenleitung \(unit)").waitUntilDisplayed()
    }

    func close() {
        // A toolbar button sits at the top edge of the sheet, above the "reachable" band of `scrollUntilHittable`.
        let close = button("Schliessen")
        XCTAssertTrue(close.waitForExistence(timeout: 10) && close.isHittable, "\(name): «Schliessen» not reachable")
        assertHitArea(close)
        close.tap()
        waitUntilGone(anchor)
    }
}
