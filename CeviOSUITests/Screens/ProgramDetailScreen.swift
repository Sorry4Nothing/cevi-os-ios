import XCTest

/// Program detail: times, place, contact, answers for the children and the leader sections.
struct ProgramDetailScreen: Screen {
    let app: XCUIApplication
    let title: String
    var anchor: XCUIElement { app.staticTexts["Kontaktperson"] }

    func answerButton(_ name: String, yes: Bool) -> XCUIElement { app.buttons["\(name), \(yes ? "Ja" : "Nein")"] }

    /// Answers for a child (or «Ich» for the own registration) and waits until the saved answer is selected.
    func answer(child name: String, yes: Bool) {
        let button = scrollUntilHittable(answerButton(name, yes: yes))
        assertHitArea(button)
        button.tap()
        assertAnswer(child: name, yes: yes)
    }

    func registerAsLeader(yes: Bool) {
        assertShows("Meine Anmeldung als Leitung", "Noch keine Antwort")
        answer(child: "Ich", yes: yes)
    }

    func assertAnswer(child name: String, yes: Bool, file: StaticString = #filePath, line: UInt = #line) {
        assertSelected(answerButton(name, yes: yes), file: file, line: line)
        assertSelected(answerButton(name, yes: !yes), false, file: file, line: line)
        guard name != "Ich" else { return }
        // Status in words next to the name, not only the filled capsule.
        let status = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", name))
            .matching(NSPredicate(format: yes ? "label CONTAINS 'Kommt' AND NOT label CONTAINS 'nicht'" : "label CONTAINS 'Kommt nicht'"))
        XCTAssertTrue(status.firstMatch.waitForExistence(timeout: 10), "status of \(name)", file: file, line: line)
    }

    /// Cancelled or closed: the state is written out and no answer buttons are offered.
    func assertClosed(status: String, file: StaticString = #filePath, line: UInt = #line) {
        assertShows(status, "Die Anmeldung ist nicht mehr möglich.", file: file, line: line)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label ENDSWITH ', Ja'")).firstMatch.exists, file: file, line: line)
    }

    /// The leader section: where the groups come from and the way to the registrations, with the counts in words.
    func assertLeaderSection(counts: String, file: StaticString = #filePath, line: UInt = #line) {
        assertShows("Die Gruppen kommen aus der Outlook-Kategorie.", "Für Leitende")
        wait(for: button(containing: "Anmeldungen ansehen"), "label CONTAINS %@", counts, file: file, line: line)
    }

    /// The row to the registration of an occasion (K4).
    func openRegistration(_ label: String) -> EventRegistrationScreen {
        scrollUntilHittable(button(containing: label)).tap()
        return EventRegistrationScreen(app: app).waitUntilDisplayed()
    }

    func openParticipation() -> ParticipationOverviewScreen {
        scrollUntilHittable(button(containing: "Anmeldungen ansehen")).tap()
        return ParticipationOverviewScreen(app: app).waitUntilDisplayed()
    }
}
