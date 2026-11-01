import XCTest

/// T10 Profil: own data, notifications, app settings, sign-out.
struct ProfileScreen: Screen {
    let app: XCUIApplication
    var anchor: XCUIElement { app.navigationBars["Profil"] }

    func toggle(_ label: String) -> XCUIElement { app.switches[label] }

    /// Switches a notification setting; the saved value comes back from the server.
    func setSwitch(_ label: String, on: Bool) {
        let element = scrollUntilHittable(toggle(label))
        assertHitArea(element)
        if (element.value as? String == "1") != on { flip(element) }
        wait(for: element, "value == %@", on ? "1" : "0")
    }

    @discardableResult
    func signOut(username: String) -> SignInScreen {
        tap("Abmelden")
        let alert = app.alerts["Abmelden?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        alert.buttons["Abmelden"].tap()
        let signIn = SignInScreen(app: app)
        signIn.waitUntilReset(after: username)
        return signIn
    }
}
