import XCTest

/// App lock (Face ID or Touch ID). The UI-test build unlocks without biometrics.
struct LockScreen: Screen {
    let app: XCUIApplication
    var anchor: XCUIElement { app.staticTexts["Cevi OS ist gesperrt"] }

    func unlock() {
        assertHitArea(button("Entsperren"))
        tap("Entsperren")
    }
}
