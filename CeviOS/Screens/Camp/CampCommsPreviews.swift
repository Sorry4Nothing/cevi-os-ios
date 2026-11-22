#if DEBUG
import SwiftUI

/// Invented sample data for the previews of the meeting and communication screens (today is 22 May 2027).
@MainActor
enum CampCommsPreview {
    static let today = CampPreview.startToday
    static let meetingId = UUID(uuidString: "0190a000-0000-7000-8000-000000000901") ?? UUID()
    private static let who = CampPreview.personId

    private static func id(_ n: Int) -> String { "0190a000-0000-7000-8000-0000000009\(String(format: "%02d", n))" }
    private static func person(_ name: String, _ cevi: String) -> String { #"{"id":"\#(who)","name":"\#(name)","ceviName":"\#(cevi)"}"# }

    // MARK: Meetings

    static func agendaItem(_ n: Int, _ title: String, status: String = "offen", text: String? = nil, decision: String? = nil) -> String {
        """
        {"id":"\(id(10 + n))","version":1,"hoeckId":"\(meetingId)","titel":"\(title)","text":\(text.map { "\"\($0)\"" } ?? "null"),"entscheid":\(decision.map { "\"\($0)\"" } ?? "null"),
         "links":[],"reihenfolge":\(n),"aufgabeId":null,"status":"\(status)","verantwortliche":[]}
        """
    }

    static func meeting(empty: Bool = false) -> CampMeeting {
        let titles = ["Lagerhaus und Offerte", "Programm Waldspiel", "Einkauf und Küche", "Fahrten Hin und Zurück", "Varia"]
        let items = empty ? "" : titles.enumerated().map { agendaItem($0.offset + 1, $0.element, text: $0.offset == 0 ? "Zwei Angebote liegen vor, Beispielberg ist günstiger." : nil, decision: $0.offset == 0 ? "Wir buchen das Lagerhaus Beispielberg." : nil) }.joined(separator: ",")
        return CampPreview.decode("""
        {"id":"\(meetingId)","version":1,"art":"lagerleitung","datum":"2027-05-26","zeit":"19:30","titel":"Hoeck 5","ort":"Pfadiheim Beispielwald","gaeste":null,
         "protokollId":"\(id(50))","anwesende":[\(person("Mara", "Luchs")),\(person("Jonas", "Fuchs")),\(person("Lea", "Biber")),\(person("Tim", "Spatz"))],"traktanden":[\(items)]}
        """)
    }

    static func row(_ n: Int, _ title: String, _ date: String, place: String?, agenda: Int?, hasProtocol: Bool = false) -> CampMeetingsModel.Row {
        CampMeetingsModel.Row(id: UUID(uuidString: id(60 + n)) ?? UUID(), version: 1, kind: agenda == nil ? nil : .campLeadership, date: DateFormats.calendarDay(date) ?? today,
                              time: "19:30", title: title, place: place, agendaCount: agenda, protocolId: hasProtocol ? UUID() : nil)
    }

    static func meetings(phase: CampPhase = .loaded, empty: Bool = false, offline: Bool = false, waiting: Int = 0, status: String = "aktiv", role: CampRole = .campLeader) -> some View {
        let active = CampPreview.active(role: role, status: status, waiting: waiting, offline: offline)
        let model = CampMeetingsModel(active: active)
        model.now = { today }
        let team = role == .team
        model.setPreview(phase: phase, rows: empty ? [] : [row(5, "Hoeck 5", "2027-05-26", place: "Pfadiheim Beispielwald", agenda: team ? nil : 5),
                                                          row(6, "Hoeck 6", "2027-06-09", place: "Online", agenda: team ? nil : 2),
                                                          row(4, "Hoeck 4", "2027-05-12", place: "Pfadiheim Beispielwald", agenda: team ? nil : 6, hasProtocol: !team)], offline: offline)
        return NavigationStack { CampMeetingsScreen(model: model) }.environment(active)
    }

    static func agenda(phase: CampPhase = .loaded, empty: Bool = false, offline: Bool = false, notice: CampAgendaModel.Notice? = nil, status: String = "aktiv", role: CampRole = .campLeader) -> some View {
        let active = CampPreview.active(role: role, status: status, waiting: offline ? 3 : 0, offline: offline)
        let model = CampAgendaModel(active: active, meetingId: meetingId)
        model.now = { today }
        let waiting: [CampAgendaItem] = notice == nil ? [] : [CampPreview.decode(agendaItem(9, "Varia"))]
        model.setPreview(phase: phase, meeting: meeting(empty: empty), waiting: waiting, notice: notice, offline: offline)
        return NavigationStack { CampAgendaScreen(model: model) }.environment(active)
    }

    static func meetingMode(phase: CampPhase = .loaded, offline: Bool = false, error: String? = nil) -> some View {
        let active = CampPreview.active(waiting: offline ? 1 : 0, offline: offline)
        let model = CampMeetingModeModel(active: active, meetingId: meetingId)
        model.now = { today }
        let mode: CampMeetingMode = CampPreview.decode("""
        {"hoeck":{"id":"\(meetingId)","version":1,"art":"lagerleitung","datum":"2027-05-26","zeit":"19:30","titel":"Hoeck 5","ort":null,"gaeste":null,"protokollId":null,"traktanden":[\(agendaItem(1, "Lagerhaus und Offerte", status: "besprochen")),\(agendaItem(2, "Programm Waldspiel"))]},
         "mitglieder":[
           {"id":"\(id(71))","name":"Mara","ceviName":"Luchs","rolle":"lagerleitung","anwesend":true},{"id":"\(id(72))","name":"Jonas","ceviName":"Fuchs","rolle":"leitung","anwesend":true},
           {"id":"\(id(73))","name":"Lea","ceviName":"Biber","rolle":"leitung","anwesend":true},{"id":"\(id(74))","name":"Tim","ceviName":"Spatz","rolle":"leitung","anwesend":true},
           {"id":"\(id(75))","name":"Sina","ceviName":"Eule","rolle":"leitung","anwesend":false}],
         "ressortRunde":[{"id":"\(id(81))","kuerzel":"KÜ","name":"Küche","leitung":\(person("Jonas", "Fuchs")),"aufgaben":{"gesamt":8,"erledigt":6,"offen":2,"ueberfaellig":0}},
                         {"id":"\(id(82))","kuerzel":"LO","name":"Logistik","leitung":\(person("Tim", "Spatz")),"aufgaben":{"gesamt":10,"erledigt":6,"offen":4,"ueberfaellig":1}}]}
        """)
        model.setPreview(phase: phase, mode: mode, offline: offline, error: error)
        return NavigationStack { CampMeetingModeScreen(model: model) }.environment(active)
    }

    private static func minutesRow(title: String = "Protokoll Hoeck 5") -> CampProtocol {
        CampPreview.decode("""
        {"id":"\(id(50))","version":2,"art":"sitzung","titel":"\(title)","datum":"2027-05-26","hoeckId":"\(meetingId)","dateiId":"\(id(51))",
         "datei":{"id":"\(id(51))","version":1,"anzeigename":"Protokoll Hoeck 5.docx","link":"https://example.org/protokoll","typ":null,"groesse":null,"hinzugefuegtVon":null,"hinzugefuegtAm":"2027-05-26T20:00:00Z"},
         "erstelltAm":"2027-05-26T20:00:00Z","erstelltVon":null}
        """)
    }

    static func minutes(phase: CampPhase = .loaded, saveFailed: Bool = false, offline: Bool = false, status: String = "aktiv", role: CampRole = .campLeader) -> some View {
        let active = CampPreview.active(role: role, status: status, waiting: offline ? 3 : 0, offline: offline)
        let model = CampProtocolModel(active: active, meetingId: meetingId)
        model.now = { today }
        let resolution: CampResolution = CampPreview.decode(#"{"id":"\#(id(55))","version":1,"text":"Wir buchen das Lagerhaus Beispielberg.","protokollId":"\#(id(50))","hoeckId":"\#(meetingId)","erstelltAm":"2027-05-26T20:00:00Z","erstelltVon":null}"#)
        model.setPreview(phase: phase, meeting: meeting(), minutes: minutesRow(), resolutions: [resolution], offline: offline,
                         error: saveFailed ? "Keine Verbindung zum Server. Bitte später nochmals versuchen." : nil, saveFailed: saveFailed)
        return NavigationStack { CampProtocolScreen(model: model) }.environment(active)
    }

    static func minutesConflict() -> some View {
        let active = CampPreview.active()
        let model = CampProtocolModel(active: active, meetingId: meetingId)
        model.setPreview(phase: .loaded, meeting: meeting(), minutes: minutesRow(), resolutions: [])
        model.conflict = .init(current: minutesRow(title: "Protokoll Hoeck 5 (Lea)"), mine: .init(title: "Protokoll Hoeck 5", kind: .meeting, date: today))
        return NavigationStack { CampProtocolScreen(model: model) }.environment(active)
    }

    // MARK: Communication

    static func mentions(phase: CampPhase = .loaded, empty: Bool = false, notice: CampMentionsModel.Notice? = nil, status: String = "aktiv") -> some View {
        let active = CampPreview.active(status: status)
        let model = CampMentionsModel(active: active)
        model.now = { today }
        let list: [CampMention] = empty ? [] : [
            CampPreview.decode(#"{"id":"\#(id(21))","titel":"@Tim fragt die Offerte bis Freitag nach.","quelleTyp":"beschluss","quelleId":"\#(id(22))","erledigt":false,"aufgabeId":null,"erstelltAm":"2027-05-19T08:00:00Z"}"#),
            CampPreview.decode(#"{"id":"\#(id(23))","titel":"@Tim kannst du die Zelte zählen?","quelleTyp":"pinnwand","quelleId":"\#(id(24))","erledigt":false,"aufgabeId":null,"erstelltAm":"2027-05-21T08:00:00Z"}"#),
            CampPreview.decode(#"{"id":"\#(id(25))","titel":"@Tim Packliste prüfen","quelleTyp":"aufgabe","quelleId":"\#(id(26))","erledigt":true,"aufgabeId":null,"erstelltAm":"2027-05-10T08:00:00Z"}"#)]
        model.setPreview(phase: phase, mentions: list, notice: notice)
        return NavigationStack { CampMentionsScreen(model: model) }.environment(active)
    }

    private static func notice(_ n: Int, _ title: String, text: String, important: Bool = false, pinned: Bool = false, until: String? = nil, roles: String = "[]",
                               poll: String = "null", files: String = "[]", reactions: String = #"{"zaehler":{"daumen":6},"eigene":null}"#) -> String {
        """
        {"id":"\(id(30 + n))","version":1,"titel":"\(title)","text":"\(text)","wichtig":\(important),"angeheftet":\(pinned),"sichtbarAb":null,"sichtbarBis":\(until.map { "\"\($0)\"" } ?? "null"),
         "vonPersonId":"\(who)","erstelltAm":"2027-05-20T08:00:00Z","von":\(person("Mara", "Luchs")),"empfaenger":{"anAlle":\(roles == "[]"),"rollen":\(roles),"personen":[]},
         "dateien":\(files),"umfrage":\(poll),"reaktionen":\(reactions)}
        """
    }

    static func notices(phase: CampPhase = .loaded, empty: Bool = false, offline: Bool = false, status: String = "aktiv", role: CampRole = .campLeader) -> some View {
        let active = CampPreview.active(role: role, status: status, waiting: offline ? 2 : 0, offline: offline)
        let model = CampNoticesModel(active: active)
        model.now = { today }
        let file = #"[{"id":"\#(id(41))","version":1,"anzeigename":"Reiseplan.pdf","link":"https://example.org/reiseplan","typ":"application/pdf","groesse":null,"hinzugefuegtVon":null,"hinzugefuegtAm":"2027-05-20T08:00:00Z"}]"#
        let poll = #"{"id":"\#(id(42))","version":1,"mehrfach":false,"schliesstAm":null,"geschlossen":false,"namenFuerTeam":false,"namenSichtbar":false,"teilnehmende":14,"optionen":[{"id":"\#(id(43))","text":"Schwimmen","stimmen":9,"eigene":true,"personen":[]},{"id":"\#(id(44))","text":"Wanderung","stimmen":5,"eigene":false,"personen":[]}]}"#
        let list: [CampNotice] = empty ? [] : [
            CampPreview.decode(notice(1, "Abfahrt am Samstag 07:30", text: "Treffpunkt Bahnhof Beispielstadt, Gleis 3.", important: true, pinned: true, until: "2027-07-17T12:00:00Z", files: file)),
            CampPreview.decode(notice(2, "Welcher Ausflug am Mittwoch?", text: "", until: "2027-07-01T12:00:00Z", roles: #"["leitung"]"#, poll: poll, reactions: #"{"zaehler":{},"eigene":null}"#))]
        model.setPreview(phase: phase, notices: list, offline: offline)
        return NavigationStack { CampNoticesScreen(model: model) }.environment(active)
    }

    static func noticeForm(inputError: String? = nil, saveError: String? = nil, saving: Bool = false) -> some View {
        let active = CampPreview.active()
        let model = CampNoticeFormModel(active: active)
        model.title = "Welcher Ausflug am Mittwoch?"
        model.roles = [.leadership]
        model.options = inputError == nil ? ["Schwimmen", "Wanderung"] : ["Schwimmen", ""]
        model.visibleUntil = DateFormats.calendarDay("2027-07-01")
        model.setPreview(inputError: inputError, saveError: saveError, saving: saving)
        return CampNoticeFormView(model: model).environment(active)
    }

    static func inbox(phase: CampPhase = .loaded, empty: Bool = false, notice: CampInboxModel.Notice? = nil, error: String? = nil, status: String = "aktiv", role: CampRole = .campLeader) -> some View {
        let active = CampPreview.active(role: role, status: status)
        let model = CampInboxModel(active: active)
        model.now = { today }
        let list: [CampInboxEntry] = empty ? [] : [
            CampPreview.decode(#"{"id":"\#(id(91))","version":1,"art":"feedback","text":"Die Nachtruhe ist für die Wölfe zu spät.","anonym":true,"status":"neu","antwort":null,"beantwortetTag":null,"erstelltTag":"2027-05-22","ressortId":null,"traktandumId":null,"von":\#(person("Name", "Darf nicht erscheinen"))}"#),
            CampPreview.decode(#"{"id":"\#(id(92))","version":1,"art":"frage","text":"Wer kauft am Montag ein?","anonym":false,"status":"in_arbeit","antwort":null,"beantwortetTag":null,"erstelltTag":"2027-05-21","ressortId":null,"traktandumId":null,"von":\#(person("Jonas", "Fuchs"))}"#)]
        model.setPreview(phase: phase, entries: list, notice: notice, error: error)
        return NavigationStack { CampInboxScreen(model: model) }.environment(active)
    }

    static func notifications(phase: CampPhase = .loaded, empty: Bool = false, tab: CampNotificationsModel.Tab = .new) -> some View {
        let active = CampPreview.active()
        let model = CampNotificationsModel(active: active)
        let kinds = [("aufgabe_zugeteilt", 10), ("erwaehnung", 60), ("frist", 600), ("pinnwand_wichtig", 1500), ("eingang_antwort", 1600)]
        let list: [CampNotification] = empty ? [] : kinds.enumerated().map { index, kind in
            let date = DateFormats.timestampText(Date().addingTimeInterval(TimeInterval(-60 * kind.1)))
            return CampPreview.decode(#"{"id":"\#(id(95 - index))","art":"\#(kind.0)","objektTyp":"aufgabe","objektId":"\#(id(99))","gelesen":false,"erstelltAm":"\#(date)"}"#)
        }
        let settings = [CampNotificationKind.taskAssigned, .taskChanged, .mention, .deadline, .importantNotice, .feedbackReply, .shiftSwapRequest, .shiftSwapDecision, .attendanceRequest]
            .map { CampNotificationSetting(kind: $0, enabled: $0 != .taskChanged) }
        model.setPreview(phase: phase, entries: list, settings: settings)
        model.tab = tab
        return NavigationStack { CampNotificationsScreen(model: model) }.environment(active)
    }
}
#endif
