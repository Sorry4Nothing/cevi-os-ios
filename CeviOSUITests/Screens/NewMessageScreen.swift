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
        tap("Schliessen")
        waitUntilGone(anchor)
    }
}
