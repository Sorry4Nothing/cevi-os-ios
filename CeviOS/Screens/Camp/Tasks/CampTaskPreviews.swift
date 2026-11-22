#if DEBUG
import SwiftUI

/// Invented sample data for the previews of the task screens (today is 17 March 2027).
@MainActor
enum CampPreview {
    static let today = DateFormats.calendarDay("2027-03-17") ?? Date()
    static let personId = UUID(uuidString: "0190a000-0000-7000-8000-0000000000aa") ?? UUID()
    static let portfolioId = UUID(uuidString: "0190a000-0000-7000-8000-0000000000b1") ?? UUID()

    static func decode<T: Decodable>(_ json: String) -> T {
        // Sample data is written here; a typo is a programming error and shows at once.
        try! JSONDecoder.api.decode(T.self, from: Data(json.utf8))
    }

    static func active(role: CampRole = .campLeader, status: String = "aktiv", waiting: Int = 0, offline: Bool = false) -> ActiveCamp {
        let camp: Camp = decode("""
        {"id":"0190a000-0000-7000-8000-000000000001","titel":"Sommerlager 2027","von":"2027-07-17","bis":"2027-07-24","vorbereitungAb":null,
         "ort":"Lagerhaus Beispielberg","adresse":null,"status":"\(status)","farbe":null,"logoMediumId":null}
        """)
        let active = ActiveCamp()
        active.open(camp: camp, role: role, client: nil)
        active.setPreview(waiting: waiting, offline: offline)
        return active
    }

    static func task(_ n: Int, _ title: String, code: String, portfolio: String, person: String, due: String?, status: String = "offen", starred: Bool = false) -> CampTask {
        decode(taskJSON(n, title, code: code, portfolio: portfolio, person: person, due: due, status: status, starred: starred))
    }

    private static func taskJSON(_ n: Int, _ title: String, code: String, portfolio: String, person: String, due: String?, status: String = "offen", starred: Bool = false) -> String {
        """
        {"id":"0190a000-0000-7000-8000-0000000001\(String(format: "%02d", n))","version":2,"titel":"\(title)","ressortId":"\(portfolioId)","teil":null,
         "verantwortlichPersonId":"\(personId)","status":"\(status)","notiz":null,"frist":\(due.map { "\"\($0)\"" } ?? "null"),
         "fristMeilensteinId":null,"fristVersatzTage":null,"stern":\(starred),"laufend":false,"spaeterAb":null,"wiederholung":null,
         "reihenfolge":\(n),"quelle":null,"erledigtAm":null,
         "verantwortlich":{"id":"\(personId)","name":"\(person.split(separator: "|")[0])","ceviName":"\(person.split(separator: "|")[1])","automatisch":false},
         "ressort":{"id":"\(portfolioId)","kuerzel":"\(code)","name":"\(portfolio)"},"unterstuetzung":[]}
        """
    }

    static var tasks: [CampTask] {
        [task(1, "Offerte Lagerhaus einholen", code: "LO", portfolio: "Logistik", person: "Tim|Spatz", due: "2027-03-15", status: "laeuft"),
         task(2, "Packliste prüfen", code: "HL", portfolio: "Hauptleitung", person: "Mara|Luchs", due: "2027-03-22"),
         task(3, "Einkaufsliste abstimmen", code: "KÜ", portfolio: "Küche", person: "Jonas|Fuchs", due: "2027-03-29", status: "wartet"),
         task(4, "Programm Waldspiel planen", code: "SP", portfolio: "Stufenprogramm", person: "Lea|Biber", due: "2027-05-30"),
         task(5, "Zelte reservieren", code: "LO", portfolio: "Logistik", person: "Tim|Spatz", due: "2027-03-01", status: "erledigt")]
    }

    static let details: CampTaskDetails = decode("""
    {"aufgabeId":"0190a000-0000-7000-8000-000000000101","checkliste":[
      {"id":"0190a000-0000-7000-8000-000000000201","version":1,"aufgabeId":"0190a000-0000-7000-8000-000000000101","text":"Zwei Lagerhäuser anfragen","erledigt":true,"erledigtVonPersonId":null,"reihenfolge":0},
      {"id":"0190a000-0000-7000-8000-000000000202","version":1,"aufgabeId":"0190a000-0000-7000-8000-000000000101","text":"Preise vergleichen","erledigt":true,"erledigtVonPersonId":null,"reihenfolge":1},
      {"id":"0190a000-0000-7000-8000-000000000203","version":1,"aufgabeId":"0190a000-0000-7000-8000-000000000101","text":"Offerte an Mara senden","erledigt":false,"erledigtVonPersonId":null,"reihenfolge":2},
      {"id":"0190a000-0000-7000-8000-000000000204","version":1,"aufgabeId":"0190a000-0000-7000-8000-000000000101","text":"Vertrag unterschreiben","erledigt":false,"erledigtVonPersonId":null,"reihenfolge":3}],
     "links":[{"id":"0190a000-0000-7000-8000-000000000301","version":1,"aufgabeId":"0190a000-0000-7000-8000-000000000101","titel":"Angebot Lagerhaus","url":"https://example.org/angebot"}],
     "stichworte":[]}
    """)

    static let portfolios: [CampPortfolio] = [decode("""
    {"id":"\(portfolioId)","version":1,"kuerzel":"KÜ","name":"Küche","leitungPersonId":"\(personId)","stvPersonId":null,"notiz":null,"parentId":null,"reihenfolge":0,
     "leitung":{"id":"\(personId)","name":"Jonas","ceviName":"Fuchs"},"stv":{"id":"\(personId)","name":"Sina","ceviName":"Eule"}}
    """)]

    static let start: CampStart = decode("""
    {"heute":"2027-05-22","countdown":{"von":"2027-07-17","bis":"2027-07-24","tageBisBeginn":56,"tageBisEnde":63},
     "fortschritt":{"aufgaben":{"gesamt":50,"erledigt":31,"ueberfaellig":4},"meilensteine":{"gesamt":5,"vergangen":2,"naechster":null}},"ueberfaellig":[]}
    """)

    static var myWeek: CampMyWeek {
        decode("""
        {"von":"2027-05-22","bis":"2027-05-28","aufgaben":\(tasksJSON),"schichten":[],"hoecks":[
          {"id":"0190a000-0000-7000-8000-000000000401","version":1,"datum":"2027-05-26","zeit":"19:30","titel":"Hoeck 5","ort":"Pfadiheim Beispielwald"}]}
        """)
    }

    private static var tasksJSON: String {
        "[" + taskJSON(1, "Offerte Lagerhaus einholen", code: "LO", portfolio: "Logistik", person: "Tim|Spatz", due: "2027-05-20", status: "laeuft") + "]"
    }

    static let startToday = DateFormats.calendarDay("2027-05-22") ?? Date()

    static func startScreen(role: CampRole = .campLeader, status: String = "aktiv", phase: CampPhase = .loaded, empty: Bool = false,
                            waiting: Int = 0, offline: Bool = false) -> some View {
        let active = active(role: role, status: status, waiting: waiting, offline: offline)
        let model = CampStartModel(active: active)
        model.now = { startToday }
        model.setPreview(phase: phase, start: empty ? nil : start, myWeek: empty ? nil : myWeek, offline: offline)
        return CampStartScreen(model: model, personId: personId).environment(active)
    }

    static let suggestions: [CampTaskSuggestion] = {
        let result: CampTaskSuggestions = decode("""
        {"vorschlaege":[{"zeile":"Offerte @Jonas bis 15.3. #Logistik","titel":"Offerte",
          "person":{"status":"gefunden","text":"Jonas","kandidaten":[{"id":"\(personId)","name":"Jonas","ceviName":"Fuchs"}]},
          "ressort":{"status":"gefunden","text":"Logistik","kandidaten":[{"id":"\(portfolioId)","kuerzel":"LO","name":"Logistik"}]},
          "frist":{"datum":"2027-03-15","text":"15.3."},"hinweise":[]}]}
        """)
        return result.suggestions
    }()

    static let unknownPerson: [CampTaskSuggestion] = {
        let result: CampTaskSuggestions = decode("""
        {"vorschlaege":[{"zeile":"Offerte @Jona bis 15.3.","titel":"Offerte",
          "person":{"status":"unbekannt","text":"Jona","kandidaten":[{"id":"\(personId)","name":"Jonas","ceviName":"Fuchs"}]},
          "ressort":null,"frist":{"datum":"2027-03-15","text":"15.3."},"hinweise":[]}]}
        """)
        return result.suggestions
    }()

    static func quickEntry(text: String = "Offerte @Jonas bis 15.3. #Logistik", suggestions: [CampTaskSuggestion]? = nil, duplicate: Bool = false,
                           error: String? = nil, saving: Bool = false) -> some View {
        let active = active()
        let model = CampQuickEntryModel(active: active)
        model.text = text
        let existing: CampDuplicateTask = decode(#"{"id":"\#(tasks[0].id)","version":2,"titel":"Offerte Lagerhaus","status":"offen"}"#)
        model.setPreview(suggestions: suggestions ?? Self.suggestions, duplicate: duplicate ? .init(title: "Offerte", existing: existing) : nil, saving: saving, error: error)
        return CampQuickEntryView(model: model).environment(active)
    }

    static func portfolioScreen(phase: CampPhase = .loaded, empty: Bool = false, role: CampRole = .campLeader) -> some View {
        let active = active(role: role)
        let model = CampPortfolioModel(active: active, portfolioId: portfolioId)
        let notes: [CampPortfolioNote] = empty ? [] : [decode("""
        {"id":"0190a000-0000-7000-8000-000000000501","version":1,"ressortId":"\(portfolioId)","text":"Montag Risotto, Dienstag Spaghetti. @Tim holt den Gasherd.","vonPersonId":null,"erstelltAm":"2027-03-16T08:00:00Z","von":{"id":"\(personId)","name":"Jonas","ceviName":"Fuchs"}}
        """)]
        model.setPreview(phase: phase, portfolio: portfolios[0], notes: notes)
        return NavigationStack { CampPortfolioView(model: model) }.environment(active)
    }

    static func scheduleScreen(phase: CampPhase = .loaded, empty: Bool = false, calendar: Bool = false, offline: Bool = false, waiting: Int = 0) -> some View {
        let active = active(waiting: waiting, offline: offline)
        let model = CampScheduleModel(active: active)
        model.now = { today }
        let schedule: CampSchedule = decode("""
        {"meilensteine":\(empty ? "[]" : #"[{"id":"0190a000-0000-7000-8000-000000000601","version":1,"titel":"Lagerhaus gebucht","datum":"2027-03-19","art":null},{"id":"0190a000-0000-7000-8000-000000000602","version":1,"titel":"Anmeldeschluss","datum":"2027-07-10","art":null}]"#),
         "lagertage":[\(["17","18","19","20"].map { #"{"id":"0190a000-0000-7000-8000-0000000007\#($0)","version":1,"datum":"2027-07-\#($0)","label":null}"# }.joined(separator: ","))],"tagesabschnitte":[]}
        """)
        model.setPreview(phase: phase, schedule: schedule, tasks: empty ? [] : Self.tasks, offline: offline)
        model.tab = calendar ? .calendar : .schedule
        if calendar { model.shiftMonth(by: 0) }
        return NavigationStack { CampScheduleView(model: model).navigationTitle("Zeitplan") }.environment(active)
    }

    static func rights(_ role: CampRole) -> CampTaskRights { CampTaskRights(role: role, readOnly: false, personId: personId) }

    // MARK: Screens

    static func tasksScreen(role: CampRole = .campLeader, status: String = "aktiv", phase: CampPhase = .loaded, tasks: [CampTask]? = nil, waiting: Int = 0,
                            offline: Bool = false, notice: CampTasksModel.Notice? = nil, selecting: Bool = false,
                            mode: CampTasksScreen.Mode = .list, column: CampTaskStatus = .open) -> some View {
        let active = active(role: role, status: status, waiting: waiting, offline: offline)
        let model = CampTasksModel(active: active, personId: personId)
        model.now = { today }
        model.setPreview(phase: phase, tasks: tasks ?? Self.tasks, portfolios: portfolios, notice: notice)
        if selecting { model.startSelecting(model.tasks.first) }
        return CampTasksScreen(model: model, mode: mode, column: column).environment(active)
    }

    static func detailScreen(role: CampRole = .campLeader, status: String = "aktiv", phase: CampPhase = .loaded, task: CampTask? = nil,
                             error: String? = nil, inputError: String? = nil, waiting: Int = 0) -> some View {
        let active = active(role: role, status: status, waiting: waiting)
        let model = CampTaskDetailModel(active: active, personId: personId, taskId: Self.tasks[0].id)
        model.now = { today }
        model.setPreview(phase: phase, task: task ?? Self.tasks[0], details: details, error: error, inputError: inputError)
        return NavigationStack { CampTaskDetailView(model: model) }.environment(active)
    }
}
#endif
