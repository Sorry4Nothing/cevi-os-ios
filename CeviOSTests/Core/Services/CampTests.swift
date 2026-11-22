import Foundation
import Testing
@testable import CeviOS

struct CampModelsTests {
    private static let campJSON = """
    {"id":"0190a000-0000-7000-8000-000000000001","titel":"Sommerlager","von":"2027-07-10","bis":"2027-07-17",
     "vorbereitungAb":null,"ort":"Beispielwald","adresse":null,"status":"aktiv","farbe":"#003973","logoMediumId":null,
     "rolle":"team"
    """

    @Test func listEntryIsDecodedWithRole() throws {
        let json = Self.campJSON + "}"
        let entry = try JSONDecoder.api.decode(CampListEntry.self, from: Data(json.utf8))
        #expect(entry.role == .team)
        #expect(entry.camp.title == "Sommerlager")
        #expect(entry.camp.status == .active)
        #expect(entry.camp.preparationFrom == nil)
        #expect(entry.camp.to > entry.camp.from)
        #expect(entry.id == entry.camp.id)
    }

    @Test func detailKnowsWhenItIsReadOnly() throws {
        let json = Self.campJSON.replacing("\"aktiv\"", with: "\"abgeschlossen\"") + ",\"schreibgeschuetzt\":true}"
        let detail = try JSONDecoder.api.decode(CampDetail.self, from: Data(json.utf8))
        #expect(detail.isReadOnly)
        #expect(detail.camp.status == .completed)
    }

    @Test func unknownRoleIsRejected() {
        let json = Self.campJSON.replacing("\"team\"", with: "\"chef\"") + "}"
        #expect(throws: DecodingError.self) { try JSONDecoder.api.decode(CampListEntry.self, from: Data(json.utf8)) }
    }

    private static let rightsJSON = """
    {"rechte":[
      {"recht":"aufgaben.bearbeiten","bedeutung":"Aufgaben bearbeiten","standard":{"leitung":true,"team":false,"lesen":false},
       "aktuell":{"leitung":true,"team":true,"lesen":false}},
      {"recht":"pinnwand.lesen","bedeutung":"Pinnwand lesen","standard":{"leitung":true,"team":true,"lesen":true},
       "aktuell":{"leitung":true,"team":true,"lesen":true}}]}
    """

    @Test func campLeadMayDoEverythingOthersFollowTheMatrix() throws {
        let rights = try JSONDecoder.api.decode(CampRights.self, from: Data(Self.rightsJSON.utf8))
        #expect(rights.allows("aufgaben.bearbeiten", role: .campLeader))
        #expect(rights.allows("irgendwas.neues", role: .campLeader))
        #expect(rights.allows("aufgaben.bearbeiten", role: .team))
        #expect(!rights.allows("aufgaben.bearbeiten", role: .readOnly))
        #expect(rights.allows("pinnwand.lesen", role: .readOnly))
    }

    @Test func unknownRightIsRefusedForEveryoneButTheCampLead() throws {
        let rights = try JSONDecoder.api.decode(CampRights.self, from: Data(Self.rightsJSON.utf8))
        #expect(!rights.allows("gibt.es.nicht", role: .leader))
    }

    @Test func notificationsDecodeAndTolerateNewKinds() throws {
        let json = """
        {"eintraege":[
          {"id":"0190a000-0000-7000-8000-000000000011","art":"aufgabe_zugeteilt","objektTyp":"aufgabe",
           "objektId":"0190a000-0000-7000-8000-000000000021","gelesen":false,"erstelltAm":"2027-07-01T08:00:00Z"},
          {"id":"0190a000-0000-7000-8000-000000000012","art":"etwas_neues","objektTyp":"x",
           "objektId":"0190a000-0000-7000-8000-000000000022","gelesen":true,"erstelltAm":"2027-07-01T09:00:00Z"}],
         "naechster":"0190a000-0000-7000-8000-000000000012"}
        """
        let page = try JSONDecoder.api.decode(CampNotificationPage.self, from: Data(json.utf8))
        #expect(page.entries.map(\.kind) == [.taskAssigned, .unknown])
        #expect(page.entries[1].isRead)
        #expect(page.next != nil)
    }

    @Test func feedEntriesAndStateAreDecoded() throws {
        let page = try JSONDecoder.api.decode(CampChangesPage.self, from: Data("""
        {"eintraege":[{"seq":7,"objekttyp":"aufgabe","id":"0190a000-0000-7000-8000-000000000031","art":"geloescht",
                       "version":3,"zeitpunkt":"2027-07-01T08:00:00Z"}],"bis":7,"weitere":false}
        """.utf8))
        #expect(page.changes.first?.kind == .deleted)
        #expect(page.until == 7 && !page.hasMore)
        let state = try JSONDecoder.api.decode(CampFeedState.self, from: Data(#"{"seq":42,"objekttypen":["aufgabe","hoeck"]}"#.utf8))
        #expect(state.seq == 42 && state.objectTypes.count == 2)
    }
}

struct CampPushTests {
    @Test func campPushesLeadToTheirTypeAndObject() {
        let id = UUID()
        let target = PushTarget.from(userInfo: ["typ": "lager_aufgabe", "id": id.uuidString])
        #expect(target == .camp(.task, id))
        #expect(PushTarget.from(userInfo: ["typ": "lager_anwesenheit", "id": id.uuidString]) == .camp(.attendance, id))
    }

    @Test func campPushWithBrokenIdOrUnknownTypeYieldsNil() {
        #expect(PushTarget.from(userInfo: ["typ": "lager_aufgabe", "id": "kaputt"]) == nil)
        #expect(PushTarget.from(userInfo: ["typ": "lager_unbekannt", "id": UUID().uuidString]) == nil)
    }

    @Test func existingPushTypesStayTheSame() {
        let id = UUID()
        #expect(PushTarget.from(userInfo: ["typ": "chat", "id": id.uuidString]) == .chat(id))
        #expect(PushTarget.from(userInfo: ["typ": "programm", "id": id.uuidString]) == .program(id))
    }
}

struct CampServiceTests {
    private func client(host: String) -> APIClient {
        APIClient(
            baseURL: URL(string: "https://\(host)")!, appVersion: "1.0.0", cookieStore: InMemoryCookieStore(["s": "1"]),
            session: APIClient.makeSession(protocolClasses: [StubProtocol.self])
        )
    }

    private func host() -> String { "a\(UUID().uuidString.prefix(8).lowercased()).test.example.org" }

    @Test func campsAreLoadedFromTheListRoute() async throws {
        let host = host()
        StubProtocol.register(host: host) { _ in (200, [:], Data(#"{"lager":[]}"#.utf8)) }
        let camps = try await client(host: host).camps()
        #expect(camps.isEmpty)
        #expect(StubProtocol.requests(host: host).first?.url?.path == "/api/v1/lager")
    }

    @Test func notificationsSendLimitAndCursor() async throws {
        let host = host()
        StubProtocol.register(host: host) { _ in (200, [:], Data(#"{"eintraege":[],"naechster":null}"#.utf8)) }
        let camp = UUID(), cursor = UUID()
        _ = try await client(host: host).campNotifications(campId: camp, after: cursor, limit: 20)
        let url = try #require(StubProtocol.requests(host: host).first?.url)
        #expect(url.path == "/api/v1/lager/\(camp.uuidString.lowercased())/benachrichtigungen")
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.contains(URLQueryItem(name: "limit", value: "20")))
        #expect(query.contains(URLQueryItem(name: "nach", value: cursor.uuidString.lowercased())))
    }

    @Test func markingReadSendsPostWithIdsOrNone() async throws {
        let host = host()
        StubProtocol.register(host: host) { _ in (204, [:], Data()) }
        let camp = UUID()
        try await client(host: host).markCampNotificationsRead(campId: camp)
        let request = try #require(StubProtocol.requests(host: host).first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/v1/lager/\(camp.uuidString.lowercased())/benachrichtigungen/gelesen")
    }

    @Test func notificationSettingsAreReadAndSet() async throws {
        let host = host()
        StubProtocol.register(host: host) { request in
            request.httpMethod == "GET"
                ? (200, [:], Data(#"{"arten":[{"art":"erwaehnung","aktiv":false},{"art":"frist","aktiv":true},{"art":"neue_art","aktiv":true}]}"#.utf8))
                : (204, [:], Data())
        }
        let client = client(host: host)
        let settings = try await client.campNotificationSettings()
        #expect(settings.kinds == [.init(kind: .mention, enabled: false), .init(kind: .deadline, enabled: true)])
        try await client.setCampNotificationSettings([.init(kind: .mention, enabled: true)])
        let put = try #require(StubProtocol.requests(host: host).last)
        #expect(put.httpMethod == "PUT" && put.url?.path == "/api/v1/ich/lager-benachrichtigungen")
        let body = try #require(StubProtocol.body(of: put))
        let text = String(decoding: body, as: UTF8.self)
        #expect(text.contains(#""art":"erwaehnung""#) && text.contains(#""aktiv":true"#))
    }

    @Test func pushIsResolvedByTypeAndObject() async throws {
        let host = host()
        let camp = UUID(), object = UUID()
        StubProtocol.register(host: host) { _ in
            (200, [:], Data(#"{"lagerId":"\#(camp.uuidString)","objektTyp":"aufgabe","objektId":"\#(object.uuidString)"}"#.utf8))
        }
        let resolution = try await client(host: host).resolveCampPush(type: .task, objectId: object)
        #expect(resolution.campId == camp)
        #expect(StubProtocol.requests(host: host).first?.url?.path == "/api/v1/lager/aufloesen/lager_aufgabe/\(object.uuidString.lowercased())")
    }

    @Test func feedAnswering410MeansReload() async throws {
        let host = host()
        StubProtocol.register(host: host) { _ in
            (410, [:], Data(#"{"code":"FEED_NEU_LADEN","message":"Bitte neu laden.","seq":12}"#.utf8))
        }
        let result = try await client(host: host).campChanges(campId: UUID(), since: 3)
        #expect(result == .reload)
    }

    @Test func feedAsksWithSinceAndLimit() async throws {
        let host = host()
        StubProtocol.register(host: host) { _ in (200, [:], Data(#"{"eintraege":[],"bis":5,"weitere":false}"#.utf8)) }
        let result = try await client(host: host).campChanges(campId: UUID(), since: 5, limit: 200)
        guard case .page(let page) = result else { Issue.record("expected a page"); return }
        #expect(page.until == 5)
        let url = try #require(StubProtocol.requests(host: host).first?.url)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.contains(URLQueryItem(name: "seit", value: "5")) && query.contains(URLQueryItem(name: "limit", value: "200")))
    }

    @Test func otherFeedErrorsStayErrors() async {
        let host = host()
        StubProtocol.register(host: host) { _ in (404, [:], Data(#"{"code":"NICHT_GEFUNDEN","message":"Nicht gefunden."}"#.utf8)) }
        await #expect(throws: APIError.self) { try await client(host: host).campChanges(campId: UUID(), since: 0) }
    }

    @Test func closedCampHasItsOwnText() {
        let closed = APIError.from(status: 409, data: Data(#"{"code":"LAGER_GESCHLOSSEN","message":"x"}"#.utf8))
        #expect(CampRules.writeError(closed).contains("abgeschlossen"))
        let other = APIError.from(status: 409, data: Data(#"{"code":"ANDERES","message":"Anderer Text."}"#.utf8))
        #expect(CampRules.writeError(other) == "Anderer Text.")
    }
}
