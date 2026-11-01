import XCTest

/// One chat: messages, composer, older pages.
struct ChatScreen: Screen {
    let app: XCUIApplication
    let title: String
    var anchor: XCUIElement { app.navigationBars[title] }

    /// The composer grows with the text, so it may be a text field or a text view.
    var composer: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "label == 'Nachricht schreiben' AND (elementType == %d OR elementType == %d)",
            XCUIElement.ElementType.textField.rawValue, XCUIElement.ElementType.textView.rawValue
        )).firstMatch
    }
    var sendButton: XCUIElement { app.buttons["Senden"] }

    /// Sends and waits for the own bubble, which reads «Du, …, Gesendet».
    func send(message text: String) {
        XCTAssertFalse(sendButton.isEnabled, "Nothing to send yet")
        assertHitArea(sendButton)
        type(text, into: composer)
        wait(for: sendButton, "enabled == true")
        sendButton.tap()
        let own = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Du, \(text)")).firstMatch
        XCTAssertTrue(own.waitForExistence(timeout: 10), "own message")
        XCTAssertTrue(own.label.hasSuffix("Gesendet"), own.label)
    }

    func loadOlder(expecting text: String) {
        let olderButton = button("Ältere Nachrichten laden")
        scrollUntilHittable(olderButton, fromTop: false).tap()
        assertShows(text)
        waitUntilGone(olderButton)
    }

    /// Direct chats say who reads along.
    func assertDirectNotice() {
        assertShows("Deine Nachricht geht an die ganze Stufenleitung", "keine Diagnosen")
    }
}
