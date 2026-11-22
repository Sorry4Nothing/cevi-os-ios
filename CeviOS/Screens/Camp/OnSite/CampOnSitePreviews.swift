#if DEBUG
import SwiftUI

/// Invented sample data for the previews of the on-site screens (day 3 of the camp is 19 July 2027).
@MainActor
enum CampOnSitePreview {
    static let now = DateFormats.calendarDay("2027-07-19") ?? Date()
    private static let me = CampPreview.personId

    static func uuid(_ group: Int, _ n: Int) -> UUID {
        UUID(uuidString: "0190a000-0000-7000-8000-0000000\(String(format: "%02d", group))\(String(format: "%03d", n))") ?? UUID()
    }

    private static func environment(_ role: CampRole, _ status: String, offline: Bool) -> ActiveCamp {
        CampPreview.active(role: role, status: status, waiting: offline ? 1 : 0, offline: offline)
    }

    private static func finish(_ model: CampRosterModel, phase: CampPhase, offline: Bool, error: String?, notice: CampRosterModel.Notice?) {
        model.now = { now }
        model.phase = phase
        model.error = error
        model.notice = notice
        model.staleSince = offline ? now : nil
    }

    private static func todo(_ n: Int, _ title: String, done: Bool = false, due: String = "2027-07-19") -> CampTask {
        CampPreview.task(n, title, code: "KÜ", portfolio: "Küche", person: "Mara|Luchs", due: due, status: done ? "erledigt" : "offen")
    }

    // MARK: L4 Today

    static let sections: [CampDaySection] = [
        CampPreview.decode(#"{"id":"\#(uuid(10, 1))","version":1,"name":"Frühstück","zeit":"07:00–10:00","reihenfolge":0}"#),
        CampPreview.decode(#"{"id":"\#(uuid(10, 2))","version":1,"name":"Mittag","zeit":"11:00–13:30","reihenfolge":1}"#),
        CampPreview.decode(#"{"id":"\#(uuid(10, 3))","version":1,"name":"Abend","zeit":"17:00–19:30","reihenfolge":2}"#),
    ]

    private static func dayJSON(_ n: Int, _ date: String) -> String { #"{"id":"\#(uuid(11, n))","datum":"\#(date)","label":null}"# }

    private static func pageJSON(chief: Bool = true, note: String? = nil) -> String {
        """
        {"id":"\(uuid(12, 1))","version":1,"lagertagId":"\(uuid(11, 3))","tageschefPersonId":\(chief ? "\"\(uuid(13, 1))\"" : "null"),"notiz":\(note.map { "\"\($0)\"" } ?? "null"),
         "tageschef":\(chief ? #"{"id":"\#(uuid(13, 1))","name":"Mara","ceviName":"Luchs"}"# : "null")}
        """
    }

    private static func blockJSON(_ n: Int, _ kind: String, _ text: String) -> String {
        #"{"id":"\#(uuid(14, n))","version":1,"seiteId":"\#(uuid(12, 1))","art":"\#(kind)","text":"\#(text)","dateiId":null,"reihenfolge":\#(n),"datei":null}"#
    }

    static func today(phase: CampPhase = .loaded, empty: Bool = false, offline: Bool = false, error: String? = nil, role: CampRole = .leader, status: String = "aktiv") -> some View {
        let active = environment(role, status, offline: offline)
        let model = CampTodayModel(active: active, personId: me)
        let blocks = empty ? "" : [blockJSON(1, "wichtig", "Abfahrt zum Waldspiel um 13:30"), blockJSON(2, "wichtig", "Wölfe bringen Taschenlampen mit")].joined(separator: ",")
        model.today = CampPreview.decode("""
        {"datum":"2027-07-19","lagertag":\(dayJSON(3, "2027-07-19")),"tagesseite":{"seite":\(pageJSON()),"bloecke":[\(blocks)],"aufgaben":[]},
         "wetter":null,"anwesenheit":null,"schichten":null,"hoecks":null}
        """)
        model.sections = sections
        if !empty {
            model.myWeek = CampPreview.decode("""
            {"von":"2027-07-19","bis":"2027-07-26","aufgaben":[],"hoecks":[],"schichten":[
             {"id":"\(uuid(15, 1))","version":1,"dienstId":"\(uuid(16, 1))","lagertagId":"\(uuid(11, 3))","datum":"2027-07-19","tagesabschnittId":"\(uuid(10, 1))",
              "personId":"\(me)","teilnehmerId":null,"name":"Mara","ceviName":"Luchs","stufe":null,"dienst":{"id":"\(uuid(16, 1))","name":"Küche","nacht":false}}]}
            """)
            model.todos = [todo(1, "Znüni bereitstellen", done: true), todo(2, "Abwaschplan aufhängen"), todo(3, "Packliste prüfen")]
        }
        if offline { model.queuedIds = [model.todos.dropFirst(1).first?.id ?? UUID()] }
        finish(model, phase: phase, offline: offline, error: error, notice: nil)
        return NavigationStack { CampTodayScreen(model: model) }.environment(active)
    }

    // MARK: L26 Attendance

    private static let people: [(String, Int)] = [("Mara (Luchs)", 1), ("Jonas (Fuchs)", 2), ("Lea (Biber)", 3), ("Tim (Spatz)", 4)]
    private static let dayDates = ["2027-07-17", "2027-07-18", "2027-07-19", "2027-07-20"]

    private static func entryJSON(_ person: Int, _ section: Int, _ value: String) -> String {
        #"{"id":"\#(uuid(20 + person, section))","version":1,"personId":"\#(uuid(13, person))","teilnehmerId":null,"lagertagId":"\#(uuid(11, 3))","tagesabschnittId":"\#(uuid(10, section))","wert":"\#(value)"}"#
    }

    static func attendance(phase: CampPhase = .loaded, offline: Bool = false, error: String? = nil, notice: CampRosterModel.Notice? = nil, status: String = "aktiv",
                           role: CampRole = .campLeader, busy: Bool = false, pending: Bool = false, requests: Bool = false) -> some View {
        let active = environment(role, status, offline: offline)
        let ownIndex = 3
        let model = CampAttendanceModel(active: active, personId: role == .campLeader ? me : uuid(13, ownIndex), ownLabel: people[ownIndex - 1].0)
        model.days = dayDates.enumerated().map { CampPreview.decode(#"{"id":"\#(uuid(11, $0.offset + 1))","version":1,"datum":"\#($0.element)","label":null}"#) }
        model.sections = sections
        model.selectedDayId = uuid(11, 3)
        let all: [(Int, Int, String)] = [(1, 1, "A"), (1, 2, "A"), (1, 3, "A"), (2, 1, "A"), (2, 2, "F"), (2, 3, "A"), (4, 1, "A"), (4, 2, "A"), (4, 3, "F")]
        let team = role != .campLeader
        model.entries = (team ? [] : all).map { CampPreview.decode(entryJSON($0.0, $0.1, $0.2)) }
        model.people = people.map { CampPersonChoice(id: uuid(13, $0.1), isParticipant: false, label: $0.0) }
        if requests {
            model.requests = [CampPreview.decode("""
            {"id":"\(uuid(30, 1))","version":1,"personId":"\(uuid(13, 3))","lagertagId":"\(uuid(11, 3))","tagesabschnittId":"\(uuid(10, 1))","wert":"F","notiz":"Arzttermin",
             "status":"offen","entschiedenVon":null,"entschiedenAm":null,"erstelltAm":"2027-07-18T08:00:00Z"}
            """)]
        }
        if busy { model.busyId = uuid(13, 3) }
        if pending { model.pending = .init(fields: [], message: "Du hast für Montag schon etwas eingetragen. Die Lagerleitung muss die Änderung bestätigen.") }
        finish(model, phase: phase, offline: offline, error: error, notice: notice)
        return NavigationStack { CampAttendanceScreen(model: model) }.environment(active)
    }

    // MARK: L27 Day page

    static func dayPage(phase: CampPhase = .loaded, empty: Bool = false, offline: Bool = false, status: String = "aktiv", role: CampRole = .leader) -> some View {
        let active = environment(role, status, offline: offline)
        let model = CampDayPageModel(active: active, personId: me, dayId: uuid(11, 3), date: now)
        let content = empty ? #""seite":null,"bloecke":[],"wetter":null"# : """
        "seite":\(pageJSON()),"bloecke":[\(blockJSON(1, "wichtig", "Abfahrt zum Waldspiel um 13:30")),\(blockJSON(2, "idee", "Singen am Feuer"))],
        "wetter":{"datum":"2027-07-19","code":1,"tmax":24,"tmin":13,"regen":0,"boeen":20,"zustand":"Sonnig","warnungen":[]}
        """
        model.detail = CampPreview.decode(#"{"lagertag":\#(dayJSON(3, "2027-07-19")),\#(content),"wetterStand":null,"aufgaben":[]}"#)
        if !empty { model.todos = [todo(1, "Feuerholz bereitlegen"), todo(2, "Fotos sichern", done: true)] }
        if offline { model.queuedIds = [model.todos.first?.id ?? UUID()] }
        finish(model, phase: phase, offline: offline, error: nil, notice: nil)
        return NavigationStack { CampDayPageScreen(model: model) }.environment(active)
    }

    // MARK: L28 Shopping

    private static func item(_ n: Int, _ name: String, _ amount: Double, _ unit: String, _ group: String, buyer: String, done: Bool = false) -> CampShoppingItem {
        CampPreview.decode("""
        {"id":"\(uuid(40, n))","version":1,"name":"\(name)","menge":\(amount),"einheit":"\(unit)","warengruppe":"\(group)","einkaeuferPersonId":"\(uuid(13, buyer == "Jonas" ? 2 : 4))",
         "einkaeufer":{"id":"\(uuid(13, buyer == "Jonas" ? 2 : 4))","name":"\(buyer)","ceviName":null},"erledigt":\(done)}
        """)
    }

    static func shopping(phase: CampPhase = .loaded, empty: Bool = false, offline: Bool = false, error: String? = nil, notice: CampRosterModel.Notice? = nil,
                         status: String = "aktiv", role: CampRole = .leader, adding: Bool = false) -> some View {
        let active = environment(role, status, offline: offline)
        let model = CampShoppingModel(active: active)
        model.items = empty ? [] : [item(1, "Äpfel", 6, "kg", "obst_gemuese", buyer: "Jonas"), item(2, "Rüebli", 4, "kg", "obst_gemuese", buyer: "Jonas"),
                                    item(3, "Reis", 12, "kg", "vorrat", buyer: "Tim"), item(4, "Teigwaren", 8, "kg", "vorrat", buyer: "Tim"), item(5, "Milch", 24, "l", "milch_kaese", buyer: "Jonas")]
        finish(model, phase: phase, offline: offline, error: error, notice: notice)
        if notice != nil { model.lastTicked = model.items.first }
        return Group {
            if adding {
                CampShoppingAddSheet(model: { model.suggestions = [CampShoppingSuggestion(name: "Reibkäse", frequency: 3)]; return model }()) {}
            } else {
                NavigationStack { CampShoppingScreen(model: model) }
            }
        }
        .environment(active)
    }

    // MARK: L29 Packing

    static func packing(phase: CampPhase = .loaded, empty: Bool = false, offline: Bool = false, status: String = "aktiv", role: CampRole = .campLeader) -> some View {
        let active = environment(role, status, offline: offline)
        let model = CampPackingModel(active: active)
        func point(_ n: Int, _ section: String, _ text: String, state: String, lead: Bool = false) -> String {
            #"{"id":"\#(uuid(50, n))","version":1,"abschnitt":"\#(section)","text":"\#(text)","nurLagerleitung":\#(lead),"reihenfolge":\#(n),"zustand":"\#(state)"}"#
        }
        let points = [point(1, "Kleidung", "Regenjacke", state: "abgehakt"), point(2, "Kleidung", "Feste Schuhe", state: "abgehakt"), point(3, "Kleidung", "Warmer Pullover", state: "offen"),
                      point(4, "Schlafen", "Schlafsack", state: "offen"), point(5, "Schlafen", "Mätteli", state: "offen"),
                      point(6, "Sonstiges", "Erste-Hilfe-Set", state: "offen", lead: true)]
        model.list = CampPreview.decode(#"{"punkte":[\#(empty ? "" : points.joined(separator: ","))],"eigene":[\#(empty ? "" : #"{"id":"\#(uuid(51, 1))","text":"Taschenlampe","abschnitt":"Sonstiges","abgehakt":false,"reihenfolge":7}"#)]}"#)
        finish(model, phase: phase, offline: offline, error: nil, notice: nil)
        return NavigationStack { CampPackingScreen(model: model) }.environment(active)
    }

    // MARK: L30 Emergency

    static func emergency(phase: CampPhase = .loaded, offline: Bool = false, status: String = "aktiv", noAddress: Bool = false) -> some View {
        let active = environment(.team, status, offline: offline)
        let model = CampEmergencyModel(active: active)
        model.emergency = CampPreview.decode("""
        {"adresse":{"ort":\(noAddress ? "null" : "\"Lagerhaus Beispielberg\""),"adresse":\(noAddress ? "null" : "\"Waldweg 1, 0000 Beispielberg\""),"kartenLink":null},
         "kontakte":[{"quelle":"eintrag","id":"\(uuid(60, 1))","version":1,"funktion":"Sicherheitsverantwortlicher","personId":null,"name":"Tim","ceviName":"Spatz","telefon":"+41 00 000 00 00","reihenfolge":1},
                     {"quelle":"ressort","id":null,"version":null,"funktion":"Lagerleitung","personId":"\(uuid(13, 1))","name":"Mara","ceviName":"Luchs","telefon":"+41 00 000 00 00","reihenfolge":null}],
         "infos":[]}
        """)
        finish(model, phase: phase, offline: offline, error: nil, notice: nil)
        model.loadedAt = DateFormats.calendarDay("2027-07-19").map { $0.addingTimeInterval(18 * 3600 + 120) } ?? now
        return NavigationStack { CampEmergencyScreen(model: model) }.environment(active)
    }

    // MARK: L32 Infos

    static func infos(phase: CampPhase = .loaded, empty: Bool = false, offline: Bool = false, status: String = "aktiv", role: CampRole = .campLeader, reordering: Bool = false) -> some View {
        let active = environment(role, status, offline: offline)
        let model = CampInfosModel(active: active)
        func info(_ n: Int, _ title: String, _ text: String, lead: Bool = false) -> CampInfo {
            CampPreview.decode(#"{"id":"\#(uuid(70, n))","version":1,"titel":"\#(title)","text":"\#(text)","links":[],"nurLagerleitung":\#(lead),"notfall":false,"reihenfolge":\#(n),"dateien":[]}"#)
        }
        model.infos = empty ? [] : [info(1, "Lagerhaus", "Lagerhaus Beispielberg, 60 Betten, Küche mit Gasherd. Schlüssel beim Hauswart."),
                                    info(2, "Regeln", "Nachtruhe 22:00. Kein Handy beim Essen. Abfall trennen."),
                                    info(3, "Tagesablauf", "07:30 Morgenessen, 12:15 Mittagessen, 18:30 Nachtessen."),
                                    info(4, "Finanzen", "Budget und Abrechnung liegen im Ressort Finanzen.", lead: true)].filter { role == .campLeader || !$0.leadershipOnly }
        model.isReordering = reordering
        finish(model, phase: phase, offline: offline, error: nil, notice: nil)
        return NavigationStack { CampInfosScreen(model: model) }.environment(active)
    }
}

#Preview("L4 Normal") { CampOnSitePreview.today() }
#Preview("L4 Nacht") { CampOnSitePreview.today().preferredColorScheme(.dark) }
#Preview("L4 Laden") { CampOnSitePreview.today(phase: .loading) }
#Preview("L4 Leer") { CampOnSitePreview.today(empty: true) }
#Preview("L4 Fehler") { CampOnSitePreview.today(phase: .failed(state: nil, text: "x")) }
#Preview("L4 Ohne Netz") { CampOnSitePreview.today(offline: true) }
#Preview("L4 Textgrösse AX3") { CampOnSitePreview.today().dynamicTypeSize(.accessibility3) }

#Preview("L26 Normal") { CampOnSitePreview.attendance() }
#Preview("L26 Nacht") { CampOnSitePreview.attendance().preferredColorScheme(.dark) }
#Preview("L26 Laden") { CampOnSitePreview.attendance(phase: .loading) }
#Preview("L26 Fehler") { CampOnSitePreview.attendance(phase: .failed(state: nil, text: "x")) }
#Preview("L26 Ohne Netz") { CampOnSitePreview.attendance(offline: true) }
#Preview("L26 Aktion läuft") { CampOnSitePreview.attendance(busy: true) }
#Preview("L26 Fehler beim Speichern") { CampOnSitePreview.attendance(error: "Deine Eingabe ist noch da. Versuche es nochmals.") }
#Preview("L26 Anfrage nötig") { CampOnSitePreview.attendance(role: .team, pending: true) }
#Preview("L26 Anfragen der Lagerleitung") { CampOnSitePreview.attendance(requests: true) }
#Preview("L26 Nur eigene Zeile") { CampOnSitePreview.attendance(role: .team) }
#Preview("L26 Nur eigene Zeile Nacht") { CampOnSitePreview.attendance(role: .team).preferredColorScheme(.dark) }
#Preview("L26 Abgeschlossen") { CampOnSitePreview.attendance(status: "abgeschlossen") }
#Preview("L26 Textgrösse AX3") { CampOnSitePreview.attendance().dynamicTypeSize(.accessibility3) }

#Preview("L27 Normal") { CampOnSitePreview.dayPage() }
#Preview("L27 Nacht") { CampOnSitePreview.dayPage().preferredColorScheme(.dark) }
#Preview("L27 Laden") { CampOnSitePreview.dayPage(phase: .loading) }
#Preview("L27 Leer") { CampOnSitePreview.dayPage(empty: true) }
#Preview("L27 Fehler") { CampOnSitePreview.dayPage(phase: .failed(state: nil, text: "x")) }
#Preview("L27 Ohne Netz") { CampOnSitePreview.dayPage(offline: true) }
#Preview("L27 Abgeschlossen") { CampOnSitePreview.dayPage(status: "abgeschlossen") }
#Preview("L27 Textgrösse AX3") { CampOnSitePreview.dayPage().dynamicTypeSize(.accessibility3) }

#Preview("L28 Normal") { CampOnSitePreview.shopping() }
#Preview("L28 Nacht") { CampOnSitePreview.shopping().preferredColorScheme(.dark) }
#Preview("L28 Laden") { CampOnSitePreview.shopping(phase: .loading) }
#Preview("L28 Leer") { CampOnSitePreview.shopping(empty: true) }
#Preview("L28 Fehler") { CampOnSitePreview.shopping(phase: .failed(state: nil, text: "x")) }
#Preview("L28 Ohne Netz") { CampOnSitePreview.shopping(offline: true) }
#Preview("L28 Artikel hinzufügen") { CampOnSitePreview.shopping(adding: true) }
#Preview("L28 Fehler beim Speichern") { CampOnSitePreview.shopping(error: "Deine Eingabe ist noch da. Versuche es nochmals.") }
#Preview("L28 Rückgängig") { CampOnSitePreview.shopping(notice: .init(title: "Reis abgehakt.")) }
#Preview("L28 Textgrösse AX3") { CampOnSitePreview.shopping().dynamicTypeSize(.accessibility3) }

#Preview("L29 Normal") { CampOnSitePreview.packing() }
#Preview("L29 Nacht") { CampOnSitePreview.packing().preferredColorScheme(.dark) }
#Preview("L29 Laden") { CampOnSitePreview.packing(phase: .loading) }
#Preview("L29 Leer") { CampOnSitePreview.packing(empty: true) }
#Preview("L29 Fehler") { CampOnSitePreview.packing(phase: .failed(state: nil, text: "x")) }
#Preview("L29 Ohne Netz") { CampOnSitePreview.packing(offline: true) }
#Preview("L29 Abgeschlossen") { CampOnSitePreview.packing(status: "abgeschlossen") }
#Preview("L29 Textgrösse AX3") { CampOnSitePreview.packing().dynamicTypeSize(.accessibility3) }

#Preview("L30 Normal") { CampOnSitePreview.emergency() }
#Preview("L30 Nacht") { CampOnSitePreview.emergency().preferredColorScheme(.dark) }
#Preview("L30 Laden") { CampOnSitePreview.emergency(phase: .loading) }
#Preview("L30 Fehler") { CampOnSitePreview.emergency(phase: .failed(state: nil, text: "x")) }
#Preview("L30 Ohne Netz") { CampOnSitePreview.emergency(offline: true) }
#Preview("L30 Ohne Adresse") { CampOnSitePreview.emergency(noAddress: true) }
#Preview("L30 Textgrösse AX3") { CampOnSitePreview.emergency().dynamicTypeSize(.accessibility3) }

#Preview("L32 Normal") { CampOnSitePreview.infos() }
#Preview("L32 Nacht") { CampOnSitePreview.infos().preferredColorScheme(.dark) }
#Preview("L32 Laden") { CampOnSitePreview.infos(phase: .loading) }
#Preview("L32 Leer") { CampOnSitePreview.infos(empty: true) }
#Preview("L32 Fehler") { CampOnSitePreview.infos(phase: .failed(state: nil, text: "x")) }
#Preview("L32 Ohne Netz") { CampOnSitePreview.infos(offline: true) }
#Preview("L32 Sortieren") { CampOnSitePreview.infos(reordering: true) }
#Preview("L32 Für die Lagerleitung") { CampOnSitePreview.infos(role: .team) }
#Preview("L32 Abgeschlossen") { CampOnSitePreview.infos(status: "abgeschlossen") }
#Preview("L32 Textgrösse AX3") { CampOnSitePreview.infos().dynamicTypeSize(.accessibility3) }
#endif
