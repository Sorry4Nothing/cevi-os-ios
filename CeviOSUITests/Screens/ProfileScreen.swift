import XCTest

/// T10 Profil: own data, groups, calendar link, app settings, sign-out.
struct ProfileScreen: Screen {
    let app: XCUIApplication
    var anchor: XCUIElement { app.navigationBars["Profil"] }

    /// A7 Benachrichtigungen from the row in the «App» section.
    func openNotifications() -> NotificationsScreen {
        tap("Benachrichtigungen")
        return NotificationsScreen(app: app).waitUntilDisplayed()
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
