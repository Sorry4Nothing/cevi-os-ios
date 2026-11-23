import XCTest

/// The «Mehr» sheet (L37) and the screens it leads to.
struct CampMoreScreen: Screen {
    let app: XCUIApplication
    var anchor: XCUIElement { app.navigationBars["Mehr"] }

    func open(_ tabBar: CampStartScreen) {
        tabBar.tab("Mehr").tap()
        waitUntilDisplayed()
    }

    func openRow(_ title: String) -> CampPageScreen {
        scrollUntilHittable(app.buttons[title]).tap()
        return CampPageScreen(app: app, title: title).waitUntilDisplayed()
    }
}

/// A camp screen with a navigation title only (rooms, emergency, documents ...).
struct CampPageScreen: Screen {
    let app: XCUIApplication
    let title: String
    var anchor: XCUIElement { app.navigationBars[title] }
}
