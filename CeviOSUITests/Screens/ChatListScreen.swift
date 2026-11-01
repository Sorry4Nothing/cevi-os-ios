import XCTest

/// Chat list: group chats and direct chats with the unit leaders.
struct ChatListScreen: Screen {
    let app: XCUIApplication
    var anchor: XCUIElement { app.navigationBars["Chat"] }

    func row(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    /// Unread is a number and a word in the label, not only bold text or color.
    func assertUnread(_ title: String, count: Int) {
        let chat = scrollUntilHittable(row(title))
        wait(for: chat, "label CONTAINS %@", "\(count) ungelesen")
        assertHitArea(chat)
    }

    func open(_ title: String) -> ChatScreen {
        scrollUntilHittable(row(title)).tap()
        return ChatScreen(app: app, title: title).waitUntilDisplayed()
    }

    func newMessage() -> NewMessageScreen {
        let pencil = button("Neue Nachricht")
        assertHitArea(pencil)
        pencil.tap()
        return NewMessageScreen(app: app).waitUntilDisplayed()
    }

    /// A section header; at AX5 the lazy list renders it only once scrolled into view.
    func assertSection(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let header = element(containing: title)
        for _ in 0..<15 where !header.exists { scrollStep(revealingAbove: false) }
        XCTAssertTrue(header.waitForExistence(timeout: 5), "\(name): «\(title)» not shown", file: file, line: line)
    }
}
