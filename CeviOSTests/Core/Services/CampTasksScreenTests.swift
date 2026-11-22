import Foundation
import Testing
@testable import CeviOS

private nonisolated let campId = UUID(uuidString: "0190a000-0000-7000-8000-000000000001")!
private nonisolated let me = UUID(uuidString: "0190a000-0000-7000-8000-0000000000aa")!
private nonisolated let portfolio = "0190a000-0000-7000-8000-0000000000b1"

private nonisolated func taskJSON(_ n: Int, version: Int = 1, status: String = "offen", due: String? = "2027-03-20", responsible: UUID? = nil, title: String? = nil) -> String {
    """
    {"id":"0190a000-0000-7000-8000-0000000001\(String(format: "%02d", n))","version":\(version),"titel":"\(title ?? "Aufgabe \(n)")","ressortId":"\(portfolio)","teil":null,
     "verantwortlichPersonId":\(responsible.map { "\"\($0)\"" } ?? "null"),"status":"\(status)","notiz":null,"frist":\(due.map { "\"\($0)\"" } ?? "null"),
     "fristMeilensteinId":null,"fristVersatzTage":null,"stern":false,"laufend":false,"spaeterAb":null,"wiederholung":null,"reihenfolge":\(n),"quelle":null,
     "erledigtAm":null,"verantwortlich":null,"ressort":{"id":"\(portfolio)","kuerzel":"LO","name":"Logistik"},"unterstuetzung":[]}
    """
}

private func task(_ n: Int, version: Int = 1, status: String = "offen", due: String? = "2027-03-20", responsible: UUID? = nil) throws -> CampTask {
    try JSONDecoder.api.decode(CampTask.self, from: Data(taskJSON(n, version: version, status: status, due: due, responsible: responsible).utf8))
}

private nonisolated let today = DateFormats.calendarDay("2027-03-17")!

private nonisolated func apiError(_ status: Int, _ code: String? = nil, extra: String = "") -> Data {
    Data(#"{"code":"\#(code ?? "X")","message":"Text"\#(extra)}"#.utf8)
}

@MainActor
private func makeActive(role: CampRole = .campLeader, status: String = "aktiv", host: String) throws -> ActiveCamp {
    let json = """
    {"id":"\(campId.uuidString)","titel":"Sommerlager","von":"2027-07-17","bis":"2027-07-24","vorbereitungAb":null,"ort":null,
     "adresse":null,"status":"\(status)","farbe":null,"logoMediumId":null}
    """
    let client = APIClient(baseURL: URL(string: "https://\(host)")!, appVersion: "1.0.0", cookieStore: InMemoryCookieStore(["s": "1"]),
                           session: APIClient.makeSession(protocolClasses: [StubProtocol.self]))
    let active = ActiveCamp()
    active.open(camp: try JSONDecoder.api.decode(Camp.self, from: Data(json.utf8)), role: role, client: client)
    return active
}

private func newHost() -> String { "a\(UUID().uuidString.prefix(8).lowercased()).test.example.org" }

struct CampTaskRulesTests {
    @Test func rolesGetTheirActions() throws {
        let own = try task(1, responsible: me), other = try task(2)
        let lead = CampTaskRights(role: .campLeader, readOnly: false, personId: me)
        let leader = CampTaskRights(role: .leader, readOnly: false, personId: me)
        let team = CampTaskRights(role: .team, readOnly: false, personId: me)
        let reader = CampTaskRights(role: .readOnly, readOnly: false, personId: me)
        #expect(lead.canCreate && lead.canDelete && lead.canMerge && lead.seesTaskList)
        #expect(leader.canEdit && !leader.canDelete && leader.seesTaskList)
        #expect(!team.canEdit && team.canSetStatus(own) && !team.canSetStatus(other) && !team.seesTaskList)
        #expect(!reader.canSetStatus(own) && !reader.canCreate)
    }

    @Test func closedCampTakesEveryAction() throws {
        let closed = CampTaskRights(role: .campLeader, readOnly: true, personId: me)
        let one = try task(1)
        #expect(!closed.canCreate && !closed.canEdit && !closed.canDelete && !closed.canSetStatus(one))
    }

    @Test func dueHintsCountDays() throws {
        func hint(_ due: String, status: String = "offen") throws -> (text: String, isOverdue: Bool)? {
            CampTaskText.dueHint(try task(1, status: status, due: due), today: today)
        }
        #expect(try hint("2027-03-15")?.text == "Überfällig seit 2 Tagen")
        #expect(try hint("2027-03-15")?.isOverdue == true)
        #expect(try hint("2027-03-22")?.text == "Fällig in 5 Tagen")
        #expect(try hint("2027-03-17")?.text == "Heute fällig")
        #expect(try hint("2027-09-01") == nil)
        #expect(try hint("2027-03-01", status: "erledigt") == nil)
    }

    @Test func listGroupsByDeadlineAndEndsWithDone() throws {
        let tasks = [try task(1, due: "2027-03-15"), try task(2, due: "2027-03-22"), try task(3, due: "2027-06-01"), try task(4, due: nil), try task(5, status: "erledigt")]
        let sections = CampTaskText.sections(tasks, tab: .list, personId: me, filter: .init(), sort: .due, today: today)
        #expect(sections.map(\.id) == ["overdue", "soon", "later", "none", "done"])
        #expect(sections.last?.title == "Erledigt, 1 Aufgabe" && sections.last?.isDone == true)
    }

    @Test func mineKeepsOnlyOwnAndFilterNarrows() throws {
        let tasks = [try task(1, responsible: me), try task(2)]
        #expect(CampTaskText.sections(tasks, tab: .mine, personId: me, filter: .init(), sort: .due, today: today).flatMap(\.tasks).count == 1)
        var filter = CampTaskLocalFilter()
        filter.overdueOnly = true
        #expect(CampTaskText.sections(tasks, tab: .list, personId: me, filter: filter, sort: .due, today: today).isEmpty)
        #expect(filter.isActive)
    }

    @Test func scheduleBuildsWeeksAndMonthGrid() throws {
        let schedule = try JSONDecoder.api.decode(CampSchedule.self, from: Data(#"{"meilensteine":[{"id":"0190a000-0000-7000-8000-000000000601","version":1,"titel":"Gebucht","datum":"2027-03-19","art":null}],"lagertage":[],"tagesabschnitte":[]}"#.utf8))
        let items = CampScheduleBuilder.items(schedule: schedule, tasks: [try task(1, due: "2027-03-15"), try task(2, status: "erledigt", due: "2027-03-16")])
        #expect(items.map(\.kind) == [.deadline, .milestone])
        let weeks = CampScheduleBuilder.weeks(items)
        #expect(weeks.count == 1 && weeks[0].title.hasPrefix("Woche 11"))
        let grid = CampScheduleBuilder.monthGrid(for: DateFormats.calendarDay("2027-07-01")!)
        #expect(grid.allSatisfy { $0.count == 7 } && grid.flatMap { $0 }.compactMap { $0 }.count == 31)
        #expect(grid[0].firstIndex { $0 != nil } == 3) // 1 July 2027 is a Thursday
        #expect(CampScheduleBuilder.marks(on: DateFormats.calendarDay("2027-03-19")!, items: items, campDays: []) == [.milestone])
    }
}

@MainActor
struct CampTasksModelTests {
    private func stub(_ host: String, _ handler: @escaping @Sendable (URLRequest) -> (Int, Data)) {
        StubProtocol.register(host: host) { request in
            let (status, data) = handler(request)
            return (status, [:], data)
        }
    }

    private nonisolated static func listBody(_ items: [String]) -> Data { Data(#"{"aufgaben":[\#(items.joined(separator: ","))],"naechster":null}"#.utf8) }

    @Test func loadsTasksAndFailsWithTheirState() async throws {
        let ok = newHost(), denied = newHost(), offline = newHost()
        stub(ok) { request in
            request.url?.path.hasSuffix("/ressorts") == true ? (200, Data(#"{"ressorts":[],"naechster":null}"#.utf8)) : (200, Self.listBody([taskJSON(1), taskJSON(2)]))
        }
        stub(denied) { _ in (403, apiError(403)) }
        let model = CampTasksModel(active: try makeActive(host: ok), personId: me)
        await model.load()
        #expect(model.phase == .loaded && model.tasks.count == 2)
        let blocked = CampTasksModel(active: try makeActive(role: .team, host: denied), personId: me)
        await blocked.load()
        if case .failed(let state, _) = blocked.phase { #expect(state == .noAccess) } else { Issue.record("expected failure") }
        let gone = CampTasksModel(active: try makeActive(host: offline), personId: me)
        await gone.load()
        if case .failed(let state, _) = gone.phase { #expect(state == .offline) } else { Issue.record("expected failure") }
    }

    @Test func statusChangeSendsVersionAndOffersUndo() async throws {
        let host = newHost()
        stub(host) { request in
            if request.httpMethod == "PUT" { return (200, Data(taskJSON(1, version: 2, status: "erledigt").utf8)) }
            return (200, Self.listBody([taskJSON(1)]))
        }
        let model = CampTasksModel(active: try makeActive(host: host), personId: me)
        await model.load()
        await model.toggleDone(model.tasks[0])
        #expect(model.tasks[0].status == .done && model.notice?.title == "Aufgabe erledigt.")
        let put = StubProtocol.requests(host: host).first { $0.httpMethod == "PUT" }
        #expect(put?.url?.path.hasSuffix("/status") == true)
        let body = String(decoding: StubProtocol.body(of: try #require(put)) ?? Data(), as: UTF8.self)
        #expect(body.contains("\"version\":1") && body.contains("erledigt"))
        // Undo: sends the old status on the new version.
        await model.undo()
        let last = StubProtocol.requests(host: host).last { $0.httpMethod == "PUT" }
        #expect(String(decoding: StubProtocol.body(of: try #require(last)) ?? Data(), as: UTF8.self).contains("\"version\":2"))
    }

    @Test func readerAndClosedCampWriteNothing() async throws {
        let host = newHost()
        stub(host) { _ in (200, Self.listBody([taskJSON(1)])) }
        for (role, status) in [(CampRole.readOnly, "aktiv"), (.campLeader, "abgeschlossen")] {
            let model = CampTasksModel(active: try makeActive(role: role, status: status, host: host), personId: me)
            await model.load()
            await model.setStatus(model.tasks[0], to: .done)
            #expect(model.tasks[0].status == .open)
        }
        #expect(StubProtocol.requests(host: host).allSatisfy { $0.httpMethod == "GET" })
    }

    @Test func versionConflictOffersBothVersions() async throws {
        let host = newHost()
        stub(host) { request in
            if request.httpMethod == "PUT" {
                let body = #","aktuell":\#(taskJSON(1, version: 5, status: "wartet")),"abweichend":["status"]"#
                return (409, Data(#"{"code":"VERSION_KONFLIKT","message":"x"\#(body)}"#.utf8))
            }
            return (200, Self.listBody([taskJSON(1)]))
        }
        let model = CampTasksModel(active: try makeActive(host: host), personId: me)
        await model.load()
        await model.setStatus(model.tasks[0], to: .done)
        let conflict = try #require(model.conflict)
        #expect(conflict.current.version == 5)
        #expect(conflict.fields == [CampConflictField(label: "Status", mine: "Erledigt", current: "Wartet")])
        await model.resolveConflict(.keepCurrent)
        #expect(model.conflict == nil && model.tasks[0].status == .waiting)
    }

    @Test func closedCampAnswerShowsTheCalmText() async throws {
        let host = newHost()
        stub(host) { request in
            request.httpMethod == "PUT" ? (409, apiError(409, "LAGER_GESCHLOSSEN")) : (200, Self.listBody([taskJSON(1)]))
        }
        let model = CampTasksModel(active: try makeActive(host: host), personId: me)
        await model.load()
        await model.setStatus(model.tasks[0], to: .done)
        #expect(model.error == "Das Lager ist abgeschlossen. Es lässt sich nur noch lesen.")
    }

    @Test func noNetworkQueuesTheStatusChange() async throws {
        let host = newHost()
        // Loads work, then the host disappears: a request to an unknown host fails with a network error.
        stub(host) { _ in (200, Self.listBody([taskJSON(1)])) }
        let active = try makeActive(host: host)
        let model = CampTasksModel(active: active, personId: me)
        await model.load()
        StubProtocol.register(host: host) { _ in (0, [:], Data()) }
        let offlineHost = newHost()
        let offline = try makeActive(host: offlineHost)
        let offlineModel = CampTasksModel(active: offline, personId: me)
        offlineModel.setPreview(phase: .loaded, tasks: [try task(1)])
        await offlineModel.setStatus(offlineModel.tasks[0], to: .done)
        #expect(offline.waitingCount == 1 && offlineModel.queuedIds.count == 1 && offlineModel.tasks[0].status == .open)
        let entries = await offline.outbox?.all
        #expect(entries?.first?.operation.type == "aufgabe.aendern")
    }

    @Test func bulkStopsAtFailureAndKeepsSelection() async throws {
        let host = newHost()
        let count = Counter()
        stub(host) { request in
            if request.httpMethod == "PUT" {
                return count.next() == 1 ? (200, Data(taskJSON(1, version: 2, status: "erledigt").utf8)) : (500, apiError(500))
            }
            return (200, Self.listBody([taskJSON(1), taskJSON(2), taskJSON(3)]))
        }
        let model = CampTasksModel(active: try makeActive(host: host), personId: me)
        await model.load()
        model.startSelecting()
        model.selection = Set(model.tasks.map(\.id))
        await model.setStatusOfSelection(.done)
        #expect(model.isSelecting && model.selection.count == 3)
        #expect(model.error?.contains("Die 3 Aufgaben sind noch gewählt.") == true)
        #expect(model.tasks[0].status == .done)
    }

    @Test func deleteIsOnlyForTheCampLead() async throws {
        let host = newHost()
        stub(host) { request in request.httpMethod == "DELETE" ? (204, Data()) : (200, Self.listBody([taskJSON(1)])) }
        let leader = CampTasksModel(active: try makeActive(role: .leader, host: host), personId: me)
        await leader.load()
        leader.startSelecting(leader.tasks[0])
        await leader.deleteSelection()
        #expect(leader.tasks.count == 1)
        let lead = CampTasksModel(active: try makeActive(host: host), personId: me)
        await lead.load()
        lead.startSelecting(lead.tasks[0])
        await lead.deleteSelection()
        #expect(lead.tasks.isEmpty && !lead.isSelecting)
    }
}

private nonisolated final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int { lock.withLock { value += 1; return value } }
}

@MainActor
struct CampTaskScreensTests {
    private func stub(_ host: String, _ handler: @escaping @Sendable (URLRequest) -> (Int, Data)) {
        StubProtocol.register(host: host) { request in
            let (status, data) = handler(request)
            return (status, [:], data)
        }
    }


    @Test func detailLoadsChecklistAndExplainsReadOnly() async throws {
        let host = newHost()
        stub(host) { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/details") { return (200, Data(detailsJSON.utf8)) }
            if path.hasSuffix("/verlauf") { return (404, apiError(404)) }
            return (200, Data(taskJSON(1).utf8))
        }
        let taskId = try task(1).id
        let model = CampTaskDetailModel(active: try makeActive(host: host), personId: me, taskId: taskId)
        await model.load()
        #expect(model.phase == .loaded && model.checklistDone == 1 && model.checklist.count == 2 && model.history == nil)
        #expect(model.canEdit && model.readOnlyReason == nil)
        let reader = CampTaskDetailModel(active: try makeActive(role: .readOnly, host: host), personId: me, taskId: taskId)
        await reader.load()
        #expect(!reader.canEdit && !reader.canSetStatus)
        #expect(reader.readOnlyReason == "Diese Aufgabe gehört zum Ressort Logistik. Ändern kann sie die Ressortleitung.")
    }

    @Test func detailInputErrorIsKeptSeparately() async throws {
        let host = newHost()
        stub(host) { request in
            let path = request.url?.path ?? ""
            if request.httpMethod == "PATCH" { return (400, apiError(400)) }
            if path.hasSuffix("/details") { return (200, Data(detailsJSON.utf8)) }
            if path.hasSuffix("/verlauf") { return (404, apiError(404)) }
            return (200, Data(taskJSON(1).utf8))
        }
        let model = CampTaskDetailModel(active: try makeActive(host: host), personId: me, taskId: try task(1).id)
        await model.load()
        await model.setDue(DateFormats.calendarDay("2027-01-01"))
        #expect(model.inputError == "Text" && model.error == nil)
    }

    @Test func detailNotFoundLeadsToItsState() async throws {
        let host = newHost()
        stub(host) { _ in (404, apiError(404)) }
        let model = CampTaskDetailModel(active: try makeActive(host: host), personId: me, taskId: UUID())
        await model.load()
        if case .failed(let state, _) = model.phase { #expect(state == .notFound) } else { Issue.record("expected failure") }
    }


    @Test func quickEntryAppliesPersonButOnlyConfirmedPortfolio() async throws {
        let host = newHost()
        stub(host) { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/schnell") { return (200, Data(suggestionBody.utf8)) }
            if path.hasSuffix("/duplikate") { return (200, Data(#"{"gruppen":[]}"#.utf8)) }
            return (200, Data(taskJSON(1).utf8))
        }
        let model = CampQuickEntryModel(active: try makeActive(host: host))
        model.text = "Offerte @Jonas #Logistik"
        await model.suggest()
        #expect(model.suggestions.count == 1 && model.canSubmit)
        await model.submit()
        let post = StubProtocol.requests(host: host).last { $0.httpMethod == "POST" && $0.url?.path.hasSuffix("/aufgaben") == true }
        let body = String(decoding: StubProtocol.body(of: try #require(post)) ?? Data(), as: UTF8.self)
        #expect(body.contains("verantwortlichPersonId") && !body.contains("ressortId"))
        #expect(model.isDone && model.created.count == 1)
    }

    @Test func similarTaskStopsAndMergeCreatesThenMerges() async throws {
        let host = newHost()
        let existing = "0190a000-0000-7000-8000-000000000199"
        stub(host) { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/schnell") { return (200, Data(suggestionBody.utf8)) }
            if path.hasSuffix("/duplikate") { return (200, Data(#"{"gruppen":[{"ressortId":null,"titel":"Offerte","aufgaben":[{"id":"\#(existing)","version":4,"titel":"Offerte Lagerhaus","status":"offen"}]}]}"#.utf8)) }
            if path.hasSuffix("/zusammenfuehren") { return (200, Data(taskJSON(9, version: 5).utf8)) }
            return (200, Data(taskJSON(1).utf8))
        }
        let model = CampQuickEntryModel(active: try makeActive(host: host))
        model.text = "Offerte @Jonas #Logistik"
        await model.suggest()
        await model.submit()
        #expect(model.duplicate?.existing.title == "Offerte Lagerhaus" && !model.isDone)
        #expect(!StubProtocol.requests(host: host).contains { $0.httpMethod == "POST" && $0.url?.path.hasSuffix("/aufgaben") == true })
        await model.merge()
        let merge = StubProtocol.requests(host: host).first { $0.url?.path.hasSuffix("/zusammenfuehren") == true }
        #expect(merge?.url?.path.contains(existing) == true)
        #expect(model.isDone && model.duplicate == nil)
    }

    @Test func quickEntryBlocksLinesWithoutTitleAndExplainsUnknownPerson() async throws {
        let host = newHost()
        let body = #"{"vorschlaege":[{"zeile":"@Jona","titel":"","person":{"status":"unbekannt","text":"Jona","kandidaten":[{"id":"0190a000-0000-7000-8000-0000000000aa","name":"Jonas","ceviName":null}]},"ressort":null,"frist":null,"hinweise":["TITEL_FEHLT"]}]}"#
        stub(host) { _ in (200, Data(body.utf8)) }
        let model = CampQuickEntryModel(active: try makeActive(host: host))
        model.text = "@Jona"
        await model.suggest()
        #expect(model.blocked && !model.canSubmit)
        #expect(model.hint(for: model.suggestions[0]) == "Gib der Aufgabe einen Titel.")
        let reader = CampQuickEntryModel(active: try makeActive(role: .team, host: host))
        reader.text = "x"
        #expect(!reader.canCreate && !reader.canSubmit)
    }

    @Test func portfolioLoadsAndNotesAreWrittenByLeadsOnly() async throws {
        let host = newHost()
        let portfolioJSON = #"{"id":"\#(portfolio)","version":1,"kuerzel":"KÜ","name":"Küche","leitungPersonId":null,"stvPersonId":null,"notiz":null,"parentId":null,"reihenfolge":0,"leitung":null,"stv":null}"#
        stub(host) { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/notizen") {
                if request.httpMethod == "POST" { return (200, Data(#"{"id":"0190a000-0000-7000-8000-000000000501","version":1,"ressortId":"\#(portfolio)","text":"Hallo","vonPersonId":null,"erstelltAm":"2027-03-16T08:00:00Z"}"#.utf8)) }
                return (200, Data(#"{"notizen":[],"naechster":null}"#.utf8))
            }
            return (200, Data(portfolioJSON.utf8))
        }
        let id = UUID(uuidString: portfolio)!
        let model = CampPortfolioModel(active: try makeActive(host: host), portfolioId: id)
        await model.load()
        #expect(model.phase == .loaded && model.portfolio?.name == "Küche" && model.canWriteNotes)
        #expect(await model.addNote("Hallo") && model.notes.count == 1)
        let team = CampPortfolioModel(active: try makeActive(role: .team, host: host), portfolioId: id)
        #expect(!team.canWriteNotes)
        #expect(await team.addNote("x") == false)
    }

    @Test func startShowsCountdownProgressAndRoleSplit() async throws {
        let host = newHost()
        let start = #"{"heute":"2027-05-22","countdown":{"von":"2027-07-17","bis":"2027-07-24","tageBisBeginn":56,"tageBisEnde":63},"fortschritt":{"aufgaben":{"gesamt":8,"erledigt":5,"ueberfaellig":1},"meilensteine":null},"ueberfaellig":[]}"#
        stub(host) { request in
            request.url?.path.hasSuffix("/meine-woche") == true ? (403, apiError(403)) : (200, Data(start.utf8))
        }
        let lead = CampStartModel(active: try makeActive(host: host))
        await lead.load()
        #expect(lead.phase == .loaded && lead.isLead && lead.canCreate)
        #expect(lead.countdownTitle == "Noch 56 Tage bis zum Lager" && lead.percentDone == 63 && lead.ownTasks.isEmpty)
        let team = CampStartModel(active: try makeActive(role: .team, host: host))
        await team.load()
        #expect(!team.isLead && !team.canCreate)
    }

    @Test func startKeepsTheStandWhenTheNetworkGoes() async throws {
        let model = CampStartModel(active: try makeActive(host: newHost()))
        model.setPreview(phase: .loaded, start: CampPreviewFree.start)
        await model.load()
        #expect(model.isOffline && model.phase == .loaded && model.start != nil)
    }

    @Test func scheduleLoadsMilestonesAndDeadlines() async throws {
        let host = newHost()
        stub(host) { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/zeitplan") { return (200, Data(#"{"meilensteine":[],"lagertage":[],"tagesabschnitte":[]}"#.utf8)) }
            return (200, Data(#"{"aufgaben":[\#(taskJSON(1))],"naechster":null}"#.utf8))
        }
        let model = CampScheduleModel(active: try makeActive(host: host))
        await model.load()
        #expect(model.phase == .loaded && model.items.count == 1 && !model.isEmpty)
        let before = model.month
        model.shiftMonth(by: 1)
        #expect(model.month > before)
    }
}

private enum CampPreviewFree {
    static let start: CampStart = try! JSONDecoder.api.decode(CampStart.self, from: Data(#"{"heute":"2027-05-22","countdown":{"von":"2027-07-17","bis":"2027-07-24","tageBisBeginn":56,"tageBisEnde":63},"fortschritt":{"aufgaben":null,"meilensteine":null},"ueberfaellig":null}"#.utf8))
}

private nonisolated let detailsJSON = #"{"aufgabeId":"0190a000-0000-7000-8000-000000000101","checkliste":[{"id":"0190a000-0000-7000-8000-000000000201","version":1,"aufgabeId":"0190a000-0000-7000-8000-000000000101","text":"A","erledigt":true,"erledigtVonPersonId":null,"reihenfolge":0},{"id":"0190a000-0000-7000-8000-000000000202","version":1,"aufgabeId":"0190a000-0000-7000-8000-000000000101","text":"B","erledigt":false,"erledigtVonPersonId":null,"reihenfolge":1}],"links":[],"stichworte":[]}"#

private nonisolated let suggestionBody = #"{"vorschlaege":[{"zeile":"Offerte @Jonas #Logistik","titel":"Offerte","person":{"status":"gefunden","text":"Jonas","kandidaten":[{"id":"0190a000-0000-7000-8000-0000000000aa","name":"Jonas","ceviName":null}]},"ressort":{"status":"gefunden","text":"Logistik","kandidaten":[{"id":"0190a000-0000-7000-8000-0000000000b1","kuerzel":"LO","name":"Logistik"}]},"frist":null,"hinweise":[]}]}"#
