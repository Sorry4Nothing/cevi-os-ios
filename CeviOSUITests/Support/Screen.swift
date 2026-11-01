import XCTest

/// Page object for one screen: its elements, intent-level actions and assertions.
@MainActor
protocol Screen {
    var app: XCUIApplication { get }
    /// Element that is present exactly when the screen is shown.
    var anchor: XCUIElement { get }
}

extension Screen {
    var name: String { String(describing: Self.self) }
    var isDisplayed: Bool { anchor.exists }

    @discardableResult
    func waitUntilDisplayed(timeout: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line) -> Self {
        XCTAssertTrue(anchor.waitForExistence(timeout: timeout), "\(name) is not displayed", file: file, line: line)
        dismissPasswordSavePrompt()
        return self
    }

    /// After a sign-in the system covers the app with the sheet «Passwort sichern?» (iOS 27). It is part of the app's
    /// hierarchy, so everything behind it is unreachable and the audit finds covered text. «Später» closes it.
    func dismissPasswordSavePrompt(timeout: TimeInterval = 1) {
        for title in ["Später", "Not Now"] {
            let button = app.sheets.buttons[title]
            if button.waitForExistence(timeout: timeout) {
                button.tap()
                return
            }
        }
    }

    // MARK: Lookup

    /// First element whose label contains `text`.
    func element(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    func button(_ label: String) -> XCUIElement { app.buttons[label] }

    /// First button whose label contains every part.
    func button(containing parts: String...) -> XCUIElement {
        let predicates = parts.map { NSPredicate(format: "label CONTAINS %@", $0) }
        return app.buttons.matching(NSCompoundPredicate(andPredicateWithSubpredicates: predicates)).firstMatch
    }

    // MARK: Actions

    /// Swipes until the element exists and can be tapped (long lists, AX5 text). Swipes towards the element when its
    /// frame is known, otherwise in the direction of `fromTop` (lazy rows exist only once scrolled into view).
    @discardableResult
    func scrollUntilHittable(_ element: XCUIElement, fromTop: Bool = true, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        _ = element.waitForExistence(timeout: 5)
        let window = app.windows.firstMatch.frame
        // Hittable alone is not enough: a tall card can be hittable while its centre sits under the navigation or tab bar.
        func isReachable() -> Bool {
            element.exists && element.isHittable
                && element.frame.midY > window.minY + window.height * 0.15 && element.frame.midY < window.minY + window.height * 0.95
        }
        for _ in 0..<15 where !isReachable() {
            let isAbove = element.exists ? element.frame.midY < window.midY : !fromTop
            scrollStep(revealingAbove: isAbove)
        }
        XCTAssertTrue(isReachable(), "«\(element.description)» not reachable on \(name)", file: file, line: line)
        return element
    }

    /// A third of the screen without momentum, so tall rows (AX5) are not skipped.
    func scrollStep(revealingAbove: Bool) {
        let window = app.windows.firstMatch
        // Above the keyboard, which covers the lower ~40 % while a field is focused.
        let top = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.22))
        let bottom = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.52))
        let (from, to) = revealingAbove ? (top, bottom) : (bottom, top)
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.1)
    }

    func tap(_ label: String, file: StaticString = #filePath, line: UInt = #line) {
        scrollUntilHittable(app.buttons[label], file: file, line: line).tap()
    }

    func type(_ text: String, into field: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        scrollUntilHittable(field, file: file, line: line).tap()
        field.typeText(text)
    }

    /// Taps the switch itself (right edge); the middle of a toggle row is its label.
    func flip(_ toggle: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        scrollUntilHittable(toggle, file: file, line: line).coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    }

    func back() {
        app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()
    }

    // MARK: Waiting

    func wait(for element: XCUIElement, _ format: String, _ arguments: CVarArg..., timeout: TimeInterval = 10,
              file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: format, argumentArray: arguments)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, "\(name): «\(element.description)» never matched \(predicate)", file: file, line: line)
    }

    func waitUntilGone(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        wait(for: element, "exists == false", file: file, line: line)
    }

    // MARK: Assertions

    /// Every label currently on screen, from one snapshot of the hierarchy.
    func snapshotLabels() throws -> [String] {
        var labels: [String] = []
        func collect(_ node: any XCUIElementSnapshot) {
            if !node.label.isEmpty { labels.append(node.label) }
            node.children.forEach(collect)
        }
        collect(try app.snapshot())
        return labels
    }

    /// Each text is visible as (part of) a label: states are conveyed by words, not color alone.
    func assertShows(_ texts: String..., file: StaticString = #filePath, line: UInt = #line) {
        for text in texts {
            XCTAssertTrue(element(containing: text).waitForExistence(timeout: 10), "\(name): «\(text)» not shown", file: file, line: line)
        }
    }

    func assertNotShown(_ text: String, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertFalse(try snapshotLabels().contains { $0.contains(text) }, "\(name): «\(text)» shown", file: file, line: line)
    }

    /// Types into a bordered field after tapping the box below the line of text, which checks that the whole box
    /// (not only the 22 pt line) is the tap area. The typed value must arrive in that field.
    func fill(_ field: XCUIElement, with text: String, isSecure: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
        scrollUntilHittable(field, file: file, line: line)
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: 0, dy: 20)).tap()
        app.typeText(text)
        if isSecure {
            wait(for: field, "value.length == %d", text.count, file: file, line: line)
        } else {
            wait(for: field, "value == %@", text, file: file, line: line)
        }
    }

    /// Tap area of at least 44 × 44 pt.
    func assertHitArea(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "\(name): «\(element.description)» missing", file: file, line: line)
        let frame = element.frame
        XCTAssertGreaterThanOrEqual(frame.height, 44, "\(name): «\(element.label)» \(frame)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.width, 44, "\(name): «\(element.label)» \(frame)", file: file, line: line)
    }

    /// Selected trait (answer buttons, segments, tabs), waited for because it follows a save.
    func assertSelected(_ element: XCUIElement, _ selected: Bool = true, file: StaticString = #filePath, line: UInt = #line) {
        wait(for: element, "exists == true AND selected == %@", NSNumber(value: selected), file: file, line: line)
    }

    /// Waits for loading placeholders to go, then runs the audit with the shared false-positive filter.
    func auditAccessibility(file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertTrue(anchor.waitForExistence(timeout: 15), "\(name) is not displayed", file: file, line: line)
        dismissPasswordSavePrompt()
        waitUntilGone(element(containing: "Lädt"), file: file, line: line)
        waitUntilGone(element(containing: "werden geladen"), file: file, line: line)
        try AccessibilityAudit.run(on: app, screen: name, file: file, line: line)
    }
}
