import Foundation
import Testing
@testable import CeviOS

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder.api.decode(T.self, from: Data(json.utf8))
}

private let uuid1 = "0190a000-0000-7000-8000-000000000001"
private let uuid2 = "0190a000-0000-7000-8000-000000000002"
private let personJSON = #"{"id":"\#(uuid2)","name":"Pat Muster","ceviName":"Pinguin"}"#
private let taskJSON = """
{"id":"\(uuid1)","version":3,"titel":"Zelte prüfen","ressortId":"\(uuid2)","teil":null,"verantwortlichPersonId":null,
 "status":"laeuft","notiz":null,"frist":"2027-06-01","fristMeilensteinId":null,"fristVersatzTage":null,"stern":true,
 "laufend":false,"spaeterAb":null,"wiederholung":"w1","reihenfolge":0,"quelle":null,"erledigtAm":null,
 "verantwortlich":{"id":"\(uuid2)","name":"Pat Muster","ceviName":null,"automatisch":true},
 "ressort":{"id":"\(uuid2)","kuerzel":"MAT","name":"Material"},"unterstuetzung":[\(personJSON)]}
"""
private let portfolioJSON = """
{"id":"\(uuid1)","version":2,"kuerzel":"MAT","name":"Material","leitungPersonId":"\(uuid2)","stvPersonId":null,"notiz":null,
 "parentId":null,"reihenfolge":1,"leitung":\(personJSON),"stv":null}
"""
private let milestoneJSON = #"{"id":"\#(uuid1)","version":1,"titel":"Anmeldeschluss","datum":"2027-03-01","art":null}"#
private let dayJSON = #"{"id":"\#(uuid1)","version":1,"datum":"2027-07-10","label":"Anreise"}"#
private let sectionJSON = #"{"id":"\#(uuid1)","version":1,"name":"Morgen","zeit":null,"reihenfolge":0}"#
private let checkJSON = #"{"id":"\#(uuid1)","version":1,"aufgabeId":"\#(uuid2)","text":"Pfosten","erledigt":false,"erledigtVonPersonId":null,"reihenfolge":0}"#
private let linkJSON = #"{"id":"\#(uuid1)","version":1,"aufgabeId":"\#(uuid2)","titel":"Plan","url":"https://example.org/plan"}"#
private let detailsJSON = #"{"aufgabeId":"\#(uuid2)","checkliste":[\#(checkJSON)],"links":[\#(linkJSON)],"stichworte":["zelt"]}"#

struct CampPlanningModelTests {
    @Test func portfolioIsDecodedWithPeople() throws {
        let portfolio = try decode(CampPortfolio.self, portfolioJSON)
        #expect(portfolio.code == "MAT" && portfolio.version == 2 && portfolio.parentId == nil)
        #expect(portfolio.leader?.ceviName == "Pinguin" && portfolio.deputy == nil)
        let page = try decode(CampPortfolioPage.self, #"{"ressorts":[\#(portfolioJSON)],"naechster":null}"#)
        #expect(page.portfolios.count == 1 && page.next == nil)
    }

    @Test func portfolioLinksAndNotesAreDecoded() throws {
        let link = try decode(CampPortfolioLinkPage.self, #"{"links":[{"id":"\#(uuid1)","version":1,"ressortId":"\#(uuid2)","titel":"A","url":"https://example.org"}],"naechster":"\#(uuid2)"}"#)
        #expect(link.links.first?.title == "A" && link.next != nil)
        let note = try decode(CampPortfolioNotePage.self, #"{"notizen":[{"id":"\#(uuid1)","version":1,"ressortId":"\#(uuid2)","text":"Hallo","vonPersonId":null,"erstelltAm":"2027-01-01T08:00:00Z"}],"naechster":null}"#)
        #expect(note.notes.first?.author == nil && note.notes.first?.text == "Hallo")
    }

    @Test func taskIsDecodedWithAllFields() throws {
        let task = try decode(CampTask.self, taskJSON)
        #expect(task.version == 3 && task.status == .running && task.repeatEvery == .weekly && task.starred)
        #expect(task.due != nil && task.completedAt == nil && task.responsible?.automatic == true)
        #expect(task.portfolio?.code == "MAT" && task.supporters.count == 1)
    }

    @Test func unknownTaskStatusIsRejected() {
        #expect(throws: DecodingError.self) { try decode(CampTask.self, taskJSON.replacing("\"laeuft\"", with: "\"kaputt\"")) }
    }

    @Test func detailsAndHistoryAreDecoded() throws {
        let details = try decode(CampTaskDetails.self, detailsJSON)
        #expect(details.checklist.first?.text == "Pfosten" && details.links.count == 1 && details.keywords == ["zelt"])
        let history = try decode(CampTaskHistory.self, """
        {"aufgabeId":"\(uuid1)","erstelltAm":"2027-01-01T08:00:00Z","erstelltVon":\(personJSON),"geaendertAm":"2027-01-02T08:00:00Z",
         "geaendertVon":null,"eintraege":[{"seq":4,"objekttyp":"aufgabe_checkpunkt","id":"\(uuid2)","art":"neu","version":1,"zeitpunkt":"2027-01-02T08:00:00Z"}],
         "naechster":3}
        """)
        #expect(history.entries.first?.kind == .new && history.next == 3 && history.changedBy == nil)
    }

    @Test func duplicatesAreDecoded() throws {
        let result = try decode(CampTaskDuplicates.self, #"{"gruppen":[{"ressortId":null,"titel":"Zelte","aufgaben":[{"id":"\#(uuid1)","version":1,"titel":"Zelte","status":"offen"}]}]}"#)
        #expect(result.groups.first?.tasks.count == 1 && result.groups.first?.portfolioId == nil)
    }

    private let suggestionJSON = """
    {"vorschlaege":[{"zeile":"Zelte prüfen @Pinguin #MAT bis 1.6.","titel":"Zelte prüfen",
      "person":{"status":"gefunden","text":"Pinguin","kandidaten":[\(personJSON)]},
      "ressort":{"status":"mehrdeutig","text":"M","kandidaten":[{"id":"\(uuid1)","kuerzel":"MAT","name":"Material"},{"id":"\(uuid2)","kuerzel":"MUS","name":"Musik"}]},
      "frist":{"datum":"2027-06-01","text":"1.6."},"hinweise":["etwas_neues"]}]}
    """

    @Test func suggestionIsDecodedAndTolerantToNewHints() throws {
        let suggestion = try #require(try decode(CampTaskSuggestions.self, suggestionJSON).suggestions.first)
        #expect(suggestion.person?.status == .found && suggestion.portfolio?.status == .ambiguous)
        #expect(suggestion.hints == [.unknown])
    }

    @Test func confirmingTakesOnlyClearMatches() throws {
        let suggestion = try #require(try decode(CampTaskSuggestions.self, suggestionJSON).suggestions.first)
        let body = CampTaskCreate(confirming: suggestion)
        #expect(body.responsibleId?.uuidString.lowercased() == uuid2)
        #expect(body.portfolioId == nil) // ambiguous: the person picks
        #expect(CampTaskCreate(confirming: suggestion, portfolio: UUID(uuidString: uuid1)).portfolioId?.uuidString.lowercased() == uuid1)
        let json = try #require(String(data: JSONEncoder.api.encode(body), encoding: .utf8))
        #expect(json.contains(#""frist":"2027-06-01""#) && json.contains(#""titel":"Zelte prüfen""#))
    }

    @Test func scheduleIsDecoded() throws {
        let schedule = try decode(CampSchedule.self, #"{"meilensteine":[\#(milestoneJSON)],"lagertage":[\#(dayJSON)],"tagesabschnitte":[\#(sectionJSON)]}"#)
        #expect(schedule.milestones.first?.title == "Anmeldeschluss" && schedule.campDays.first?.label == "Anreise")
        #expect(schedule.sections.first?.time == nil)
        let proposal = try decode(CampScheduleProposal.self, #"{"lagertage":[{"datum":"2027-07-10","label":null}],"tagesabschnitte":[{"name":"Morgen","zeit":null,"reihenfolge":0}]}"#)
        #expect(proposal.campDays.count == 1 && proposal.sections.first?.name == "Morgen")
    }

    @Test func milestoneMoveIsDecodedAndGivesTaskRefs() throws {
        let move = try decode(CampMilestoneMove.self, """
        {"trocken":true,"meilenstein":{"id":"\(uuid1)","version":1,"datumAlt":"2027-03-01","datumNeu":"2027-03-08"},
         "aufgaben":[{"id":"\(uuid2)","version":4,"titel":"Flyer","status":"offen","fristAlt":"2027-03-01","fristNeu":"2027-03-08"}]}
        """)
        #expect(move.dryRun && move.milestone.newDate > move.milestone.oldDate)
        #expect(move.taskRefs == [CampVersionRef(id: UUID(uuidString: uuid2)!, version: 4)])
    }

    @Test func todoStartDecisionAndTemplateAreDecoded() throws {
        let todos = try decode(CampTodoList.self, #"{"todos":[{"id":"\#(uuid1)","text":"Einkaufen","erledigt":false,"reihenfolge":0}]}"#)
        #expect(todos.todos.first?.text == "Einkaufen")
        let decisions = try decode(CampDecisionPage.self, #"{"entscheide":[{"id":"\#(uuid1)","titel":"Ort","entscheid":"Wald","aufgabeId":null,"hoeck":{"id":"\#(uuid2)","datum":"2027-02-01","titel":"Höck 1"}}],"naechster":null}"#)
        #expect(decisions.decisions.first?.meeting.title == "Höck 1")
        let tasks = try decode(CampTemplateApplication.self, #"{"trocken":true,"art":"aufgaben","aufgaben":[{"titel":"A","frist":null}]}"#)
        #expect(tasks.kind == .tasks && tasks.items == nil && tasks.tasks?.count == 1)
        let packing = try decode(CampTemplateApplication.self, #"{"trocken":false,"art":"packliste","punkte":[{"abschnitt":"Kleider","text":"Socken","nurLagerleitung":false}]}"#)
        #expect(packing.kind == .packingList && packing.items?.first?.section == "Kleider")
    }

    @Test func startIsDecodedAndMayLackTaskProgress() throws {
        let start = try decode(CampStart.self, """
        {"heute":"2027-05-01","countdown":{"von":"2027-07-10","bis":"2027-07-17","tageBisBeginn":70,"tageBisEnde":77},
         "fortschritt":{"aufgaben":null,"meilensteine":{"gesamt":3,"vergangen":1,"naechster":\(milestoneJSON)}},"ueberfaellig":null}
        """)
        #expect(start.countdown.daysUntilStart == 70 && start.progress.tasks == nil && start.overdue == nil)
        #expect(start.progress.milestones?.next?.title == "Anmeldeschluss")
        let full = try decode(CampStart.self, """
        {"heute":"2027-05-01","countdown":{"von":"2027-07-10","bis":"2027-07-17","tageBisBeginn":70,"tageBisEnde":77},
         "fortschritt":{"aufgaben":{"gesamt":10,"erledigt":4,"ueberfaellig":1},"meilensteine":null},"ueberfaellig":[\(taskJSON)]}
        """)
        #expect(full.progress.tasks?.done == 4 && full.overdue?.count == 1)
    }
}

struct CampPlanningBodyTests {
    private func json(_ value: some Encodable) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder.api.encode(value)) as? [String: Any])
    }

    @Test func patchSendsOnlySetFieldsAndNullToClear() throws {
        let body = try json(CampTaskPatch(version: 2, title: "Neu", note: .clear, due: .set(CampCalendarDay(DateFormats.calendarDay("2027-06-01")!))))
        #expect(Set(body.keys) == ["version", "titel", "notiz", "frist"])
        #expect(body["notiz"] is NSNull)
        #expect(body["frist"] as? String == "2027-06-01")
        #expect(body["version"] as? Int == 2)
    }

    @Test func createLeavesUnsetFieldsOut() throws {
        let body = try json(CampPortfolioCreate(code: "MAT", name: "Material"))
        #expect(Set(body.keys) == ["kuerzel", "name"])
    }

    @Test func orderBodyIsListOfIdsAndVersions() throws {
        let body = try json(CampOrderBody(entries: [CampVersionRef(id: UUID(), version: 2)]))
        #expect((body["eintraege"] as? [[String: Any]])?.first?["version"] as? Int == 2)
    }

    @Test func filterBuildsTheQuery() {
        let id = UUID()
        let items = CampTaskFilter(portfolioId: id, status: .waiting, overdue: true, keyword: "zelt").queryItems
        #expect(items.contains(URLQueryItem(name: "ressortId", value: id.uuidString.lowercased())))
        #expect(items.contains(URLQueryItem(name: "status", value: "wartet")))
        #expect(items.contains(URLQueryItem(name: "ueberfaellig", value: "true")))
        #expect(items.contains(URLQueryItem(name: "stichwort", value: "zelt")) && items.count == 4)
    }
}

struct CampConflictTests {
    private let conflict = APIError.from(status: 409, data: Data("""
    {"code":"VERSION_KONFLIKT","message":"Zwischenzeitlich geändert.","aktuell":\(taskJSON),"abweichend":["titel","status"]}
    """.utf8))

    @Test func versionConflictCarriesCurrentRowAndFields() throws {
        let result = try #require(CampRules.versionConflict(conflict, as: CampTask.self))
        #expect(result.current?.version == 3 && result.differing == ["titel", "status"])
    }

    @Test func conflictWithUnknownRowShapeKeepsMessageAndFields() throws {
        let error = APIError.from(status: 409, data: Data(#"{"code":"VERSION_KONFLIKT","message":"x","aktuell":{"a":1},"abweichend":["a"]}"#.utf8))
        let result = try #require(CampRules.versionConflict(error, as: CampTask.self))
        #expect(result.current == nil && result.differing == ["a"])
    }

    @Test func otherErrorsAreNoVersionConflict() {
        let closed = APIError.from(status: 409, data: Data(#"{"code":"LAGER_GESCHLOSSEN","message":"x"}"#.utf8))
        #expect(CampRules.versionConflict(closed, as: CampTask.self) == nil)
        #expect(CampRules.versionConflict(APIError.network, as: CampTask.self) == nil)
    }
}

struct CampPlanningServiceTests {
    private let camp = UUID(), id = UUID(), other = UUID()
    private var campPath: String { "/api/v1/lager/\(camp.uuidString.lowercased())" }
    private var idText: String { id.uuidString.lowercased() }

    /// Runs `call` against a stub answering `status` with `json`; returns the request the app sent.
    private func sent(
        status: Int = 200, _ json: String = "{}", _ call: (APIClient) async throws -> Void
    ) async throws -> (method: String, path: String, query: [String: String], body: [String: Any]?) {
        let host = "a\(UUID().uuidString.prefix(8).lowercased()).test.example.org"
        StubProtocol.register(host: host) { _ in (status, [:], Data(json.utf8)) }
        let client = APIClient(
            baseURL: URL(string: "https://\(host)")!, appVersion: "1.0.0", cookieStore: InMemoryCookieStore(["s": "1"]),
            session: APIClient.makeSession(protocolClasses: [StubProtocol.self])
        )
        try await call(client)
        let request = try #require(StubProtocol.requests(host: host).first)
        let url = try #require(request.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let body = StubProtocol.body(of: request).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        return (request.httpMethod ?? "GET", url.path, Dictionary(items.map { ($0.name, $0.value ?? "") }) { $1 }, body)
    }

    @Test func portfolioRoutes() async throws {
        var r = try await sent(#"{"ressorts":[],"naechster":null}"#) { _ = try await $0.campPortfolios(campId: camp, after: other, limit: 10) }
        #expect(r.method == "GET" && r.path == campPath + "/ressorts" && r.query["limit"] == "10" && r.query["nach"] == other.uuidString.lowercased())
        r = try await sent(portfolioJSON) { _ = try await $0.campPortfolio(campId: camp, portfolioId: id) }
        #expect(r.method == "GET" && r.path == campPath + "/ressorts/" + idText)
        r = try await sent(status: 201, portfolioJSON) { _ = try await $0.createCampPortfolio(campId: camp, CampPortfolioCreate(code: "MAT", name: "Material")) }
        #expect(r.method == "POST" && r.path == campPath + "/ressorts" && r.body?["kuerzel"] as? String == "MAT")
        r = try await sent(portfolioJSON) { _ = try await $0.updateCampPortfolio(campId: camp, portfolioId: id, CampPortfolioPatch(version: 2, leaderId: .clear)) }
        #expect(r.method == "PATCH" && r.body?["leitungPersonId"] is NSNull && r.body?["version"] as? Int == 2)
        r = try await sent(status: 204, "") { try await $0.deleteCampPortfolio(campId: camp, portfolioId: id, version: 5) }
        #expect(r.method == "DELETE" && r.path == campPath + "/ressorts/" + idText && r.query["version"] == "5")
        r = try await sent(status: 204, "") { try await $0.reorderCampPortfolios(campId: camp, [CampVersionRef(id: id, version: 1)]) }
        #expect(r.method == "PUT" && r.path == campPath + "/ressorts/reihenfolge" && (r.body?["eintraege"] as? [Any])?.count == 1)
    }

    @Test func portfolioLinkAndNoteRoutes() async throws {
        let base = campPath + "/ressorts/" + idText
        var r = try await sent(#"{"links":[],"naechster":null}"#) { _ = try await $0.campPortfolioLinks(campId: camp, portfolioId: id) }
        #expect(r.method == "GET" && r.path == base + "/links")
        r = try await sent(status: 201, #"{"id":"\#(uuid1)","version":1,"ressortId":"\#(uuid2)","titel":"A","url":"https://example.org"}"#) {
            _ = try await $0.createCampPortfolioLink(campId: camp, portfolioId: id, CampLinkCreate(title: "A", url: "https://example.org"))
        }
        #expect(r.method == "POST" && r.path == base + "/links" && r.body?["titel"] as? String == "A")
        r = try await sent(#"{"id":"\#(uuid1)","version":2,"ressortId":"\#(uuid2)","titel":"B","url":"https://example.org"}"#) {
            _ = try await $0.updateCampPortfolioLink(campId: camp, portfolioId: id, linkId: other, CampLinkPatch(version: 1, title: "B"))
        }
        #expect(r.method == "PATCH" && r.path == base + "/links/" + other.uuidString.lowercased())
        r = try await sent(status: 204, "") { try await $0.deleteCampPortfolioLink(campId: camp, portfolioId: id, linkId: other, version: 2) }
        #expect(r.method == "DELETE" && r.query["version"] == "2")
        let note = #"{"id":"\#(uuid1)","version":1,"ressortId":"\#(uuid2)","text":"T","vonPersonId":null,"erstelltAm":"2027-01-01T08:00:00Z"}"#
        r = try await sent(#"{"notizen":[],"naechster":null}"#) { _ = try await $0.campPortfolioNotes(campId: camp, portfolioId: id) }
        #expect(r.method == "GET" && r.path == base + "/notizen" && r.query["limit"] == "50")
        r = try await sent(status: 201, note) { _ = try await $0.createCampPortfolioNote(campId: camp, portfolioId: id, text: "T") }
        #expect(r.method == "POST" && r.body?["text"] as? String == "T")
        r = try await sent(note) { _ = try await $0.updateCampPortfolioNote(campId: camp, portfolioId: id, noteId: other, version: 1, text: "U") }
        #expect(r.method == "PATCH" && r.path == base + "/notizen/" + other.uuidString.lowercased() && r.body?["text"] as? String == "U")
        r = try await sent(status: 204, "") { try await $0.deleteCampPortfolioNote(campId: camp, portfolioId: id, noteId: other, version: 3) }
        #expect(r.method == "DELETE" && r.query["version"] == "3")
    }

    @Test func taskReadRoutes() async throws {
        let filter = CampTaskFilter(status: .open, starred: true)
        var r = try await sent(#"{"aufgaben":[\#(taskJSON)],"naechster":null}"#) { _ = try await $0.campTasks(campId: camp, filter: filter, limit: 20) }
        #expect(r.method == "GET" && r.path == campPath + "/aufgaben" && r.query["status"] == "offen" && r.query["stern"] == "true" && r.query["limit"] == "20")
        r = try await sent(taskJSON) { _ = try await $0.campTask(campId: camp, taskId: id) }
        #expect(r.method == "GET" && r.path == campPath + "/aufgaben/" + idText)
        r = try await sent(#"{"gruppen":[]}"#) { _ = try await $0.campTaskDuplicates(campId: camp, title: "Zelte", portfolioId: other) }
        #expect(r.path == campPath + "/aufgaben/duplikate" && r.query["titel"] == "Zelte" && r.query["ressortId"] == other.uuidString.lowercased())
        r = try await sent(detailsJSON) { _ = try await $0.campTaskDetails(campId: camp, taskId: id) }
        #expect(r.path == campPath + "/aufgaben/" + idText + "/details")
        r = try await sent("""
        {"aufgabeId":"\(uuid1)","erstelltAm":"2027-01-01T08:00:00Z","erstelltVon":null,"geaendertAm":"2027-01-01T08:00:00Z","geaendertVon":null,"eintraege":[],"naechster":null}
        """) { _ = try await $0.campTaskHistory(campId: camp, taskId: id, before: 9) }
        #expect(r.path == campPath + "/aufgaben/" + idText + "/verlauf" && r.query["vor"] == "9" && r.query["limit"] == "50")
    }

    @Test func taskWriteRoutes() async throws {
        var r = try await sent(status: 201, taskJSON) { _ = try await $0.createCampTask(campId: camp, CampTaskCreate(title: "Zelte")) }
        #expect(r.method == "POST" && r.path == campPath + "/aufgaben" && r.body?["titel"] as? String == "Zelte")
        r = try await sent(taskJSON) { _ = try await $0.updateCampTask(campId: camp, taskId: id, CampTaskPatch(version: 3, starred: false)) }
        #expect(r.method == "PATCH" && r.body?["stern"] as? Bool == false)
        r = try await sent(status: 204, "") { try await $0.deleteCampTask(campId: camp, taskId: id, version: 3) }
        #expect(r.method == "DELETE" && r.query["version"] == "3")
        r = try await sent(status: 204, "") { try await $0.reorderCampTasks(campId: camp, [CampVersionRef(id: id, version: 1)]) }
        #expect(r.method == "PUT" && r.path == campPath + "/aufgaben/reihenfolge")
        r = try await sent(taskJSON) { _ = try await $0.setCampTaskStatus(campId: camp, taskId: id, version: 3, status: .done) }
        #expect(r.method == "PUT" && r.path == campPath + "/aufgaben/" + idText + "/status" && r.body?["status"] as? String == "erledigt")
        r = try await sent(taskJSON) { _ = try await $0.mergeCampTasks(campId: camp, taskId: id, version: 3, withId: other, withVersion: 2) }
        #expect(r.method == "POST" && r.path == campPath + "/aufgaben/" + idText + "/zusammenfuehren")
        #expect((r.body?["mitId"] as? String)?.lowercased() == other.uuidString.lowercased() && r.body?["mitVersion"] as? Int == 2)
    }

    @Test func checklistLinkAndKeywordRoutes() async throws {
        let base = campPath + "/aufgaben/" + idText
        var r = try await sent(status: 201, checkJSON) { _ = try await $0.createCampChecklistItem(campId: camp, taskId: id, CampChecklistCreate(text: "Pfosten")) }
        #expect(r.method == "POST" && r.path == base + "/checkliste")
        r = try await sent(checkJSON) { _ = try await $0.updateCampChecklistItem(campId: camp, taskId: id, itemId: other, CampChecklistPatch(version: 1, done: true)) }
        #expect(r.method == "PATCH" && r.path == base + "/checkliste/" + other.uuidString.lowercased() && r.body?["erledigt"] as? Bool == true)
        r = try await sent(status: 204, "") { try await $0.deleteCampChecklistItem(campId: camp, taskId: id, itemId: other, version: 1) }
        #expect(r.method == "DELETE" && r.query["version"] == "1")
        r = try await sent(status: 204, "") { try await $0.reorderCampChecklist(campId: camp, taskId: id, [CampVersionRef(id: other, version: 1)]) }
        #expect(r.method == "PUT" && r.path == base + "/checkliste/reihenfolge")
        r = try await sent(status: 201, linkJSON) { _ = try await $0.createCampTaskLink(campId: camp, taskId: id, CampLinkCreate(title: "Plan", url: "https://example.org/plan")) }
        #expect(r.method == "POST" && r.path == base + "/links")
        r = try await sent(linkJSON) { _ = try await $0.updateCampTaskLink(campId: camp, taskId: id, linkId: other, CampLinkPatch(version: 1, url: "https://example.org/x")) }
        #expect(r.method == "PATCH" && r.path == base + "/links/" + other.uuidString.lowercased())
        r = try await sent(status: 204, "") { try await $0.deleteCampTaskLink(campId: camp, taskId: id, linkId: other, version: 1) }
        #expect(r.method == "DELETE" && r.path == base + "/links/" + other.uuidString.lowercased())
        r = try await sent(detailsJSON) { _ = try await $0.setCampTaskKeywords(campId: camp, taskId: id, version: 3, keywords: ["zelt"]) }
        #expect(r.method == "PUT" && r.path == base + "/stichworte" && (r.body?["stichworte"] as? [String]) == ["zelt"])
    }

    @Test func quickEntrySendsTextAndReturnsSuggestionsWithoutSaving() async throws {
        let host = "a\(UUID().uuidString.prefix(8).lowercased()).test.example.org"
        StubProtocol.register(host: host) { _ in
            (200, [:], Data(#"{"vorschlaege":[{"zeile":"Zelte","titel":"Zelte","person":null,"ressort":null,"frist":null,"hinweise":[]}]}"#.utf8))
        }
        let client = APIClient(
            baseURL: URL(string: "https://\(host)")!, appVersion: "1.0.0", cookieStore: InMemoryCookieStore(["s": "1"]),
            session: APIClient.makeSession(protocolClasses: [StubProtocol.self])
        )
        let suggestions = try await client.suggestCampTasks(campId: camp, text: "Zelte")
        #expect(suggestions.first?.title == "Zelte")
        let requests = StubProtocol.requests(host: host)
        #expect(requests.count == 1 && requests.first?.httpMethod == "POST" && requests.first?.url?.path == campPath + "/aufgaben/schnell")
    }

    @Test func scheduleRoutes() async throws {
        let base = campPath + "/zeitplan"
        var r = try await sent(#"{"meilensteine":[],"lagertage":[],"tagesabschnitte":[]}"#) { _ = try await $0.campSchedule(campId: camp) }
        #expect(r.method == "GET" && r.path == base)
        r = try await sent(#"{"lagertage":[],"tagesabschnitte":[]}"#) { _ = try await $0.campScheduleProposal(campId: camp) }
        #expect(r.method == "GET" && r.path == base + "/vorschlag")
        let day = CampCalendarDay(DateFormats.calendarDay("2027-07-10")!)
        r = try await sent(status: 201, #"{"lagertage":[],"tagesabschnitte":[]}"#) {
            _ = try await $0.adoptCampSchedule(campId: camp, CampScheduleAdopt(campDays: [.init(date: day)], sections: [.init(name: "Morgen")]))
        }
        #expect(r.method == "POST" && r.path == base + "/uebernehmen" && (r.body?["lagertage"] as? [[String: Any]])?.first?["datum"] as? String == "2027-07-10")
        r = try await sent(status: 201, milestoneJSON) { _ = try await $0.createCampMilestone(campId: camp, CampMilestoneCreate(title: "Anmeldeschluss", date: day)) }
        #expect(r.method == "POST" && r.path == base + "/meilensteine" && r.body?["datum"] as? String == "2027-07-10")
        r = try await sent(milestoneJSON) { _ = try await $0.updateCampMilestone(campId: camp, milestoneId: id, CampMilestonePatch(version: 1, kind: .clear)) }
        #expect(r.method == "PATCH" && r.path == base + "/meilensteine/" + idText && r.body?["art"] is NSNull)
        r = try await sent(status: 204, "") { try await $0.deleteCampMilestone(campId: camp, milestoneId: id, version: 1) }
        #expect(r.method == "DELETE" && r.query["version"] == "1")
        r = try await sent(status: 201, dayJSON) { _ = try await $0.createCampDay(campId: camp, CampDayCreate(date: day, label: "Anreise")) }
        #expect(r.method == "POST" && r.path == base + "/lagertage")
        r = try await sent(dayJSON) { _ = try await $0.updateCampDay(campId: camp, dayId: id, CampDayPatch(version: 1, label: .set("Start"))) }
        #expect(r.method == "PATCH" && r.path == base + "/lagertage/" + idText && r.body?["label"] as? String == "Start")
        r = try await sent(status: 204, "") { try await $0.deleteCampDay(campId: camp, dayId: id, version: 1) }
        #expect(r.method == "DELETE" && r.path == base + "/lagertage/" + idText)
        r = try await sent(status: 201, sectionJSON) { _ = try await $0.createCampDaySection(campId: camp, CampSectionCreate(name: "Morgen")) }
        #expect(r.method == "POST" && r.path == base + "/tagesabschnitte")
        r = try await sent(sectionJSON) { _ = try await $0.updateCampDaySection(campId: camp, sectionId: id, CampSectionPatch(version: 1, time: .clear)) }
        #expect(r.method == "PATCH" && r.path == base + "/tagesabschnitte/" + idText && r.body?["zeit"] is NSNull)
        r = try await sent(status: 204, "") { try await $0.deleteCampDaySection(campId: camp, sectionId: id, version: 1) }
        #expect(r.method == "DELETE" && r.path == base + "/tagesabschnitte/" + idText)
    }

    @Test func milestoneMovePreviewThenConfirmation() async throws {
        let answer = """
        {"trocken":true,"meilenstein":{"id":"\(uuid1)","version":1,"datumAlt":"2027-03-01","datumNeu":"2027-03-08"},"aufgaben":[]}
        """
        let date = DateFormats.calendarDay("2027-03-08")!
        var r = try await sent(answer) { _ = try await $0.previewCampMilestoneMove(campId: camp, milestoneId: id, version: 1, to: date) }
        #expect(r.method == "POST" && r.path == campPath + "/zeitplan/meilensteine/" + idText + "/verschieben")
        #expect(r.body?["trocken"] as? Bool == true && r.body?["datum"] as? String == "2027-03-08" && r.body?["aufgaben"] == nil)
        r = try await sent(answer.replacing("true", with: "false")) {
            _ = try await $0.confirmCampMilestoneMove(campId: camp, milestoneId: id, version: 1, to: date, tasks: [CampVersionRef(id: other, version: 4)])
        }
        #expect(r.body?["trocken"] as? Bool == false && (r.body?["aufgaben"] as? [[String: Any]])?.first?["version"] as? Int == 4)
    }

    @Test func todoRoutes() async throws {
        let todo = #"{"id":"\#(uuid1)","text":"Einkaufen","erledigt":false,"reihenfolge":0}"#
        var r = try await sent(#"{"todos":[\#(todo)]}"#) { _ = try await $0.campTodos(campId: camp) }
        #expect(r.method == "GET" && r.path == campPath + "/todos")
        r = try await sent(status: 201, todo) { _ = try await $0.createCampTodo(campId: camp, CampTodoCreate(text: "Einkaufen")) }
        #expect(r.method == "POST" && r.body?["text"] as? String == "Einkaufen")
        r = try await sent(todo) { _ = try await $0.updateCampTodo(campId: camp, todoId: id, CampTodoPatch(done: true)) }
        #expect(r.method == "PATCH" && r.path == campPath + "/todos/" + idText && r.body?["erledigt"] as? Bool == true && r.body?.count == 1)
        r = try await sent(status: 204, "") { try await $0.deleteCampTodo(campId: camp, todoId: id) }
        #expect(r.method == "DELETE" && r.path == campPath + "/todos/" + idText && r.query.isEmpty)
    }

    @Test func templateStartAndDecisionRoutes() async throws {
        let dry = #"{"trocken":true,"art":"aufgaben","aufgaben":[]}"#
        var r = try await sent(dry) { _ = try await $0.applyCampTemplate(campId: camp, templateId: id, dryRun: true) }
        #expect(r.method == "POST" && r.path == campPath + "/vorlagen/" + idText + "/anwenden" && r.query["trocken"] == "true")
        r = try await sent(status: 201, dry) { _ = try await $0.applyCampTemplate(campId: camp, templateId: id) }
        #expect(r.query.isEmpty)
        r = try await sent("""
        {"heute":"2027-05-01","countdown":{"von":"2027-07-10","bis":"2027-07-17","tageBisBeginn":70,"tageBisEnde":77},
         "fortschritt":{"aufgaben":null,"meilensteine":null},"ueberfaellig":null}
        """) { _ = try await $0.campStart(campId: camp) }
        #expect(r.method == "GET" && r.path == campPath + "/start")
        r = try await sent(#"{"entscheide":[],"naechster":null}"#) { _ = try await $0.campDecisions(campId: camp, after: other) }
        #expect(r.path == campPath + "/entscheide" && r.query["nach"] == other.uuidString.lowercased())
    }

    @Test func versionConflictSurfacesAsApiErrorWithBody() async throws {
        let conflict = """
        {"code":"VERSION_KONFLIKT","message":"Geändert.","aktuell":\(taskJSON),"abweichend":["titel"]}
        """
        do {
            _ = try await sent(status: 409, conflict) { _ = try await $0.updateCampTask(campId: camp, taskId: id, CampTaskPatch(version: 1, title: "X")) }
            Issue.record("expected a conflict")
        } catch let error as APIError {
            #expect(error.kind == .conflict)
            #expect(CampRules.versionConflict(error, as: CampTask.self)?.differing == ["titel"])
        }
    }
}
