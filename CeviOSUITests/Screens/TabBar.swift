import XCTest

/// Main navigation between the tabs.
struct TabBar: Screen {
    enum Tab: String, CaseIterable {
        case programs = "Programme"
        case chat = "Chat"
        case profile = "Profil"
    }

    let app: XCUIApplication
    var anchor: XCUIElement { app.tabBars.firstMatch }

    func button(_ tab: Tab) -> XCUIElement { app.tabBars.buttons[tab.rawValue] }

    func open(_ tab: Tab) {
        button(tab).tap()
        assertSelected(button(tab))
    }

    /// The tabs follow the role: chat only for parents and unit leaders.
    func assertTabs(_ tabs: [Tab], file: StaticString = #filePath, line: UInt = #line) {
        waitUntilDisplayed()
        for tab in Tab.allCases {
            XCTAssertEqual(button(tab).exists, tabs.contains(tab), "Tab \(tab.rawValue)", file: file, line: line)
        }
    }
}
