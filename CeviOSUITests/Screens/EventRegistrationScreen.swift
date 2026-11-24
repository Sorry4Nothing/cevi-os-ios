import XCTest

/// K4 Anlass-Anmeldung.
struct EventRegistrationScreen: Screen {
    let app: XCUIApplication
    var anchor: XCUIElement { app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Anmeldung ' AND label != 'Anmeldung wird geladen'")).firstMatch }

    func pick(_ option: String) { scrollUntilHittable(app.buttons[option]).tap() }

    func answerYesNo(_ field: String, yes: Bool) {
        scrollUntilHittable(app.buttons["\(field), \(yes ? "Ja" : "Nein")"]).tap()
    }

    func submit() { tap("Anmelden") }
}
