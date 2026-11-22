import Foundation
import Testing
@testable import CeviOS

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder.api.decode(T.self, from: Data(json.utf8))
}

private let uuid1 = "0190a000-0000-7000-8000-000000000001"
private let uuid2 = "0190a000-0000-7000-8000-000000000002"
private let uuid3 = "0190a000-0000-7000-8000-000000000003"

private let entryJSON = #"{"id":"\#(uuid1)","version":2,"personId":"\#(uuid2)","teilnehmerId":null,"lagertagId":"\#(uuid2)","tagesabschnittId":"\#(uuid3)","wert":"A"}"#
private let requestJSON = """
{"id":"\(uuid1)","version":1,"personId":"\(uuid2)","lagertagId":"\(uuid2)","tagesabschnittId":"\(uuid3)","wert":"F","notiz":"Arzttermin","status":"offen",
 "entschiedenVon":null,"entschiedenAm":null,"erstelltAm":"2027-07-10T08:00:00Z"}
"""

struct CampAttendanceModelTests {
    @Test func matrixPageDecodes() throws {
        let page = try decode(CampAttendancePage.self, #"{"eintraege":[\#(entryJSON),{"id":"\#(uuid2)","version":1,"personId":null,"teilnehmerId":"\#(uuid3)","lagertagId":"\#(uuid2)","tagesabschnittId":"\#(uuid3)","wert":"O"}],"naechster":"\#(uuid3)","frist":"2027-07-09T22:00:00Z"}"#)
        #expect(page.entries[0].value == .present && page.entries[1].participantId != nil && page.entries[1].value == .open)
        #expect(page.next != nil && page.deadline != nil)
        let noDeadline = try decode(CampAttendancePage.self, #"{"eintraege":[],"naechster":null,"frist":null}"#)
        #expect(noDeadline.deadline == nil && noDeadline.next == nil)
    }

    @Test func unknownValueIsRejected() {
        #expect(throws: DecodingError.self) { try decode(CampAttendanceEntry.self, entryJSON.replacingOccurrences(of: #""A""#, with: #""X""#)) }
    }

    @Test func ownAttendanceKeepsRequestsApart() throws {
        let own = try decode(CampOwnAttendance.self, #"{"eintraege":[\#(entryJSON)],"anfragen":[\#(requestJSON)],"frist":null}"#)
        #expect(own.entries.count == 1 && own.requests.first?.status == .open && own.requests.first?.value == .absent)
        #expect(own.requests.first?.note == "Arzttermin" && own.requests.first?.decidedAt == nil)
    }

    @Test func requestStatusesDecode() throws {
        for (text, status) in [("offen", CampAttendanceRequestStatus.open), ("angenommen", .accepted), ("abgelehnt", .rejected)] {
            let request = try decode(CampAttendanceRequest.self, requestJSON.replacingOccurrences(of: #""offen""#, with: "\"\(text)\""))
            #expect(request.status == status)
        }
    }

    @Test func summaryDecodes() throws {
        let summary = try decode(CampAttendanceSummary.self, #"{"zeilen":[{"lagertagId":"\#(uuid1)","tagesabschnittId":"\#(uuid2)","wert":"A","leitende":3,"teilnehmende":20}]}"#)
        #expect(summary.rows.first?.leaders == 3 && summary.rows.first?.participants == 20)
    }

    @Test func wholeDayMakesOneFieldPerSection() throws {
        let day = UUID(), sections = [UUID(), UUID(), UUID()]
        let fields = CampAttendanceField.wholeDay(day, sectionIds: sections, value: .present)
        #expect(fields.map(\.sectionId) == sections && fields.allSatisfy { $0.dayId == day && $0.value == .present })
        let data = try JSONEncoder.api.encode(CampAttendanceFieldsBody(entries: fields))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((object["eintraege"] as? [[String: Any]])?.first?["wert"] as? String == "A" && object["notiz"] == nil)
    }

    @Test func deadlineBodySendsNullToLift() throws {
        let lifted = try #require(JSONSerialization.jsonObject(with: JSONEncoder.api.encode(CampAttendanceDeadlineBody(deadline: nil))) as? [String: Any])
        #expect(lifted["frist"] is NSNull)
    }

    @Test func blockedFieldsAreReadFromTheConflict() throws {
        let body = #"{"code":"ANFRAGE_NOETIG","message":"x","gesperrt":[{"lagertagId":"\#(uuid1)","tagesabschnittId":"\#(uuid2)","grund":"frist"},{"lagertagId":"\#(uuid1)","tagesabschnittId":"\#(uuid3)","grund":"neu"}]}"#
        let error = APIError.from(status: 409, data: Data(body.utf8))
        let blocked = try #require(CampRules.attendanceBlocked(error))
        #expect(blocked.map(\.reason) == [.deadline, .unknown])
        #expect(CampRules.attendanceBlocked(APIError.from(status: 409, data: Data(#"{"code":"ANFRAGE_OFFEN","message":"x"}"#.utf8))) == nil)
        #expect(CampRules.attendanceBlocked(APIError.from(status: 403, data: Data(body.utf8))) == nil)
    }
}

struct CampAttendanceServiceTests {
    private let camp = UUID(), id = UUID(), other = UUID()
    private var campPath: String { "/api/v1/lager/\(camp.uuidString.lowercased())" }

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

    @Test func matrixRoutes() async throws {
        var r = try await sent(#"{"eintraege":[],"naechster":null,"frist":null}"#) { _ = try await $0.campAttendance(campId: camp, dayIds: [id, other], after: other, limit: 50) }
        #expect(r.method == "GET" && r.path == campPath + "/anwesenheit" && r.query["limit"] == "50" && r.query["nach"] == other.uuidString.lowercased())
        #expect(r.query["lagertagIds"] == "\(id.uuidString.lowercased()),\(other.uuidString.lowercased())")
        r = try await sent(#"{"eintraege":[]}"#) { _ = try await $0.campAttendance(campId: camp) }
        #expect(r.query["lagertagIds"] == nil)
        var entries: [CampAttendanceEntry] = []
        r = try await sent(#"{"eintraege":[\#(entryJSON)]}"#) {
            entries = try await $0.setCampAttendance(campId: camp, [CampAttendanceLeaderField(participantId: id, dayId: id, sectionId: other, value: .open, version: 2)])
        }
        let field = try #require((r.body?["eintraege"] as? [[String: Any]])?.first)
        #expect(r.method == "PUT" && r.path == campPath + "/anwesenheit" && entries.count == 1)
        #expect(field["wert"] as? String == "O" && field["version"] as? Int == 2 && field["personId"] == nil && field["teilnehmerId"] != nil)
        r = try await sent(#"{"zeilen":[]}"#) { _ = try await $0.campAttendanceSummary(campId: camp) }
        #expect(r.method == "GET" && r.path == campPath + "/anwesenheit/zusammenfassung")
    }

    @Test func deadlineRoute() async throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        var result: Date?
        let r = try await sent(#"{"frist":"2027-01-15T08:00:00Z"}"#) { result = try await $0.setCampAttendanceDeadline(campId: camp, date) }
        #expect(r.method == "PUT" && r.path == campPath + "/anwesenheit/frist" && r.body?["frist"] is String && result != nil)
    }

    @Test func ownRoutes() async throws {
        var r = try await sent(#"{"eintraege":[],"anfragen":[],"frist":null}"#) { _ = try await $0.ownCampAttendance(campId: camp, dayIds: [id]) }
        #expect(r.method == "GET" && r.path == campPath + "/anwesenheit/eigene" && r.query["lagertagIds"] == id.uuidString.lowercased())
        r = try await sent(#"{"eintraege":[\#(entryJSON)]}"#) {
            _ = try await $0.setOwnCampAttendance(campId: camp, CampAttendanceField.wholeDay(id, sectionIds: [other, UUID()], value: .present))
        }
        #expect(r.method == "PUT" && r.path == campPath + "/anwesenheit/eigene" && (r.body?["eintraege"] as? [Any])?.count == 2)
        #expect(Set(r.body?.keys.map { $0 } ?? []) == ["eintraege"])
    }

    @Test func ownWriteRefusedWithConflictNeedsARequest() async throws {
        let host = "a\(UUID().uuidString.prefix(8).lowercased()).test.example.org"
        let json = #"{"code":"ANFRAGE_NOETIG","message":"x","gesperrt":[{"lagertagId":"\#(uuid1)","tagesabschnittId":"\#(uuid2)","grund":"eingetragen"}]}"#
        StubProtocol.register(host: host) { _ in (409, [:], Data(json.utf8)) }
        let client = APIClient(baseURL: URL(string: "https://\(host)")!, appVersion: "1.0.0", cookieStore: InMemoryCookieStore(["s": "1"]), session: APIClient.makeSession(protocolClasses: [StubProtocol.self]))
        do {
            _ = try await client.setOwnCampAttendance(campId: camp, [CampAttendanceField(dayId: id, sectionId: other, value: .absent)])
            Issue.record("expected a conflict")
        } catch let error as APIError {
            #expect(CampRules.attendanceBlocked(error)?.first?.reason == .entered)
        }
    }

    @Test func requestRoutes() async throws {
        var r = try await sent(status: 201, #"{"anfragen":[\#(requestJSON)]}"#) {
            let requests = try await $0.requestCampAttendanceChange(campId: camp, [CampAttendanceField(dayId: id, sectionId: other, value: .absent)], note: "Arzttermin")
            #expect(requests.first?.status == .open)
        }
        #expect(r.method == "POST" && r.path == campPath + "/anwesenheit/anfragen" && r.body?["notiz"] as? String == "Arzttermin")
        r = try await sent(#"{"anfragen":[],"naechster":null}"#) { _ = try await $0.campAttendanceRequests(campId: camp, status: .open, after: other) }
        #expect(r.method == "GET" && r.path == campPath + "/anwesenheit/anfragen" && r.query["status"] == "offen" && r.query["limit"] == "100")
        r = try await sent(#"{"anfragen":[\#(requestJSON.replacingOccurrences(of: #""offen""#, with: #""angenommen""#))]}"#) {
            let decided = try await $0.decideCampAttendanceRequests(campId: camp, .accepted, requests: [CampVersionRef(id: id, version: 1)])
            #expect(decided.first?.status == .accepted)
        }
        let first = try #require((r.body?["anfragen"] as? [[String: Any]])?.first)
        #expect(r.method == "POST" && r.path == campPath + "/anwesenheit/anfragen/entscheid" && r.body?["entscheid"] as? String == "angenommen" && first["version"] as? Int == 1)
    }
}
