import XCTest

/// Units and visibility of a program (unit leaders and admins).
struct AssignmentScreen: Screen {
    let app: XCUIApplication
    var anchor: XCUIElement { app.navigationBars["Stufen und Sichtbarkeit"] }
    var saveButton: XCUIElement { app.buttons["Speichern"] }

    func unit(_ name: String) -> XCUIElement { app.switches[name] }

    /// Without a unit only «Intern» is allowed; the reason is shown and saving is blocked.
    func assertUnitRequired(_ unitName: String) {
        flip(unit(unitName))
        assertShows("Ohne Stufe ist nur «Intern» möglich.")
        XCTAssertFalse(saveButton.isEnabled)
        flip(unit(unitName))
        waitUntilGone(element(containing: "Ohne Stufe"))
    }

    func setVisibility(_ option: String) {
        scrollUntilHittable(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sichtbar für'")).firstMatch).tap()
        let item = app.buttons[option].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 10), "menu item \(option)")
        item.tap()
        wait(for: app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sichtbar für'")).firstMatch,
             "label CONTAINS %@ OR value CONTAINS %@", option, option)
    }

    func save() {
        tap("Speichern")
        waitUntilGone(anchor)
    }
}
