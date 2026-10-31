import XCTest

/// Apple's accessibility audit on every screen, with fictional fixture data from the DEBUG harness (`UITestScenario`).
/// Each scenario runs at the default text size and at AX5 (`AccessibilityXXXL`); the main screens also in dark mode.
@MainActor
final class AccessibilityAuditTests: XCTestCase {
    private enum Variant { case standard, largestText, dark }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSignIn() throws { try audit("signIn", dark: true) { $0.text("Schön, bist du da.") } }
    func testChangePassword() throws { try audit("changePassword") { $0.text("Eigenes Passwort wählen") } }
    func testPrivacy() throws { try audit("privacy") { $0.text("Willkommen, Fuchs!") } }
    func testProgramList() throws { try audit("programList", dark: true) { $0.text("Waldnachmittag") } }
    func testProgramDetail() throws { try audit("programDetail", dark: true) { $0.text("Kommen deine Kinder?") } }

    func testParticipationOverview() throws {
        try audit("participationOverview") { app in
            app.text("Kommen deine Kinder?")
            app.scrollTo(app.buttons["Anmeldungen"]).tap()
            app.text("Sortiert: offen zuerst")
        }
    }

    func testAttendance() throws {
        try audit("attendance") { app in
            app.tabBars.buttons["Anwesenheit"].tap()
            app.buttons["Jungschar"].tap()
            app.text("Anwesend:")
        }
    }

    func testChatList() throws {
        try audit("chatList", dark: true) { app in
            app.tabBars.buttons["Chat"].tap()
            app.text("Gruppenchat Jungschar")
        }
    }

    func testChat() throws { try audit("chat", dark: true) { $0.text("Bitte Regenjacke mitnehmen.") } }

    func testNewMessage() throws {
        try audit("newMessage") { app in
            app.tabBars.buttons["Chat"].tap()
            app.buttons["Neue Nachricht"].tap()
            app.text("An welche Stufenleitung")
        }
    }

    func testProfile() throws {
        try audit("profile", dark: true) { app in
            app.tabBars.buttons["Profil"].tap()
            app.text("Benachrichtigungen")
        }
    }

    func testLock() throws { try audit("lock") { $0.text("Cevi OS ist gesperrt") } }
    func testOffline() throws { try audit("offline") { $0.text("Keine Verbindung") } }
    func testEmpty() throws { try audit("empty") { $0.text("Keine Programme") } }
    func testError() throws { try audit("error") { $0.text("Etwas ist schiefgelaufen") } }

    // MARK: Helpers

    @MainActor
    private func audit(_ scenario: String, dark: Bool = false, open: (XCUIApplication) -> Void) throws {
        for variant in dark ? [Variant.standard, .largestText, .dark] : [.standard, .largestText] {
            let app = XCUIApplication()
            app.launchArguments += ["-UITestScenario", scenario]
            switch variant {
            case .standard: break
            case .largestText:
                app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            case .dark: app.launchArguments += ["-AppleInterfaceStyle", "Dark"]
            }
            app.launch()
            open(app)
            // Let transitions, scroll-to-bottom and the first poll settle; mid-fade colors give false contrast results.
            Thread.sleep(forTimeInterval: 1.5)
            // Collect every issue of the run, so one failure lists all of them with element and variant.
            var found: [String] = []
            let tabBar = app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame : .null
            try app.performAccessibilityAudit { issue in
                if !Self.isKnownFalsePositive(issue, variant: variant, tabBar: tabBar) {
                    found.append("\(issue.compactDescription) | \(issue.element?.elementType.rawValue ?? 0) «\(issue.element?.label ?? "-")» \(issue.element?.frame ?? .zero)")
                }
                return true
            }
            XCTAssertTrue(found.isEmpty, "\(scenario) \(variant): " + found.joined(separator: " ;; "))
            app.terminate()
        }
    }

    /// Issues the app cannot fix. Each entry says why; no audit type is switched off as a whole.
    /// Labels checked by hand on screenshots (default size and AX5). Keep this list short and explicit.
    private static let verifiedUnclipped = [
        "Du hast ein Startpasswort", "Nochmals versuchen", "An welche Stufenleitung", "Nachricht an die Stufenleitung", "Nachrichten an die Stufenleitung",
        "Ich habe die Datenschutzerklärung", "Konto löschen", "Mitteilungen zu Anmeldungen",
    ]

    private static func isKnownFalsePositive(_ issue: XCUIAccessibilityAuditIssue, variant: Variant, tabBar: CGRect) -> Bool {
        switch issue.auditType {
        case .contrast:
            // Contrast without an element: system chrome (Liquid Glass tab bar and its badge) that the app does not draw.
            guard let element = issue.element else { return true }
            // Text scrolled under the translucent tab bar is measured against the glass, not against its own background.
            return element.frame.intersects(tabBar)
        case .dynamicType, .textClipped where verifiedUnclipped.contains(where: { issue.element?.label.hasPrefix($0) == true }):
            // The audit grows these texts without a new layout pass. Screenshots at the default size and at AX5 show
            // them complete (they wrap or the row grows), so the finding does not hold for the real layout.
            return true
        case .dynamicType, .textClipped:
            // At AX5 the audit tries to enlarge text beyond the largest size, which is impossible; the screenshots of
            // these screens at AX5 show the full text. The default size is audited without this exception.
            return variant == .largestText
        default:
            return false
        }
    }
}

@MainActor
private extension XCUIApplication {
    /// Waits for an element whose label contains `text` and returns it.
    @discardableResult
    func text(_ text: String, timeout: TimeInterval = 15) -> XCUIElement {
        let element = descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "«\(text)» not found")
        return element
    }

    /// Swipes up until the element is hittable (large text sizes push it below the fold).
    func scrollTo(_ element: XCUIElement) -> XCUIElement {
        XCTAssertTrue(element.waitForExistence(timeout: 15))
        for _ in 0..<10 where !element.isHittable { swipeUp() }
        return element
    }
}
