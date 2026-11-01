import XCTest

/// Second factor after the password.
struct SecondFactorScreen: Screen {
    let app: XCUIApplication
    var anchor: XCUIElement { app.staticTexts["Zweiter Faktor"] }
    var codeField: XCUIElement { app.textFields["Code"] }
    var confirmButton: XCUIElement { app.buttons["Bestätigen"] }

    func confirm(code: String) {
        fill(codeField, with: code)
        wait(for: confirmButton, "enabled == true")
        confirmButton.tap()
    }

    func assertConfirmDisabledUntilSixDigits() {
        assertShows("6-stelligen Code")
        XCTAssertFalse(confirmButton.isEnabled)
        assertHitArea(confirmButton)
    }

    func assertWrongCode() {
        assertShows("Der Code stimmt nicht.")
    }
}
