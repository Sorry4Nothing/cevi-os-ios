import XCTest

/// Attendance tab: the units the person leads.
struct AttendanceListScreen: Screen {
    let app: XCUIApplication
    var anchor: XCUIElement { app.navigationBars["Anwesenheit"] }

    func open(_ unit: String) -> AttendanceScreen {
        assertHitArea(button(unit))
        tap(unit)
        return AttendanceScreen(app: app, unit: unit).waitUntilDisplayed()
    }
}
