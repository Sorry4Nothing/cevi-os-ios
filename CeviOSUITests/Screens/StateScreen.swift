import XCTest

/// Full-screen states. An ended session has no own screen: the app returns to the sign-in.
struct StateScreen: Screen {
    enum Kind {
        case offline, error, empty, outdated, sessionEnded

        var title: String {
            switch self {
            case .offline: "Keine Verbindung"
            case .error: "Etwas ist schiefgelaufen"
            case .empty: "Keine Programme"
            case .outdated: "Bitte die App aktualisieren"
            case .sessionEnded: "Schön, bist du da."
            }
        }

        var action: String? {
            switch self {
            case .offline, .error: "Nochmals versuchen"
            case .empty: "Aktualisieren"
            case .outdated, .sessionEnded: nil
            }
        }
    }

    let app: XCUIApplication
    let kind: Kind
    var anchor: XCUIElement { app.staticTexts[kind.title] }

    func retry() {
        guard let action = kind.action else { return XCTFail("\(kind) has no action") }
        assertHitArea(button(action))
        tap(action)
    }
}
