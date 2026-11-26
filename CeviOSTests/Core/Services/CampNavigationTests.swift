import Foundation
import Testing
@testable import CeviOS

private func error(_ status: Int, _ code: String? = nil) -> APIError {
    let body = code.map { #"{"code":"\#($0)","message":"x"}"# } ?? "{}"
    return APIError.from(status: status, data: Data(body.utf8))
}

struct CampScreenStateTests {
    @Test func errorsLeadToTheirState() {
        #expect(CampScreenState(error: error(401)) == .sessionEnded)
        #expect(CampScreenState(error: error(404)) == .notFound)
        #expect(CampScreenState(error: error(403)) == .noAccess)
        #expect(CampScreenState(error: error(503)) == .maintenance)
        #expect(CampScreenState(error: error(500, "WARTUNG")) == .maintenance)
        #expect(CampScreenState(error: error(409, "LAGER_GESCHLOSSEN")) == .closed)
        #expect(CampScreenState(error: error(409, "VERSION_KONFLIKT")) == .versionConflict)
        #expect(CampScreenState(error: .network) == .offline)
    }

    @Test func otherErrorsHaveNoStateOfTheirOwn() {
        #expect(CampScreenState(error: error(409, "KONFLIKT")) == nil)
        #expect(CampScreenState(error: error(500)) == nil)
        #expect(CampScreenState(error: error(429)) == nil)
    }

    @Test func closedCampAndConflictAreNotFullScreen() {
        #expect(!CampScreenState.closed.isFullScreen)
        #expect(!CampScreenState.versionConflict.isFullScreen)
        #expect(CampScreenState.maintenance.isFullScreen)
    }

    @Test func queueTextCountsChangesAndNamesMissingNetwork() {
        #expect(CampQueueText.title(waiting: 3, offline: true) == "Ohne Netz. 3 Änderungen warten.")
        #expect(CampQueueText.title(waiting: 1, offline: false) == "1 Änderung wartet.")
    }

    @Test func conflictFieldDiffersOnlyWhenValuesDiffer() {
        #expect(CampConflictField(label: "Frist", mine: "15. März", current: "22. März").differs)
        #expect(!CampConflictField(label: "Status", mine: "Läuft", current: "Läuft").differs)
    }

    @Test func campDatesAreWrittenInGerman() throws {
        let a = try #require(DateFormats.calendarDay("2027-07-17")), b = try #require(DateFormats.calendarDay("2027-07-24"))
        let c = try #require(DateFormats.calendarDay("2027-08-02"))
        #expect(CampFormat.dates(from: a, to: b) == "17. bis 24. Juli 2027")
        #expect(CampFormat.dates(from: a, to: c) == "17. Juli bis 2. August 2027")
    }
}

@MainActor
struct ActiveCampTests {
    private func camp(_ status: String, id: UUID = UUID()) throws -> Camp {
        let json = """
        {"id":"\(id.uuidString)","titel":"Sommerlager","von":"2027-07-10","bis":"2027-07-17","vorbereitungAb":null,"ort":null,
         "adresse":null,"status":"\(status)","farbe":null,"logoMediumId":null,"wetterOrt":{"status":"kein_ort","name":null}}
        """
        return try JSONDecoder.api.decode(Camp.self, from: Data(json.utf8))
    }

    @Test func openingAndLeavingSwitchesTheView() throws {
        let active = ActiveCamp()
        #expect(!active.isOpen)
        active.open(camp: try camp("aktiv"), role: .team, client: nil)
        #expect(active.isOpen && active.role == .team && active.title == "Sommerlager" && !active.isReadOnly)
        active.leave()
        #expect(!active.isOpen && active.role == nil)
    }

    @Test func memberNamesAreLoadedOnceAndStayEmptyOnRefusal() async throws {
        let person = UUID()
        for (status, body, expected) in [(200, #"{"mitglieder":[{"personId":"\#(person.uuidString)","name":"Lea","bildUrl":null,"rolle":"team","ressorts":[]}]}"#, "Lea"), (403, "{}", nil)] {
            let host = "a\(UUID().uuidString.prefix(8).lowercased()).test.example.org"
            StubProtocol.register(host: host) { _ in (status, [:], Data(body.utf8)) }
            let client = APIClient(baseURL: URL(string: "https://\(host)")!, appVersion: "1.0.0", cookieStore: InMemoryCookieStore(["s": "1"]),
                                   session: APIClient.makeSession(protocolClasses: [StubProtocol.self]))
            let active = ActiveCamp()
            active.open(camp: try camp("aktiv"), role: .team, client: client)
            await active.loadMemberNames()
            await active.loadMemberNames()
            #expect(active.memberNames[person] == expected)
            #expect(StubProtocol.requests(host: host).count == (expected == nil ? 2 : 1))
        }
    }

    @Test func completedAndArchivedCampsAreReadOnly() throws {
        let active = ActiveCamp()
        active.open(camp: try camp("abgeschlossen"), role: .leader, client: nil)
        #expect(active.isReadOnly)
        active.leave()
        active.open(camp: try camp("archiviert"), role: .leader, client: nil)
        #expect(active.isReadOnly)
    }
}

@MainActor
struct CampListAndRouterTests {
    private func host() -> String { "a\(UUID().uuidString.prefix(8).lowercased()).test.example.org" }

    private func client(host: String) -> APIClient {
        APIClient(baseURL: URL(string: "https://\(host)")!, appVersion: "1.0.0", cookieStore: InMemoryCookieStore(["s": "1"]),
                  session: APIClient.makeSession(protocolClasses: [StubProtocol.self]))
    }

    private nonisolated static func entryJSON(_ id: UUID, status: String) -> String {
        """
        {"id":"\(id.uuidString)","titel":"Lager","von":"2027-07-10","bis":"2027-07-17","vorbereitungAb":null,"ort":null,
         "adresse":null,"status":"\(status)","farbe":null,"logoMediumId":null,"wetterOrt":{"status":"kein_ort","name":null},"rolle":"team"}
        """
    }

    @Test func switcherShowsOnlyWithCamps() async {
        let empty = host(), withCamp = host(), failing = host()
        StubProtocol.register(host: empty) { _ in (200, [:], Data(#"{"lager":[]}"#.utf8)) }
        StubProtocol.register(host: withCamp) { _ in (200, [:], Data("{\"lager\":[\(Self.entryJSON(UUID(), status: "aktiv"))]}".utf8)) }
        StubProtocol.register(host: failing) { _ in (404, [:], Data("{}".utf8)) }
        let a = CampListModel(), b = CampListModel(), c = CampListModel()
        #expect(!a.showsSwitcher)
        await a.load(client: client(host: empty))
        await b.load(client: client(host: withCamp))
        await c.load(client: client(host: failing))
        #expect(!a.showsSwitcher && a.phase == .loaded)
        #expect(b.showsSwitcher)
        #expect(!c.showsSwitcher)
        if case .failed(let state, _) = c.phase { #expect(state == .notFound) } else { Issue.record("expected failure") }
    }

    @Test func campsAreSplitIntoOpenAndClosed() async {
        let host = host()
        let body = "{\"lager\":[\(Self.entryJSON(UUID(), status: "aktiv")),\(Self.entryJSON(UUID(), status: "abgeschlossen")),\(Self.entryJSON(UUID(), status: "entwurf"))]}"
        StubProtocol.register(host: host) { _ in (200, [:], Data(body.utf8)) }
        let model = CampListModel()
        await model.load(client: client(host: host))
        #expect(model.openCamps.count == 2 && model.closedCamps.count == 1)
    }

    @Test func failedReloadKeepsTheCamps() async {
        let host = host()
        StubProtocol.register(host: host) { _ in (200, [:], Data("{\"lager\":[\(Self.entryJSON(UUID(), status: "aktiv"))]}".utf8)) }
        let model = CampListModel()
        await model.load(client: client(host: host))
        StubProtocol.register(host: host) { _ in (500, [:], Data("{}".utf8)) }
        await model.load(client: client(host: host))
        #expect(model.showsSwitcher)
    }

    @Test func pushResolvesAndOpensTheCamp() async {
        let host = host(), campId = UUID(), objectId = UUID()
        StubProtocol.register(host: host) { request in
            if request.url?.path.contains("/aufloesen/") == true {
                return (200, [:], Data(#"{"lagerId":"\#(campId.uuidString)","objektTyp":"aufgabe","objektId":"\#(objectId.uuidString)"}"#.utf8))
            }
            return (200, [:], Data("{\"lager\":[\(Self.entryJSON(campId, status: "aktiv"))]}".utf8))
        }
        let active = ActiveCamp()
        let outcome = await CampRouter.open(type: .task, objectId: objectId, client: client(host: host), list: CampListModel(), active: active)
        #expect(outcome == nil)
        #expect(active.camp?.id == campId)
    }

    @Test func pushOfAStrangerCampShowsNoAccess() async {
        let host = host()
        StubProtocol.register(host: host) { _ in (404, [:], Data("{}".utf8)) }
        let active = ActiveCamp()
        let outcome = await CampRouter.open(type: .notice, objectId: UUID(), client: client(host: host), list: CampListModel(), active: active)
        #expect(outcome == .noAccess)
        #expect(!active.isOpen)
    }
}
