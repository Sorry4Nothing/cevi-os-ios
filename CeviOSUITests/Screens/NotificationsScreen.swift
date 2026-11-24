import XCTest

/// A7 Benachrichtigungen: one switch per kind with one sentence.
struct NotificationsScreen: Screen {
    let app: XCUIApplication
    var anchor: XCUIElement { app.navigationBars["Benachrichtigungen"] }

    func toggle(_ title: String) -> XCUIElement { app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch }

    /// Switches a setting; the saved value comes back from the server.
    func setSwitch(_ title: String, on: Bool) {
        let element = scrollUntilHittable(toggle(title))
        assertHitArea(element)
        if (element.value as? String == "1") != on { flip(element) }
        wait(for: element, "value == %@", on ? "1" : "0")
    }
}
