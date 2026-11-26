import XCTest

/// Lädeli: articles, cart and order against the simulated backend; every screen is audited.
@MainActor
final class ShopFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testOrderFromTheProfile() throws {
        let app = AppRobot.launch(signedInAs: .parent)
        ProgramListScreen(app: app).waitUntilDisplayed()
        TabBar(app: app).open(.profile)
        let profile = ProfileScreen(app: app).waitUntilDisplayed()
        profile.tap("Lädeli")
        let shop = GenericScreen(app: app, title: "Lädeli").waitUntilDisplayed()
        try shop.auditAccessibility()
        shop.assertShows("Lagershirt", "CHF 25.00", "Nicht zu haben: L", "Trinkflasche")
        app.buttons["Trinkflasche in den Warenkorb legen"].tap()
        shop.tap("Warenkorb ansehen, 1 Stück, CHF 12.50")
        let cart = GenericScreen(app: app, title: "Warenkorb").waitUntilDisplayed()
        try cart.auditAccessibility()
        cart.tap("Bestellen")
        cart.assertShows("Bestellung eingegangen", "Danke! Hol deine Bestellung Im Pfadiheim ab.")
    }
}

/// A screen known by the title of its navigation bar.
struct GenericScreen: Screen {
    let app: XCUIApplication
    let title: String
    var anchor: XCUIElement { app.navigationBars[title] }
}
