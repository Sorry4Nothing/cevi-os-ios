import XCTest

/// T02 Passwort: own password after the first sign-in.
struct ChangePasswordScreen: Screen {
    let app: XCUIApplication
    var anchor: XCUIElement { app.staticTexts["Eigenes Passwort wählen"] }
    var currentField: XCUIElement { app.secureTextFields["Startpasswort"] }
    var newField: XCUIElement { app.secureTextFields["Neues Passwort"] }
    var repeatField: XCUIElement { app.secureTextFields["Passwort wiederholen"] }
    var saveButton: XCUIElement { app.buttons["Passwort speichern"] }

    /// Goes through the validation (too short, not equal) before saving. Rules are announced in words.
    /// Moves between the fields with the return key, as the keyboard leaves the last field under the action bar.
    func changePassword(current: String, new: String) {
        fill(currentField, with: current, isSecure: true)
        app.typeText("\n")
        app.typeText(String(new.prefix(4)))
        wait(for: newField, "value.length == 4")
        assertShows("Mindestens 12 Zeichen, nicht erfüllt")
        XCTAssertFalse(saveButton.isEnabled)
        app.typeText(String(new.dropFirst(4)))
        assertShows("Mindestens 12 Zeichen, erfüllt")

        app.typeText("\n")
        app.typeText(new + "x")
        wait(for: repeatField, "value.length == %d", new.count + 1)
        assertShows("Die beiden neuen Passwörter sind nicht gleich.")
        XCTAssertFalse(saveButton.isEnabled)
        app.typeText(XCUIKeyboardKey.delete.rawValue)
        assertShows("Stimmt überein, erfüllt")
        wait(for: saveButton, "enabled == true")
        saveButton.tap()
    }
}
