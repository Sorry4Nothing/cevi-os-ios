import XCTest

/// The whole app end to end, as scripts over the screen objects in `Screens/`. The real app code runs against the
/// simulated backend of the DEBUG build (fictional data, fresh per launch). Every screen is audited for accessibility.
@MainActor
final class AppFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: Parent

    func testParentFlow() throws {
        try parentFlow(AppRobot.launch())
    }

    /// The same script at the largest accessibility text size (AX5).
    func testParentFlowLargestText() throws {
        try parentFlow(AppRobot.launch(textSize: .largest))
    }

    private func parentFlow(_ app: XCUIApplication) throws {
        let signIn = SignInScreen(app: app).waitUntilDisplayed()
        try signIn.auditAccessibility()
        signIn.assertControls()
        signIn.signIn(username: AppRobot.username(.parent), password: AppRobot.password())

        let tabs = TabBar(app: app)
        tabs.assertTabs([.programs, .chat, .profile])
        let programs = ProgramListScreen(app: app).waitUntilDisplayed()
        try programs.auditAccessibility()
        programs.assertRow("Waldnachmittag", shows: "Jungschar", "Zusage für Lena offen", "Zusage für Noah offen")
        programs.assertRow("Kerzenziehen", shows: "Abgesagt", "Lena kommt")
        programs.assertMultiDay("Herbstweekend")
        programs.assertRow("Herbstweekend", shows: "Wird geprüft")

        var detail = programs.open("Waldnachmittag")
        try detail.auditAccessibility()
        detail.assertShows("Treffpunkt", "Bahnhof Beispielstadt", "Regenjacke und Zvieri", "Jan Muster", "Noch offen")
        detail.answer(child: "Lena", yes: true)
        detail.answer(child: "Noah", yes: false)
        try detail.auditAccessibility()
        detail.back()
        // Persistence: the list and the reopened detail show the saved answers.
        programs.waitUntilDisplayed()
        programs.assertRow("Waldnachmittag", shows: "Lena kommt", "Noah kommt nicht")
        detail = programs.open("Waldnachmittag")
        detail.assertAnswer(child: "Lena", yes: true)
        detail.assertAnswer(child: "Noah", yes: false)
        detail.back()

        let cancelled = programs.waitUntilDisplayed().open("Kerzenziehen")
        cancelled.assertClosed(status: "Abgesagt")
        try cancelled.auditAccessibility()
        cancelled.back()

        tabs.open(.chat)
        let chats = ChatListScreen(app: app).waitUntilDisplayed()
        try chats.auditAccessibility()
        chats.assertUnread("Gruppenchat Jungschar", count: 2)
        let group = chats.open("Gruppenchat Jungschar")
        try group.auditAccessibility()
        group.assertShows("Bitte Regenjacke mitnehmen.", "Jan Muster (Biber) (Stufenleitung)")
        group.loadOlder(expecting: "Info 1:")
        group.send(message: "Lena bringt Zvieri für alle mit.")
        group.back()

        let sheet = chats.waitUntilDisplayed().newMessage()
        try sheet.auditAccessibility()
        let direct = sheet.write(for: "Noah", unit: "Jungschar")
        direct.assertDirectNotice()
        try direct.auditAccessibility()
        direct.send(message: "Noah kommt am Samstag etwas später.")
        direct.back()
        chats.waitUntilDisplayed().assertShows("Mit der Stufenleitung")

        tabs.open(.profile)
        let profile = ProfileScreen(app: app).waitUntilDisplayed()
        try profile.auditAccessibility()
        profile.assertShows("Eva Beispiel", "Elternteil · Lena und Noah", "Benachrichtigungen")
        profile.setSwitch("Mitteilungen zum Chat", on: false)
        profile.setSwitch("Mitteilungen zu Programmen", on: false)
        profile.setSwitch("Mitteilungen zum Chat", on: true)
        let privacy = profile.openPrivacy()
        try privacy.auditAccessibility()
        privacy.assertSections()
        privacy.back()

        profile.waitUntilDisplayed().signOut(username: AppRobot.username(.parent))
    }

    /// Main screens once in dark mode.
    func testMainScreensDark() throws {
        let app = AppRobot.launch(appearance: .dark)
        let signIn = SignInScreen(app: app).waitUntilDisplayed()
        try signIn.auditAccessibility()
        signIn.signIn(username: AppRobot.username(.parent), password: AppRobot.password())

        let programs = ProgramListScreen(app: app).waitUntilDisplayed()
        try programs.auditAccessibility()
        let detail = programs.open("Waldnachmittag")
        detail.answer(child: "Lena", yes: true)
        try detail.auditAccessibility()
        detail.back()

        let tabs = TabBar(app: app)
        tabs.open(.chat)
        let chats = ChatListScreen(app: app).waitUntilDisplayed()
        try chats.auditAccessibility()
        let group = chats.open("Gruppenchat Jungschar")
        try group.auditAccessibility()
        group.back()
        try chats.waitUntilDisplayed().newMessage().auditAccessibility()
        NewMessageScreen(app: app).close()

        tabs.open(.profile)
        try ProfileScreen(app: app).waitUntilDisplayed().auditAccessibility()
    }

    // MARK: First sign-in

    func testFirstLoginFlow() throws {
        let app = AppRobot.launch()
        let signIn = SignInScreen(app: app).waitUntilDisplayed()
        signIn.submitEmpty()
        try signIn.auditAccessibility()
        signIn.signIn(username: AppRobot.username(.newcomer), password: AppRobot.password())

        let password = ChangePasswordScreen(app: app).waitUntilDisplayed()
        try password.auditAccessibility()
        password.changePassword(current: AppRobot.password(), new: "Neu-" + UUID().uuidString.prefix(12))

        let welcome = WelcomeScreen(app: app).waitUntilDisplayed()
        try welcome.auditAccessibility()
        welcome.assertIntroduction(children: "Lena und Noah")
        welcome.acceptAndStart()

        try ProgramListScreen(app: app).waitUntilDisplayed().auditAccessibility()
        TabBar(app: app).assertTabs([.programs, .chat, .profile])
    }

    // MARK: Unit leader

    func testLeaderFlow() throws {
        let app = AppRobot.launch()
        SignInScreen(app: app).waitUntilDisplayed()
            .signIn(username: AppRobot.username(.leader), password: AppRobot.password())

        let tabs = TabBar(app: app)
        tabs.assertTabs([.programs, .chat, .attendance, .profile])
        let programs = ProgramListScreen(app: app).waitUntilDisplayed()
        try programs.auditAccessibility()

        let detail = programs.open("Waldnachmittag")
        detail.assertShows("Wir bauen ein Floss.", "Leitung")
        detail.registerAsLeader(yes: true)
        try detail.auditAccessibility()

        let overview = detail.openParticipation()
        try overview.auditAccessibility()
        overview.assertCounts(yes: 0, no: 0, open: 4)
        overview.assertRow("Lena Beispiel", answer: "Offen")
        overview.assertShows("Sortiert: offen zuerst")
        overview.showLeaders()
        overview.assertCounts(yes: 1, no: 0, open: 0)
        overview.assertRow("Jan Muster (Biber)", answer: "Ja")
        try overview.auditAccessibility()
        overview.back()

        let assignment = detail.waitUntilDisplayed().openAssignment()
        try assignment.auditAccessibility()
        assignment.assertUnitRequired("Jungschar")
        assignment.setVisibility("Leitende")
        assignment.save()
        detail.waitUntilDisplayed()

        tabs.open(.attendance)
        let units = AttendanceListScreen(app: app).waitUntilDisplayed()
        try units.auditAccessibility()
        let attendance = units.open("Jungschar")
        try attendance.auditAccessibility()
        attendance.assertAnswers("Ja", "Nein", "Offen")
        attendance.assertQuota(0, of: 4)
        attendance.mark("Lena Beispiel", present: true)
        attendance.assertQuota(1, of: 4)
        attendance.mark("Noah Beispiel", present: false)
        attendance.mark("Lena Beispiel", present: nil)
        attendance.assertQuota(0, of: 4)
        try attendance.auditAccessibility()
        attendance.showLeaders()
        attendance.mark("Jan Muster (Biber)", present: true)
        try attendance.auditAccessibility()

        tabs.open(.chat)
        let chats = ChatListScreen(app: app).waitUntilDisplayed()
        chats.assertUnread("Sara Muster", count: 1)
        try chats.auditAccessibility()
    }

    // MARK: Second factor

    func testSecondFactorFlow() throws {
        let app = AppRobot.launch()
        SignInScreen(app: app).waitUntilDisplayed()
            .signIn(username: AppRobot.username(.admin), password: AppRobot.password())

        let secondFactor = SecondFactorScreen(app: app).waitUntilDisplayed()
        try secondFactor.auditAccessibility()
        secondFactor.assertConfirmDisabledUntilSixDigits()
        secondFactor.confirm(code: "000000")
        secondFactor.assertWrongCode()
        secondFactor.confirm(code: String(Int.random(in: 100_000...999_999)))

        ProgramListScreen(app: app).waitUntilDisplayed()
        TabBar(app: app).assertTabs([.programs, .attendance, .profile])
    }

    // MARK: States

    func testFailureStates() throws {
        try XCTContext.runActivity(named: "Offline at launch, then retry") { _ in
            let app = AppRobot.launch(signedInAs: .parent, failure: .offline)
            let offline = StateScreen(app: app, kind: .offline).waitUntilDisplayed()
            try offline.auditAccessibility()
            offline.retry()
            ProgramListScreen(app: app).waitUntilDisplayed()
        }
        try XCTContext.runActivity(named: "Server error, then retry") { _ in
            let app = AppRobot.launch(failure: .server)
            SignInScreen(app: app).waitUntilDisplayed().signIn(username: AppRobot.username(.parent), password: AppRobot.password())
            let error = StateScreen(app: app, kind: .error).waitUntilDisplayed()
            try error.auditAccessibility()
            error.retry()
            ProgramListScreen(app: app).waitUntilDisplayed().assertRow("Waldnachmittag")
        }
        try XCTContext.runActivity(named: "Empty program list") { _ in
            let app = AppRobot.launch(failure: .empty)
            SignInScreen(app: app).waitUntilDisplayed().signIn(username: AppRobot.username(.parent), password: AppRobot.password())
            let empty = StateScreen(app: app, kind: .empty).waitUntilDisplayed()
            try empty.auditAccessibility()
            empty.assertShows("In den nächsten Monaten ist nichts geplant.")
        }
        try XCTContext.runActivity(named: "Session ended, back to sign-in") { _ in
            let app = AppRobot.launch(failure: .unauthorized)
            let signIn = SignInScreen(app: app).waitUntilDisplayed()
            signIn.signIn(username: AppRobot.username(.parent), password: AppRobot.password())
            ProgramListScreen(app: app).waitUntilDisplayed().row("Waldnachmittag").tap()
            signIn.waitUntilReset(after: AppRobot.username(.parent))
            try StateScreen(app: app, kind: .sessionEnded).auditAccessibility()
            signIn.signIn(username: AppRobot.username(.parent), password: AppRobot.password())
            ProgramListScreen(app: app).waitUntilDisplayed()
        }
    }

    func testOutdatedApp() throws {
        let app = AppRobot.launch(failure: .outdated)
        SignInScreen(app: app).waitUntilDisplayed().signIn(username: AppRobot.username(.parent), password: AppRobot.password())
        let outdated = StateScreen(app: app, kind: .outdated).waitUntilDisplayed()
        try outdated.auditAccessibility()
        outdated.assertShows("Diese Version von Cevi OS wird nicht mehr unterstützt.")
    }

    func testLockScreen() throws {
        let app = AppRobot.launch(signedInAs: .leader, locked: true)
        let lock = LockScreen(app: app).waitUntilDisplayed()
        try lock.auditAccessibility()
        lock.unlock()
        ProgramListScreen(app: app).waitUntilDisplayed()
    }
}
