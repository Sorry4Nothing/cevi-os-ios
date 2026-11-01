import XCTest

/// T01 Anmeldung.
struct SignInScreen: Screen {
    let app: XCUIApplication
    var anchor: XCUIElement { app.staticTexts["Schön, bist du da."] }
    var usernameField: XCUIElement { app.textFields["Benutzername"] }
    var passwordField: XCUIElement { app.secureTextFields["Passwort"] }
    var signInButton: XCUIElement { app.buttons["Anmelden"] }

    /// Types both fields (tapping the edge of each box) and submits with the return key (the keyboard may cover the button).
    func signIn(username: String, password: String) {
        fill(usernameField, with: username)
        fill(passwordField, with: password, isSecure: true)
        app.typeText("\n")
    }

    func submitEmpty() {
        tap("Anmelden")
        assertShows("Bitte Benutzername und Passwort eingeben.")
    }

    /// A freshly shown sign-in (after sign-out or an ended session) no longer holds the typed username.
    func waitUntilReset(after username: String) {
        waitUntilDisplayed()
        wait(for: usernameField, "NOT (value CONTAINS %@)", username)
    }

    func assertControls() {
        assertShows("Cevi OS")
        assertHitArea(button("Passwort anzeigen"))
        assertHitArea(signInButton)
    }
}
