import XCTest

/// T02 Passwort: own password after the first sign-in.
struct ChangePasswordScreen: Screen {
    let app: XCUIApplication
    var anchor: XCUIElement { app.staticTexts["Eigenes Passwort wählen"] }
    var newField: XCUIElement { app.secureTextFields["Neues Passwort"] }
    var saveButton: XCUIElement { app.buttons["Passwort speichern"] }

    /// The start password of the sign-in stays in memory, so only the new password is asked. The rule is announced in words.
    func changePassword(current: String, new: String) {
        fill(newField, with: String(new.prefix(4)), isSecure: true)
        wait(for: newField, "value.length == 4")
        assertShows("Mindestens 12 Zeichen, nicht erfüllt")
        XCTAssertFalse(saveButton.isEnabled)
        app.typeText(String(new.dropFirst(4)))
        assertShows("Mindestens 12 Zeichen, erfüllt")
        wait(for: saveButton, "enabled == true")
        saveButton.tap()
    }
}
