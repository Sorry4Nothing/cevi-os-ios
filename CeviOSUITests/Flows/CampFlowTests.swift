import XCTest

/// The camp view end to end against the simulated backend (camp «Sommerlager Beispiel 2027», one closed camp).
/// Every screen is audited; the screens also go to `/tmp/camp-shots` for the comparison with the design.
@MainActor
final class CampFlowTests: XCTestCase {
    private let camp = "Sommerlager Beispiel 2027"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Program list → switcher → camp choice → the camp view.
    @discardableResult
    private func enterCamp(_ app: XCUIApplication, _ title: String, snapshots: Bool = true) throws -> CampStartScreen {
        let programs = ProgramListScreen(app: app).waitUntilDisplayed()
        let switcher = CampSwitcherScreen(app: app)
        switcher.openChooser()
        try switcher.auditChooser()
        if snapshots { switcher.snap("L1") }
        switcher.choose(title)
        _ = programs
        return CampStartScreen(app: app, campTitle: title).waitUntilDisplayed()
    }

    // MARK: Camp lead

    func testCampFlow() throws {
        let app = AppRobot.launch(signedInAs: .leader)
        let start = try enterCamp(app, camp)
        start.assertShows("Noch 12 Tage bis zum Lager")
        try start.auditAccessibility()
        start.snap("L2")
        start.assertTabs(["Start", "Aufgaben", "Pinnwand", "Mehr"], hidden: ["Anwesenheit"])

        // Tasks: list, detail, status, checklist.
        start.open("Aufgaben")
        let tasks = CampTasksScreen(app: app).waitUntilDisplayed()
        tasks.assertShows("Offerte Lagerhaus einholen", "Zelte prüfen", "Menüplan abschliessen")
        try tasks.auditAccessibility()
        tasks.snap("L5")
        // Kanban (T1) and Zeitplan (T3) are views of the same screen.
        tasks.show("Kanban")
        tasks.assertShows("Offen", "Erledigt")
        try tasks.auditAccessibility()
        tasks.snap("T1")
        tasks.show("Zeitplan")
        let schedule = CampPageScreen(app: app, title: "Zeitplan").waitUntilDisplayed()
        schedule.snap("T3")
        try schedule.auditAccessibility()
        tasks.show("Liste")
        let detail = tasks.open("Zelte prüfen")
        try detail.auditAccessibility()
        detail.snap("L7")
        detail.tick("Preise vergleichen")
        detail.markDone()
        try detail.auditAccessibility()
        detail.back()
        tasks.waitUntilDisplayed()

        // The concurrent edit: the first change of «Busfahrt buchen» meets a conflict, «Meine behalten» sends it again.
        let bus = tasks.open("Busfahrt buchen")
        bus.doneButton.tap()
        bus.assertConflict()
        try bus.auditConflict()
        bus.snap("U7")
        bus.keepMine()
        XCTAssertTrue(bus.reopenButton.waitForExistence(timeout: 10), "retry after the conflict did not save")
        bus.back()

        // Pinnwand.
        start.open("Pinnwand")
        let notices = CampNoticesScreen(app: app).waitUntilDisplayed()
        notices.assertShows("Treffpunkt am Samstag", "Wer hilft beim Aufbau?")
        try notices.auditAccessibility()
        notices.snap("L16")

        // «Mehr» opens (its entries are in testCampMoreScreens).
        let more = CampMoreScreen(app: app)
        more.open(start)
        try more.auditAccessibility()
        more.snap("L37")
    }

    /// Every entry of the «Mehr» sheet: opens, audited. A failing screen does not hide the next one.
    func testCampMoreScreens() throws {
        continueAfterFailure = true
        let app = AppRobot.launch(signedInAs: .leader)
        let start = try enterCamp(app, camp, snapshots: false)
        let more = CampMoreScreen(app: app)
        more.open(start)
        let rows: [(String, String?)] = [
            ("Hoecks", nil), ("Erwähnungen", nil), ("Eingang", nil), ("Benachrichtigungen", nil),
            ("Zimmer und Zelte", "L20"), ("Fahrten", nil), ("Programmgruppen", nil), ("Schichtplan", "T2"), ("Diensttausch", nil), ("Abzählen", nil),
            ("Anwesenheit", "L26"), ("Tagesseiten", nil), ("Einkaufsliste", "L28"), ("Packliste", nil), ("Notfall", "L30"), ("Infos", nil),
            ("Dokumente", "L33"), ("Adressbuch", nil), ("Suche", nil),
        ]
        for (row, id) in rows {
            let page = more.openRow(row)
            if let id { page.snap(id) } else { page.snap("more-\(row)") }
            try page.auditAccessibility()
            page.back()
            more.waitUntilDisplayed()
        }
    }

    /// Core screens at the largest text size.
    func testCampFlowLargestText() throws {
        try coreScreens(AppRobot.launch(signedInAs: .leader, textSize: .largest))
    }

    /// Core screens in dark mode.
    func testCampFlowDark() throws {
        try coreScreens(AppRobot.launch(signedInAs: .leader, appearance: .dark))
    }

    private func coreScreens(_ app: XCUIApplication) throws {
        let start = try enterCamp(app, camp)
        try start.auditAccessibility()
        start.snap("L2")
        start.open("Aufgaben")
        let tasks = CampTasksScreen(app: app).waitUntilDisplayed()
        try tasks.auditAccessibility()
        tasks.snap("L5")
        let detail = tasks.open("Zelte prüfen")
        try detail.auditAccessibility()
        detail.snap("L7")
        detail.back()
        start.open("Pinnwand")
        let notices = CampNoticesScreen(app: app).waitUntilDisplayed()
        try notices.auditAccessibility()
        notices.snap("L16")
        let more = CampMoreScreen(app: app)
        more.open(start)
        try more.auditAccessibility()
        let emergency = more.openRow("Notfall")
        try emergency.auditAccessibility()
        emergency.snap("L30")
    }

    // MARK: Team

    func testCampTeamFlow() throws {
        let app = AppRobot.launch(signedInAs: .team)
        let start = try enterCamp(app, camp, snapshots: false)
        try start.auditAccessibility()
        start.snap("L3")
        // The team has no task list; its own presence is a tab.
        start.assertTabs(["Start", "Anwesenheit", "Pinnwand", "Mehr"], hidden: ["Aufgaben"])
        start.open("Anwesenheit")
        let attendance = CampPageScreen(app: app, title: "Anwesenheit").waitUntilDisplayed()
        try attendance.auditAccessibility()
        attendance.snap("L26")
        start.open("Pinnwand")
        try CampNoticesScreen(app: app).waitUntilDisplayed().auditAccessibility()
    }

    // MARK: Closed camp

    func testCampClosed() throws {
        let app = AppRobot.launch(signedInAs: .leader)
        let title = "Herbstlager Beispiel 2026"
        let start = try enterCamp(app, title, snapshots: false)
        try start.auditAccessibility()
        start.open("Aufgaben")
        let tasks = CampTasksScreen(app: app).waitUntilDisplayed()
        try tasks.auditAccessibility()
        // Read-only: the detail has no button that changes anything.
        let detail = tasks.open("Zelte prüfen")
        XCTAssertFalse(detail.doneButton.exists, "a closed camp must not offer «Erledigt»")
        XCTAssertFalse(detail.reopenButton.exists)
        try detail.auditAccessibility()
    }
}
