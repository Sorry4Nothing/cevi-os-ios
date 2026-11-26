import Foundation
import Testing
@testable import CeviOS

private nonisolated let camp = UUID(uuidString: "0190a000-0000-7000-8000-000000000001")!
private nonisolated let point1 = "0190a000-0000-7000-8000-000000009001"
private nonisolated let point2 = "0190a000-0000-7000-8000-000000009002"
private nonisolated let checkJSON = """
{"stand":"offen","datum":"2027-07-05","pruefer":[
 {"id":"aufgaben","titel":"Aufgaben","stand":"offen","hinweise":[{"code":"AUFGABEN_UEBERFAELLIG","schwere":"offen","text":"2 Aufgaben sind überfällig.","anzahl":2,
   "beispiele":[{"id":"\(point1)","titel":"Zelte prüfen","datum":"2027-07-01"},{"id":"\(point2)","titel":"Anmeldeschluss","datum":null,"offeneAufgaben":3}]}]},
 {"id":"neuer_pruefer","titel":"Neu","stand":"bereit","hinweise":[]}]}
"""
private nonisolated func pointJSON(_ id: String = point1, version: Int = 1, title: String = "Elternbrief", done: Bool = false, order: Int = 0) -> String {
    #"{"id":"\#(id)","version":\#(version),"titel":"\#(title)","erledigt":\#(done),"reihenfolge":\#(order)}"#
}
private nonisolated func pointsJSON(_ points: String...) -> String { #"{"punkte":[\#(points.joined(separator: ","))]}"# }

private nonisolated func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T { try JSONDecoder.api.decode(T.self, from: Data(json.utf8)) }
private func json(_ request: URLRequest) throws -> [String: Any] {
    let data = try #require(StubProtocol.body(of: request))
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}
private nonisolated func newHost() -> String { "c\(UUID().uuidString.prefix(8).lowercased()).test.example.org" }
private nonisolated func client(_ host: String) -> APIClient {
    APIClient(baseURL: URL(string: "https://\(host)")!, appVersion: "1.0.0", cookieStore: InMemoryCookieStore(["s": "1"]),
              session: APIClient.makeSession(protocolClasses: [StubProtocol.self]))
}

@MainActor
private func active(_ role: CampRole, status: String = "aktiv", host: String) throws -> ActiveCamp {
    let json = """
    {"id":"\(camp.uuidString)","titel":"Sommerlager","von":"2027-07-17","bis":"2027-07-24","vorbereitungAb":null,"ort":null,
     "adresse":null,"status":"\(status)","farbe":null,"logoMediumId":null,"wetterOrt":{"status":"kein_ort","name":null}}
    """
    let result = ActiveCamp()
    result.open(camp: try decode(Camp.self, json), role: role, client: client(host))
    return result
}

/// Answers the three reads of the check with fixed data and records the writes; `write` answers the first write.
private nonisolated func serve(_ host: String, points: String = pointsJSON(pointJSON()), write: @escaping @Sendable (URLRequest) -> (Int, String) = { _ in (200, pointJSON()) }) {
    StubProtocol.register(host: host) { request in
        let path = request.url?.path ?? ""
        if request.httpMethod == "GET" { return (200, [:], Data((path.hasSuffix("/check") ? checkJSON : points).utf8)) }
        let (status, body) = write(request)
        return (status, [:], Data(body.utf8))
    }
}

struct CampCheckServiceTests {
    @Test func decodesTheCheckWithAnUnknownChecker() throws {
        let check = try decode(CampCheck.self, checkJSON)
        #expect(check.state == .open && check.checkers.map(\.id) == [.tasks, .unknown])
        let note = try #require(check.checkers.first?.notes.first)
        #expect(note.severity == .open && note.count == 2 && note.examples[0].date != nil && note.examples[1].date == nil && note.examples[1].openTasks == 3)
        #expect(throws: DecodingError.self) { try decode(CampCheckState.self, "\"kaputt\"") }
    }

    @Test func routesAndBodies() async throws {
        let host = newHost()
        StubProtocol.register(host: host) { request in
            let path = request.url?.path ?? ""
            if request.httpMethod == "DELETE" { return (204, [:], Data()) }
            if request.httpMethod == "GET" { return (200, [:], Data((path.hasSuffix("/check") ? checkJSON : pointsJSON()).utf8)) }
            return (request.httpMethod == "POST" ? 201 : 200, [:], Data(pointJSON().utf8))
        }
        let api = client(host)
        let id = UUID(uuidString: point1)!
        _ = try await api.campCheck(campId: camp)
        _ = try await api.campCheckPoints(campId: camp)
        _ = try await api.createCampCheckPoint(campId: camp, CampCheckPointCreate(title: "Elternbrief"))
        _ = try await api.updateCampCheckPoint(campId: camp, pointId: id, CampCheckPointPatch(version: 1, done: true))
        try await api.deleteCampCheckPoint(campId: camp, pointId: id, version: 2)
        let requests = StubProtocol.requests(host: host)
        let base = "/api/v1/lager/" + camp.uuidString.lowercased() + "/check"
        #expect(requests.map { ($0.httpMethod ?? "") + " " + ($0.url?.path ?? "") } == [
            "GET " + base, "GET " + base + "/punkte", "POST " + base + "/punkte", "PATCH " + base + "/punkte/" + point1, "DELETE " + base + "/punkte/" + point1,
        ])
        let create = try json(requests[2])
        #expect(create["titel"] as? String == "Elternbrief" && create["reihenfolge"] == nil)
        let patch = try json(requests[3])
        #expect(Set(patch.keys) == ["version", "erledigt"] && patch["erledigt"] as? Bool == true)
        #expect(requests[4].url?.query == "version=2")
    }
}

@MainActor
struct CampCheckModelTests {
    @Test func rightsFollowTheRole() {
        func rights(_ role: CampRole, readOnly: Bool = false) -> CampCheckRights { CampCheckRights(role: role, readOnly: readOnly) }
        #expect(rights(.campLeader).reads && rights(.campLeader).edits)
        #expect(rights(.leader).reads && !rights(.leader).edits)
        #expect(rights(.readOnly).reads && !rights(.readOnly).edits)
        #expect(!rights(.team).reads && !rights(.team).edits)
        #expect(rights(.campLeader, readOnly: true).reads && !rights(.campLeader, readOnly: true).edits)
    }

    @Test func loadsTheCheckAndTheOwnPointsInOrder() async throws {
        let host = newHost()
        serve(host, points: pointsJSON(pointJSON(point2, title: "B", order: 1), pointJSON(point1, title: "A", order: 0)))
        let model = CampCheckModel(active: try active(.campLeader, host: host))
        await model.load()
        #expect(model.phase == .loaded && model.check?.state == .open && model.points.map(\.title) == ["A", "B"] && model.canEdit && model.canAddPoint)
    }

    @Test func aFailedLoadShowsTheFailureAndNoAccessOfTheTeam() async throws {
        let host = newHost()
        StubProtocol.register(host: host) { _ in (403, [:], Data(#"{"message":"x"}"#.utf8)) }
        let model = CampCheckModel(active: try active(.team, host: host))
        await model.load()
        guard case .failed(let state, _) = model.phase else { Issue.record("expected failure"); return }
        #expect(state == .noAccess)
        let offline = CampCheckModel(active: try active(.leader, host: newHost()))
        await offline.load()
        guard case .failed(let kind, _) = offline.phase else { Issue.record("expected failure"); return }
        #expect(kind == .offline)
    }

    @Test func buttonsAreMissingWithoutTheRightOrInAClosedCamp() async throws {
        let host = newHost()
        serve(host)
        for (role, status) in [(CampRole.leader, "aktiv"), (.readOnly, "aktiv"), (.campLeader, "abgeschlossen")] {
            let model = CampCheckModel(active: try active(role, status: status, host: host))
            await model.load()
            #expect(!model.canEdit && !model.canAddPoint)
            #expect(await model.add(title: "x") == false)
            await model.toggle(model.points[0])
            await model.delete(model.points[0])
        }
        #expect(StubProtocol.requests(host: host).allSatisfy { $0.httpMethod == "GET" })
    }

    @Test func addingWritesReloadsAndValidatesTheTitle() async throws {
        let host = newHost()
        serve(host) { _ in (201, pointJSON()) }
        let model = CampCheckModel(active: try active(.campLeader, host: host))
        await model.load()
        #expect(await model.add(title: "  ") == false && model.error == "Gib einen Punkt ein.")
        #expect(await model.add(title: String(repeating: "a", count: 201)) == false && model.error?.contains("zu lang") == true)
        #expect(StubProtocol.requests(host: host).filter { $0.httpMethod == "POST" }.isEmpty)
        #expect(await model.add(title: " Elternbrief ") == true && model.error == nil && model.notice?.title == "Punkt hinzugefügt.")
        let post = try #require(StubProtocol.requests(host: host).first { $0.httpMethod == "POST" })
        #expect(String(decoding: StubProtocol.body(of: post) ?? Data(), as: UTF8.self).contains("\"Elternbrief\""))
    }

    @Test func aFailedWriteShowsRetryAndNothingRepeatsOnItsOwn() async throws {
        let host = newHost()
        serve(host) { _ in (500, #"{"code":"FEHLER","message":"Fehler"}"#) }
        let model = CampCheckModel(active: try active(.campLeader, host: host))
        await model.load()
        await model.toggle(model.points[0])
        #expect(model.error != nil && model.canRetry)
        #expect(StubProtocol.requests(host: host).filter { $0.httpMethod == "PATCH" }.count == 1)
        serve(host) { _ in (200, pointJSON(version: 2, done: true)) }
        await model.retry()
        #expect(model.error == nil && !model.canRetry)
        let patches = StubProtocol.requests(host: host).filter { $0.httpMethod == "PATCH" }
        #expect(patches.count == 2)
        #expect(String(decoding: StubProtocol.body(of: patches[1]) ?? Data(), as: UTF8.self).contains("\"erledigt\":true"))
    }

    @Test func renameSendsOnlyTheTitleAndSkipsAnUnchangedOne() async throws {
        let host = newHost()
        serve(host) { _ in (200, pointJSON(title: "Neu")) }
        let model = CampCheckModel(active: try active(.campLeader, host: host))
        await model.load()
        #expect(await model.rename(model.points[0], to: "Elternbrief") == true)
        #expect(StubProtocol.requests(host: host).filter { $0.httpMethod == "PATCH" }.isEmpty)
        #expect(await model.rename(model.points[0], to: "Neu") == true)
        let patch = try #require(StubProtocol.requests(host: host).first { $0.httpMethod == "PATCH" })
        let body = try json(patch)
        #expect(Set(body.keys) == ["version", "titel"])
    }

    @Test func deletingSendsTheVersion() async throws {
        let host = newHost()
        serve(host, points: pointsJSON(pointJSON(version: 4))) { _ in (204, "") }
        let model = CampCheckModel(active: try active(.campLeader, host: host))
        await model.load()
        await model.delete(model.points[0])
        let delete = try #require(StubProtocol.requests(host: host).first { $0.httpMethod == "DELETE" })
        #expect(delete.url?.query == "version=4" && model.notice?.title == "Punkt gelöscht.")
    }

    @Test func aConflictOffersBothVersionsAndKeepMineResendsOnTheNewVersion() async throws {
        let host = newHost()
        let conflict = #"{"code":"VERSION_KONFLIKT","message":"m","aktuell":\#(pointJSON(version: 3, title: "Andere Fassung", done: true)),"abweichend":["titel"]}"#
        serve(host) { _ in (409, conflict) }
        let model = CampCheckModel(active: try active(.campLeader, host: host))
        await model.load()
        await model.toggle(model.points[0])
        let shown = try #require(model.conflict)
        #expect(shown.fields.map(\.label) == ["Punkt", "Erledigt"] && shown.mineDone && shown.current.version == 3 && !model.canRetry)
        serve(host) { _ in (200, pointJSON(version: 4, done: true)) }
        await model.resolve(.keepMine)
        #expect(model.conflict == nil)
        let last = try #require(StubProtocol.requests(host: host).last { $0.httpMethod == "PATCH" })
        #expect(String(decoding: StubProtocol.body(of: last) ?? Data(), as: UTF8.self).contains("\"version\":3"))
    }

    @Test func keepingTheCurrentVersionDropsTheChange() async throws {
        let host = newHost()
        serve(host) { _ in (409, #"{"code":"VERSION_KONFLIKT","message":"m","aktuell":\#(pointJSON(version: 3)),"abweichend":["erledigt"]}"#) }
        let model = CampCheckModel(active: try active(.campLeader, host: host))
        await model.load()
        await model.toggle(model.points[0])
        await model.resolve(.keepCurrent)
        #expect(model.conflict == nil && StubProtocol.requests(host: host).filter { $0.httpMethod == "PATCH" }.count == 1)
    }

    @Test func textsNameTheStates() {
        #expect(CampCheckModel.headline(.ready) == "Das Lager ist bereit." && CampCheckModel.stateName(.open) == "Offen")
        let example = CampCheckExample(id: UUID(), title: "M", date: DateFormats.calendarDay("2027-07-12"), openTasks: 3)
        #expect(CampCheckModel.detail(example) == "12. Juli, 3 offene Aufgaben")
        #expect(CampCheckModel.detail(CampCheckExample(id: UUID(), title: "P", date: nil, openTasks: nil)) == nil)
    }
}
