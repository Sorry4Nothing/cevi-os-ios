import XCTest

/// Pinnwand (L16).
struct CampNoticesScreen: Screen {
    let app: XCUIApplication
    var anchor: XCUIElement { app.navigationBars["Pinnwand"] }
}
