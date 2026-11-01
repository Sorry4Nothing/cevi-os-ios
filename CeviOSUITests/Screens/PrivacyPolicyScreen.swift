import XCTest

/// T11 Datenschutz: short version inside the app.
struct PrivacyPolicyScreen: Screen {
    let app: XCUIApplication
    var anchor: XCUIElement { app.navigationBars["Datenschutz"] }

    func assertSections() {
        assertShows("Was wir speichern", "Wer was sieht", "Was wir nicht machen", "Keine Werbung und keine Tracker")
    }
}
