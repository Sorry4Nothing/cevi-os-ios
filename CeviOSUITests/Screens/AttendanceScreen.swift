import XCTest

/// Attendance of one unit at one event.
struct AttendanceScreen: Screen {
    let app: XCUIApplication
    let unit: String
    var anchor: XCUIElement { app.navigationBars[unit] }

    func presenceButton(_ person: String, present: Bool) -> XCUIElement {
        app.buttons["\(person), \(present ? "Da" : "Nicht da")"]
    }

    /// `present == nil` takes the entry back by tapping the selected button again.
    func mark(_ person: String, present: Bool?) {
        let target = present ?? true
        let button = scrollUntilHittable(presenceButton(person, present: target))
        assertHitArea(button)
        button.tap()
        assertSelected(presenceButton(person, present: target), present != nil)
        if present != nil { assertSelected(presenceButton(person, present: !target), false) }
    }

    func assertQuota(_ present: Int, of total: Int) {
        assertShows("Anwesend: \(present) von \(total)")
    }

    /// The parents' answer is separate from who was there, and written out.
    func assertAnswers(_ words: String...) {
        for word in words { assertShows("Zusage: \(word)") }
    }

    func showLeaders() {
        let segment = app.buttons["Leitende"]
        segment.tap()
        assertSelected(segment)
    }
}
