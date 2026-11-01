import XCTest

/// Starts the app against the simulated backend of the DEBUG build (`CeviOS/App/UITestBackend.swift`).
/// Every launch starts with fresh in-memory data; nothing is shared between tests.
@MainActor
enum AppRobot {
    /// The username prefix selects the persona of the simulated backend.
    enum Persona: String {
        case parent = "eltern"
        case leader = "leitung"
        case newcomer = "neu"
    }

    enum TextSize { case standard, largest }
    enum Appearance { case light, dark }

    enum Failure: String {
        /// The first request fails without connection.
        case offline
        /// The first program list answers 500.
        case server
        /// The first program detail answers 401: the session ends.
        case unauthorized
        /// Every request answers 426.
        case outdated
        /// The program list is empty.
        case empty
    }

    static let largestTextCategory = "UICTContentSizeCategoryAccessibilityXXXL"

    static func launch(
        signedInAs persona: Persona? = nil,
        textSize: TextSize = .standard,
        appearance: Appearance = .light,
        failure: Failure? = nil,
        locked: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        // Always in pairs: `-key value`, so the argument domain parses every flag.
        var arguments = ["-UITestBackend", "YES"]
        if let persona { arguments += ["-UITestSignedIn", username(persona)] }
        if let failure { arguments += ["-UITestFailure", failure.rawValue] }
        if locked { arguments += ["-UITestLocked", "YES"] }
        if textSize == .largest { arguments += ["-UIPreferredContentSizeCategoryName", largestTextCategory] }
        if appearance == .dark { arguments += ["-AppleInterfaceStyle", "Dark"] }
        app.launchArguments = arguments
        app.launch()
        return app
    }

    static func username(_ persona: Persona) -> String { "\(persona.rawValue).demo" }

    /// The backend accepts any non-empty password; a fresh random one per call, nothing hard-coded.
    static func password() -> String { UUID().uuidString }
}
