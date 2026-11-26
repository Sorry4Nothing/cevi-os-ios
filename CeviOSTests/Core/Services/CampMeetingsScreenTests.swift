import Foundation
import Testing
@testable import CeviOS

private nonisolated func uid(_ n: Int) -> String { "0190a000-0000-7000-8000-0000000007\(String(format: "%02d", n))" }
private nonisolated let campUUID = UUID(uuidString: "0190a000-0000-7000-8000-000000000001")!
private nonisolated let meetingUUID = UUID(uuidString: uid(1))!

@MainActor
private func active(_ role: CampRole = .campLeader, status: String = "aktiv", host: String) throws -> ActiveCamp {
    let json = """
    {"id":"\(campUUID.uuidString)","titel":"Sommerlager","von":"2027-07-17","bis":"2027-07-24","vorbereitungAb":null,"ort":null,
     "adresse":null,"status":"\(status)","farbe":null,"logoMediumId":null,"wetterOrt":{"status":"kein_ort","name":null}}
    """
    let client = APIClient(baseURL: URL(string: "https://\(host)")!, appVersion: "1.0.0", cookieStore: InMemoryCookieStore(["s": "1"]),
                           session: APIClient.makeSession(protocolClasses: [StubProtocol.self]))
    let active = ActiveCamp()
    active.open(camp: try JSONDecoder.api.decode(Camp.self, from: Data(json.utf8)), role: role, client: client)
    return active
}

private func host() -> String { "a\(UUID().uuidString.prefix(8).lowercased()).test.example.org" }

private func stub(_ host: String, _ handler: @escaping @Sendable (URLRequest) -> (Int, String)) {
    StubProtocol.register(host: host) { request in
        let (status, body) = handler(request)
        return (status, [:], Data(body.utf8))
    }
}

private nonisolated func itemJSON(_ n: Int, version: Int = 1, meeting: Bool = true) -> String {
    """
    {"id":"\(uid(10 + n))","version":\(version),"hoeckId":\(meeting ? "\"\(uid(1))\"" : "null"),"titel":"Punkt \(n)","text":null,"entscheid":null,
     "links":[],"reihenfolge":\(n),"aufgabeId":null,"status":"offen","verantwortliche":[]}
    """
}

private nonisolated func meetingJSON(items: [String] = []) -> String {
    """
    {"id":"\(uid(1))","version":1,"art":"lagerleitung","datum":"2027-05-26","zeit":"19:30","titel":"Hoeck 5","ort":null,"gaeste":null,"protokollId":null,
     "anwesende":[],"traktanden":[\(items.joined(separator: ","))]}
    """
}

private nonisolated func body(_ request: URLRequest) -> String { StubProtocol.body(of: request).map { String(decoding: $0, as: UTF8.self) } ?? "" }

struct CampCommsRightsTests {
    @Test func rolesGetTheirActions() {
        func rights(_ role: CampRole, readOnly: Bool = false) -> CampCommsRights { CampCommsRights(role: role, readOnly: readOnly) }
        #expect(rights(.campLeader).editsMeetings && rights(.campLeader).readsInbox && rights(.campLeader).answersInbox)
        #expect(rights(.leader).editsNotices && !rights(.leader).readsInbox)
        #expect(rights(.team).interacts && !rights(.team).editsMeetings && !rights(.team).seesAllMeetings && !rights(.team).readsProtocols)
        #expect(!rights(.readOnly).interacts && rights(.readOnly).readsProtocols && !rights(.readOnly).editsProtocols)
        let closed = rights(.campLeader, readOnly: true)
        #expect(!closed.editsMeetings && !closed.editsNotices && !closed.interacts && !closed.answersInbox && closed.readsInbox)
    }

    @Test func timeFieldAcceptsOnlyClockTimes() {
        #expect(CampMeetingsModel.isValid(time: "19:30") && CampMeetingsModel.isValid(time: ""))
        #expect(!CampMeetingsModel.isValid(time: "25:00") && !CampMeetingsModel.isValid(time: "7pm"))
    }
}

@MainActor
struct CampMeetingsModelTests {
    private nonisolated static let pageJSON = """
    {"hoecks":[
      {"id":"\(uid(1))","version":1,"art":"lagerleitung","datum":"2027-05-26","zeit":"19:30","titel":"Hoeck 5","ort":null,"gaeste":null,"protokollId":null,"anzahlTraktanden":5,"anzahlAnwesende":0},
      {"id":"\(uid(2))","version":1,"datum":"2027-05-12","zeit":null,"titel":"Team Hoeck","ort":null}],"naechster":null}
    """

    @Test func loadsBothShapesAndSplitsByDay() async throws {
        let host = host()
        stub(host) { _ in (200, Self.pageJSON) }
        let model = CampMeetingsModel(active: try active(host: host))
        model.now = { DateFormats.calendarDay("2027-05-20")! }
        await model.load()
        #expect(model.phase == .loaded && model.upcoming.map(\.title) == ["Hoeck 5"] && model.past.map(\.title) == ["Team Hoeck"])
        #expect(model.upcoming[0].agendaCount == 5 && model.past[0].agendaCount == nil)
        #expect(model.draftLikeLatest()?.date == DateFormats.calendarDay("2027-06-02"))
    }

    @Test func failureWithoutDataShowsTheState() async throws {
        let host = host()
        stub(host) { _ in (403, #"{"code":"X","message":"Nein"}"#) }
        let model = CampMeetingsModel(active: try active(.team, host: host))
        await model.load()
        if case .failed(let state, _) = model.phase { #expect(state == .noAccess) } else { Issue.record("expected failure") }
    }

    @Test func createChecksInputAndPostsTheMeeting() async throws {
        let host = host()
        stub(host) { request in request.httpMethod == "POST" ? (201, meetingJSON()) : (200, Self.pageJSON) }
        let model = CampMeetingsModel(active: try active(host: host))
        var draft = CampMeetingsModel.Draft()
        #expect(await !model.create(draft) && model.inputError != nil)
        draft.title = "Hoeck 6"
        draft.time = "7pm"
        #expect(await !model.create(draft))
        draft.time = "19:30"
        #expect(await model.create(draft))
        let post = try #require(StubProtocol.requests(host: host).first { $0.httpMethod == "POST" })
        #expect(post.url?.path == "/api/v1/lager/\(campUUID.uuidString.lowercased())/hoecks" && body(post).contains("\"titel\":\"Hoeck 6\""))
    }

    @Test func teamCannotCreate() async throws {
        let host = host()
        stub(host) { _ in (200, Self.pageJSON) }
        let model = CampMeetingsModel(active: try active(.team, host: host))
        var draft = CampMeetingsModel.Draft()
        draft.title = "X"
        #expect(await !model.create(draft))
        #expect(StubProtocol.requests(host: host).isEmpty)
    }
}

@MainActor
struct CampAgendaAndModeTests {
    @Test func movingSendsTheSwappedOrder() async throws {
        let host = host()
        stub(host) { request in
            request.httpMethod == "PUT" ? (204, "") : (200, meetingJSON(items: [itemJSON(1), itemJSON(2), itemJSON(3)]))
        }
        let model = CampAgendaModel(active: try active(host: host), meetingId: meetingUUID)
        await model.load()
        #expect(model.items.count == 3 && !model.canMove(model.items[0], by: -1) && model.canMove(model.items[0], by: 1))
        await model.move(model.items[0], by: 1)
        let put = try #require(StubProtocol.requests(host: host).first { $0.httpMethod == "PUT" })
        let text = body(put).lowercased()
        #expect(put.url?.path.hasSuffix("/traktanden/reihenfolge") == true)
        #expect(try #require(text.range(of: uid(12))).lowerBound < #require(text.range(of: uid(11))).lowerBound)
    }

    @Test func postponeClearsTheMeetingAndUndoPutsItBack() async throws {
        let host = host()
        stub(host) { request in
            request.httpMethod == "PATCH" ? (200, itemJSON(1, version: 2, meeting: false)) : (200, meetingJSON(items: [itemJSON(1)]))
        }
        let model = CampAgendaModel(active: try active(host: host), meetingId: meetingUUID)
        await model.load()
        await model.postpone(model.items[0])
        #expect(model.notice?.title == "«Punkt 1» ist auf dem nächsten Hoeck." && model.hasUndo)
        let first = try #require(StubProtocol.requests(host: host).first { $0.httpMethod == "PATCH" })
        #expect(body(first).contains("\"hoeckId\":null") && body(first).contains("\"version\":1"))
        await model.undo()
        let patches = StubProtocol.requests(host: host).filter { $0.httpMethod == "PATCH" }
        #expect(patches.count == 2 && body(patches[1]).lowercased().contains(uid(1)) && body(patches[1]).contains("\"version\":2"))
    }

    @Test func teamAndReadersHaveNoEditButtons() async throws {
        let host = host()
        stub(host) { _ in (200, meetingJSON(items: [itemJSON(1), itemJSON(2)])) }
        let reader = CampAgendaModel(active: try active(.readOnly, host: host), meetingId: meetingUUID)
        await reader.load()
        #expect(!reader.canEdit && !reader.canMove(reader.items[0], by: 1))
        let closed = CampAgendaModel(active: try active(status: "abgeschlossen", host: host), meetingId: meetingUUID)
        await closed.load()
        #expect(!closed.canEdit)
    }

    @Test func tickGoesBackWhenTheServerRefuses() async throws {
        let host = host()
        let mode = """
        {"hoeck":\(meetingJSON()),"mitglieder":[{"id":"\(uid(5))","name":"Mara","ceviName":"Luchs","rolle":"leitung","anwesend":false}],"ressortRunde":null}
        """
        stub(host) { request in request.httpMethod == "PUT" ? (500, "{}") : (200, mode) }
        let model = CampMeetingModeModel(active: try active(host: host), meetingId: meetingUUID)
        await model.load()
        #expect(model.presentCount == 0 && CampMeetingModeModel.name(model.members[0]) == "Mara")
        await model.togglePresent(model.members[0])
        #expect(model.presentCount == 0 && model.error != nil)
        #expect(StubProtocol.requests(host: host).contains { $0.httpMethod == "PUT" && $0.url?.path.hasSuffix("/anwesende/\(uid(5))") == true })
    }
}

@MainActor
struct CampProtocolModelTests {
    private nonisolated static func minutes(version: Int, title: String) -> String {
        """
        {"id":"\(uid(50))","version":\(version),"art":"sitzung","titel":"\(title)","datum":"2027-05-26","hoeckId":"\(uid(1))","dateiId":"\(uid(51))","datei":null,
         "erstelltAm":"2027-05-26T20:00:00Z","erstelltVon":null}
        """
    }

    private nonisolated static func handler(patch: @escaping @Sendable (URLRequest) -> (Int, String)) -> @Sendable (URLRequest) -> (Int, String) {
        { request in
            let path = request.url?.path ?? ""
            if request.httpMethod == "PATCH" { return patch(request) }
            if path.hasSuffix("/hoecks/\(uid(1))") { return (200, meetingJSON().replacingOccurrences(of: #""protokollId":null"#, with: #""protokollId":"\#(uid(50))""#)) }
            if path.hasSuffix("/protokolle/\(uid(50))") { return (200, Self.minutes(version: 1, title: "Protokoll")) }
            return (200, #"{"beschluesse":[],"naechster":null}"#)
        }
    }

    @Test func conflictKeepsTheInputAndKeepMineResendsOnTheNewVersion() async throws {
        let host = host()
        let conflict = #"{"code":"VERSION_KONFLIKT","message":"Konflikt","aktuell":\#(Self.minutes(version: 2, title: "Von Lea")),"abweichend":["titel"]}"#
        stub(host, Self.handler { request in body(request).contains("\"version\":2") ? (200, Self.minutes(version: 3, title: "Meins")) : (409, conflict) })
        let model = CampProtocolModel(active: try active(host: host), meetingId: meetingUUID)
        await model.load()
        model.draft.title = "Meins"
        await model.save()
        let pending = try #require(model.conflict)
        #expect(pending.current.title == "Von Lea" && pending.fields.first { $0.label == "Titel" }?.differs == true)
        await model.resolve(.keepMine)
        #expect(model.conflict == nil && model.minutes?.version == 3 && model.draft.title == "Meins")
    }

    @Test func failedSaveKeepsTheInput() async throws {
        let host = host()
        stub(host, Self.handler { _ in (500, #"{"code":"X","message":"Fehler"}"#) })
        let model = CampProtocolModel(active: try active(host: host), meetingId: meetingUUID)
        await model.load()
        model.draft.title = "Neu"
        await model.save()
        #expect(model.saveFailed && model.draft.title == "Neu" && model.isDirty)
    }

    @Test func teamCannotReadProtocols() async throws {
        let host = host()
        stub(host) { _ in (200, "{}") }
        let model = CampProtocolModel(active: try active(.team, host: host), meetingId: meetingUUID)
        await model.load()
        if case .failed(let state, _) = model.phase { #expect(state == .noAccess) } else { Issue.record("expected failure") }
        #expect(StubProtocol.requests(host: host).isEmpty)
    }
}
