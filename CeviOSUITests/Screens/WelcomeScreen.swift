import XCTest

/// T03 Willkommen: confirm the privacy statement on the first sign-in.
struct WelcomeScreen: Screen {
    let app: XCUIApplication
    var anchor: XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Willkommen,'")).firstMatch
    }
    var consent: XCUIElement {
        app.switches.matching(NSPredicate(format: "label BEGINSWITH 'Ich habe die Datenschutzerklärung'")).firstMatch
    }
    var startButton: XCUIElement { app.buttons["Los geht’s"] }

    func assertIntroduction(children: String) {
        assertShows("Programme", "Zusagen", "Chat", children)
        assertHitArea(consent)
    }

    func acceptAndStart() {
        XCTAssertFalse(scrollUntilHittable(startButton).isEnabled, "Start must wait for the consent")
        scrollUntilHittable(consent).tap()
        wait(for: consent, "value == '1'")
        tap("Los geht’s")
    }
}
