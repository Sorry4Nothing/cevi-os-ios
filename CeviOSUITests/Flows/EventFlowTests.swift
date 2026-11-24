import XCTest

/// «Mein Kalender» screens, suggestions, rooms, occasion registration, calendar link and notifications against the
/// simulated backend. Every screen and every state is audited for accessibility.
@MainActor
final class EventFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func signedIn(_ persona: AppRobot.Persona, textSize: AppRobot.TextSize = .standard, appearance: AppRobot.Appearance = .light,
                          failure: AppRobot.Failure? = nil) -> ProgramListScreen {
        let app = AppRobot.launch(signedInAs: persona, textSize: textSize, appearance: appearance, failure: failure)
        return ProgramListScreen(app: app).waitUntilDisplayed()
    }

    // MARK: A1 to A4, K4

    func testParentCalendarAndRegistration() throws {
        let programs = signedIn(.parent)
        try programs.auditAccessibility()
        programs.assertShows("Gruppen deiner Kinder: Jungschar")
        // Time, place, group and the state of the children in words.
        programs.assertRow("Waldnachmittag", shows: "Bahnhof Beispielstadt", "Jungschar", "Zusage für 2 Kinder offen")
        programs.assertRow("Sommerlager Beispiel 2027", shows: "Anmeldung offen")

        let detail = programs.open("Sommerlager Beispiel 2027")
        try detail.auditAccessibility()
        let registration = detail.openRegistration("Zur Anmeldung")
        try registration.auditAccessibility()
        registration.assertShows("Aus deinem Konto", "Jahrgang 2016", "Stimmt etwas nicht? Ändere es im Profil.", "Bitte keine Gesundheitsdaten eintragen.")

        // Required answers are named, nothing is sent.
        registration.submit()
        registration.assertShows("Prüfe deine Eingaben.", "Diese Angabe ist nötig.")
        try registration.auditAccessibility()

        registration.answerYesNo("Mein Kind schwimmt sicher", yes: true)
        registration.pick("152")
        registration.submit()
        registration.assertShows("Angemeldet.", "T-Shirt-Grösse: 152", "Mein Kind schwimmt sicher: Ja")
        try registration.auditAccessibility()

        // Undo brings the form back; registering again ends in the summary, then back to the detail.
        registration.tap("Rückgängig")
        registration.assertShows("Aus deinem Konto")
        registration.submit()
        registration.assertShows("Angemeldet.")
        registration.tap("Zu den Programmen")
        detail.waitUntilDisplayed()
        detail.assertShows("Anmeldung ansehen")
    }

    func testParentCannotSuggestButRequestsRooms() throws {
        let programs = signedIn(.parent)
        programs.openMenu("Termin vorschlagen")
        let suggest = SuggestEventScreen(app: programs.app).waitUntilDisplayed()
        suggest.assertShows("Kein Vorschlag möglich")
        try suggest.auditAccessibility()
        suggest.back()

        programs.waitUntilDisplayed().openMenu("Raum anfragen")
        let room = RequestRoomScreen(app: programs.app).waitUntilDisplayed()
        room.assertShows("Das zuständige Team bestätigt deine Anfrage.", "Pfadiheim Beispielwald", "Gruppenraum Keller")
        try room.auditAccessibility()

        // Double booking: the reason is in words at the time.
        room.type("Material sortieren", into: programs.app.textFields["Zweck"])
        programs.app.buttons["Gruppenraum Keller, 12 Plätze"].tap()
        room.send()
        room.assertShows("Dieser Raum ist schon belegt.", "Wähle eine andere Zeit.")
        try room.auditAccessibility()

        room.room("Pfadiheim Beispielwald").tap()
        room.send()
        room.assertShows("Anfrage gesendet.", "Zweck: Material sortieren")
        try room.auditAccessibility()
        room.openRequests()
        let requests = MyRoomRequestsScreen(app: programs.app).waitUntilDisplayed()
        requests.assertShows("Offen", "Bestätigt", "Im Kalender eingetragen", "Abgelehnt", "Material sortieren")
        try requests.auditAccessibility()
    }

    func testRoomRequestsListOpensTheFormAndBack() throws {
        let programs = signedIn(.parent)
        programs.openMenu("Meine Raumanfragen")
        let requests = MyRoomRequestsScreen(app: programs.app).waitUntilDisplayed()
        requests.app.buttons["Raum anfragen"].tap()
        let room = RequestRoomScreen(app: programs.app).waitUntilDisplayed()
        room.type("Sitzung", into: programs.app.textFields["Zweck"])
        room.send()
        room.assertShows("Anfrage gesendet.")
        // From the list the way out goes back to it, with the new request on top.
        room.openRequests()
        requests.waitUntilDisplayed().assertShows("Sitzung")
    }

    func testLeaderSuggestsAnEvent() throws {
        let programs = signedIn(.leader)
        programs.openMenu("Termin vorschlagen")
        let suggest = SuggestEventScreen(app: programs.app).waitUntilDisplayed()
        suggest.assertShows("Die Abteilungsleitung prüft deinen Vorschlag.", "Erst nach der Freigabe erscheint er im Kalender.")
        try suggest.auditAccessibility()

        // Nothing is sent while a field is missing.
        suggest.send()
        suggest.assertShows("Prüfe deine Eingaben.", "Gib einen Titel ein.", "Wähle mindestens eine Gruppe.")
        try suggest.auditAccessibility()

        suggest.fill(programs.app.textFields["Titel"], with: "Serverfehler")
        // The keyboard covers the lower half; close it so the audit sees the whole form.
        programs.app.keyboards.buttons["Return"].tap()
        suggest.tap("Jungschar")
        suggest.assertSelected(suggest.group("Jungschar"))
        suggest.send()
        // A server error keeps the input and offers a retry.
        suggest.assertShows("Das hat nicht geklappt", "Deine Eingabe ist noch da.")
        try suggest.auditAccessibility()
        suggest.tap("Nochmals versuchen")
        suggest.assertShows("Gesendet.", "Offen", "Für Jungschar")
        try suggest.auditAccessibility()

        suggest.tap("Rückgängig")
        suggest.assertShows("Die Abteilungsleitung prüft deinen Vorschlag.")
        XCTAssertEqual(programs.app.textFields["Titel"].value as? String, "Serverfehler")
    }

    // MARK: A6, A7

    func testProfileCalendarLinkGroupsAndNotifications() throws {
        let programs = signedIn(.parent)
        TabBar(app: programs.app).open(.profile)
        let profile = ProfileScreen(app: programs.app).waitUntilDisplayed()
        profile.assertShows("Meine Gruppen", "Stufe Jungschar", "Mein Kalender-Link", "Der Link gehört nur dir.")
        try profile.auditAccessibility()

        profile.tap("Link erzeugen")
        profile.assertShows("Dein Link ist bereit.", "Teilen oder kopieren")
        try profile.auditAccessibility()
        // The address is never shown on screen.
        try profile.assertNotShown("ui-test-token")
        profile.tap("Fertig")
        profile.assertShows("Der alte Link funktioniert danach nicht mehr.")
        profile.tap("Link neu erzeugen")
        profile.app.sheets.buttons["Link neu erzeugen"].tap()
        profile.assertShows("Dein Link ist bereit.")
        profile.tap("Fertig")
        profile.tap("Link widerrufen")
        profile.app.sheets.buttons["Link widerrufen"].tap()
        profile.assertShows("Link erzeugen")

        let notifications = profile.openNotifications()
        notifications.assertShows("Was dir die App meldet", "Chat")
        try notifications.auditAccessibility()
    }

    func testLeaderNotificationsShowCampKinds() throws {
        let programs = signedIn(.leader)
        TabBar(app: programs.app).open(.profile)
        let notifications = ProfileScreen(app: programs.app).waitUntilDisplayed().openNotifications()
        notifications.assertShows("Aufgaben", "Erwähnungen")
        notifications.setSwitch("Aufgaben", on: true)
        try notifications.auditAccessibility()
    }

    // MARK: States and sizes

    func testRoomsEmptyAndOccasionClosed() throws {
        let empty = signedIn(.parent, failure: .noRooms)
        empty.openMenu("Raum anfragen")
        let room = RequestRoomScreen(app: empty.app).waitUntilDisplayed()
        room.assertShows("Keine Räume", "Die Abteilungsleitung hat noch keine Räume erfasst.")
        try room.auditAccessibility()

        let closed = signedIn(.parent, failure: .occasionClosed)
        let registration = closed.open("Sommerlager Beispiel 2027").openRegistration("Zur Anmeldung")
        registration.assertShows("Anmeldung geschlossen", "Die Anmeldung ist geschlossen. Frag die Leitung.")
        try registration.auditAccessibility()
    }

    func testFormsLargestTextAndDark() throws {
        let large = signedIn(.leader, textSize: .largest)
        large.openMenu("Termin vorschlagen")
        try SuggestEventScreen(app: large.app).waitUntilDisplayed().auditAccessibility()

        let dark = signedIn(.parent, appearance: .dark)
        dark.openMenu("Raum anfragen")
        try RequestRoomScreen(app: dark.app).waitUntilDisplayed().auditAccessibility()
    }
}
