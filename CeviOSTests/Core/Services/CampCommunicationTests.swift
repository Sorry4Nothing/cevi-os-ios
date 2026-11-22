import Foundation
import Testing
@testable import CeviOS

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder.api.decode(T.self, from: Data(json.utf8))
}

/// UUIDs inside a body are written upper case by Foundation; the server reads them case-insensitively.
private func lowered(_ value: Any?) -> [String]? { (value as? [String])?.map { $0.lowercased() } }

private let uuid1 = "0190a000-0000-7000-8000-000000000001"
private let uuid2 = "0190a000-0000-7000-8000-000000000002"
private let personJSON = #"{"id":"\#(uuid2)","name":"Pat Muster","ceviName":"Pinguin"}"#
private let agendaJSON = """
{"id":"\(uuid1)","version":2,"hoeckId":null,"titel":"Zeltplatz","text":null,"entscheid":null,"links":[{"titel":"Plan","url":"https://example.org/p"}],
 "reihenfolge":0,"aufgabeId":null,"status":"offen","verantwortliche":[\(personJSON)]}
"""
private let meetingJSON = """
{"id":"\(uuid1)","version":3,"art":"lagerleitung","datum":"2027-02-01","zeit":"19:30","titel":"Höck 1","ort":null,"gaeste":null,"protokollId":null,
 "anwesende":[\(personJSON)],"traktanden":[\(agendaJSON)]}
"""
private let fileJSON = """
{"id":"\(uuid2)","version":1,"anzeigename":"Protokoll.pdf","link":"https://example.org/f","typ":"application/pdf","groesse":1200,
 "hinzugefuegtVon":null,"hinzugefuegtAm":"2027-02-02T08:00:00Z"}
"""
private let protocolJSON = """
{"id":"\(uuid1)","version":4,"art":"sitzung","titel":"Protokoll Höck 1","datum":"2027-02-01","hoeckId":"\(uuid2)","dateiId":"\(uuid2)","datei":\(fileJSON),
 "erstelltAm":"2027-02-02T08:00:00Z","erstelltVon":null}
"""
private let resolutionJSON = #"{"id":"\#(uuid1)","version":1,"text":"Ort: Wald","protokollId":null,"hoeckId":null,"erstelltAm":"2027-02-02T08:00:00Z","erstelltVon":null}"#
private let mentionJSON = #"{"id":"\#(uuid1)","quelleTyp":"aufgabe","quelleId":"\#(uuid2)","titel":"Zelte","erledigt":false,"aufgabeId":null,"erstelltAm":"2027-02-02T08:00:00Z"}"#
private let pollJSON = """
{"id":"\(uuid1)","version":1,"mehrfach":false,"schliesstAm":null,"geschlossen":false,"namenFuerTeam":false,"namenSichtbar":false,"teilnehmende":3,
 "optionen":[{"id":"\(uuid2)","text":"Ja","stimmen":2,"eigene":true,"personen":[]}]}
"""
private let noticeJSON = """
{"id":"\(uuid1)","version":5,"titel":"Packliste","text":"Bitte lesen","wichtig":true,"angeheftet":false,"sichtbarAb":null,"sichtbarBis":"2027-07-01T00:00:00Z",
 "vonPersonId":"\(uuid2)","erstelltAm":"2027-02-02T08:00:00Z","von":\(personJSON),"empfaenger":{"anAlle":true,"rollen":[],"personen":[]},
 "dateien":[\(fileJSON)],"umfrage":\(pollJSON),"reaktionen":{"zaehler":{"herz":2,"neu":1},"eigene":"herz"}}
"""
private func inboxJSON(anonymous: Bool, from: String) -> String {
    """
    {"id":"\(uuid1)","version":1,"art":"feedback","text":"Super Lager","anonym":\(anonymous),"status":"neu","antwort":null,"beantwortetTag":null,
     "erstelltTag":"2027-02-02","ressortId":null,"traktandumId":null,"von":\(from)}
    """
}

struct CampCommunicationModelTests {
    @Test func meetingIsDecodedFullOrAsTeamView() throws {
        let full = try decode(CampMeetingView<CampMeeting>.self, meetingJSON)
        guard case .full(let meeting) = full else { Issue.record("expected the full view"); return }
        #expect(meeting.version == 3 && meeting.time == "19:30" && meeting.agenda.first?.links.first?.title == "Plan")
        #expect(meeting.attendees?.first?.ceviName == "Pinguin" && meeting.agenda.first?.meetingId == nil)
        let team = try decode(CampMeetingView<CampMeeting>.self, #"{"id":"\#(uuid1)","version":1,"datum":"2027-02-01","zeit":null,"titel":"Team-Höck","ort":"Wald"}"#)
        guard case .team(let view) = team else { Issue.record("expected the team view"); return }
        #expect(view.place == "Wald" && view.time == nil)
    }

    @Test func meetingPageMixesSummaryAndTeamEntries() throws {
        let page = try decode(CampMeetingPage.self, """
        {"hoecks":[{"id":"\(uuid1)","version":1,"art":"team","datum":"2027-02-01","zeit":null,"titel":"A","ort":null,"gaeste":null,"protokollId":null,
          "anzahlTraktanden":2,"anzahlAnwesende":5},
         {"id":"\(uuid2)","version":1,"datum":"2027-02-08","zeit":null,"titel":"B","ort":null}],"naechster":null}
        """)
        guard case .full(let summary) = page.meetings[0], case .team = page.meetings[1] else { Issue.record("wrong shapes"); return }
        #expect(summary.agendaCount == 2 && summary.attendeeCount == 5 && summary.kind == .team)
    }

    @Test func meetingModeIsDecodedWithoutAttendeesAndRound() throws {
        let mode = try decode(CampMeetingMode.self, """
        {"hoeck":{"id":"\(uuid1)","version":1,"art":"lagerleitung","datum":"2027-02-01","zeit":null,"titel":"H","ort":null,"gaeste":null,"protokollId":null,
          "traktanden":[\(agendaJSON)]},
         "mitglieder":[{"id":"\(uuid2)","name":null,"ceviName":"Pinguin","rolle":"team","anwesend":true}],
         "ressortRunde":[{"id":"\(uuid1)","kuerzel":"MAT","name":"Material","leitung":null,"aufgaben":{"gesamt":5,"erledigt":2,"offen":3,"ueberfaellig":1}},
                         {"id":"\(uuid2)","kuerzel":"MUS","name":"Musik","leitung":\(personJSON),"aufgaben":null}]}
        """)
        #expect(mode.meeting.attendees == nil && mode.members.first?.present == true && mode.members.first?.role == .team)
        #expect(mode.portfolioRound?.first?.tasks?.overdue == 1 && mode.portfolioRound?.last?.tasks == nil)
        let noRound = try decode(CampMeetingMode.self, #"{"hoeck":\#(meetingJSON),"mitglieder":[],"ressortRunde":null}"#)
        #expect(noRound.portfolioRound == nil)
    }

    @Test func agendaResultsAreDecoded() throws {
        #expect(try decode(CampAgendaAdopted.self, #"{"uebernommen":3}"#).adopted == 3)
        #expect(try decode(CampAgendaWaiting.self, #"{"traktanden":[\#(agendaJSON)]}"#).items.first?.status == .open)
        #expect(throws: DecodingError.self) { try decode(CampAgendaItem.self, agendaJSON.replacing("\"offen\"", with: "\"kaputt\"")) }
    }

    @Test func protocolCarriesVersionAndFileReference() throws {
        let item = try decode(CampProtocol.self, protocolJSON)
        #expect(item.version == 4 && item.kind == .meeting && item.file?.displayName == "Protokoll.pdf" && item.file?.id == item.fileId)
        let deletedFile = try decode(CampProtocolPage.self, #"{"protokolle":[\#(protocolJSON.replacing(fileJSON, with: "null"))],"naechster":null}"#)
        #expect(deletedFile.protocols.first?.file == nil)
    }

    @Test func protocolConflictShowsCurrentRowAndFields() throws {
        let error = APIError.from(status: 409, data: Data("""
        {"code":"VERSION_KONFLIKT","message":"Geändert.","aktuell":\(protocolJSON),"abweichend":["titel"]}
        """.utf8))
        let conflict = try #require(CampRules.versionConflict(error, as: CampProtocol.self))
        #expect(conflict.current?.version == 4 && conflict.differing == ["titel"])
    }

    @Test func resolutionAndMentionAreDecoded() throws {
        #expect(try decode(CampResolutionPage.self, #"{"beschluesse":[\#(resolutionJSON)],"naechster":null}"#).resolutions.first?.text == "Ort: Wald")
        let mention = try decode(CampMentionPage.self, #"{"erwaehnungen":[\#(mentionJSON)],"naechster":null}"#).mentions[0]
        #expect(mention.sourceKind == .task && !mention.done && mention.taskId == nil)
        let sync = try decode(CampMentionSync.self, #"{"personIds":["\#(uuid1)"],"neu":1}"#)
        #expect(sync.personIds.count == 1 && sync.new == 1)
    }

    @Test func noticeIsDecodedWithPollFilesAndReactions() throws {
        let notice = try decode(CampNotice.self, noticeJSON)
        #expect(notice.important && !notice.pinned && notice.visibleUntil != nil && notice.audience.everyone)
        #expect(notice.files.first?.link.absoluteString == "https://example.org/f" && notice.files.first?.size == 1200)
        #expect(notice.poll?.options.first?.own == true && notice.poll?.participants == 3)
        #expect(notice.reactions.counts == [.heart: 2] && notice.reactions.own == .heart) // an unknown key is skipped
        #expect(notice.author?.ceviName == "Pinguin")
        let plain = try decode(CampNotice.self, noticeJSON.replacing(pollJSON, with: "null").replacing("\"von\":\(personJSON)", with: "\"von\":null"))
        #expect(plain.poll == nil && plain.author == nil)
    }

    @Test func reactionsWithoutOwnAreDecoded() throws {
        let reactions = try decode(CampReactions.self, #"{"zaehler":{},"eigene":null}"#)
        #expect(reactions.counts.isEmpty && reactions.own == nil)
    }

    @Test func inboxEntryOfNamedSenderHasSender() throws {
        let entry = try decode(CampInboxEntry.self, inboxJSON(anonymous: false, from: personJSON))
        #expect(entry.sender?.ceviName == "Pinguin" && !entry.anonymous && entry.kind == .feedback)
    }

    @Test func anonymousInboxEntryNeverCarriesASenderName() throws {
        let clean = try decode(CampInboxEntry.self, inboxJSON(anonymous: true, from: "null"))
        #expect(clean.anonymous && clean.sender == nil)
        // Even if the server sent a name by mistake, the model drops it.
        let leaked = try decode(CampInboxEntry.self, inboxJSON(anonymous: true, from: personJSON))
        #expect(leaked.sender == nil)
        let page = try decode(CampInboxPage.self, #"{"eintraege":[\#(inboxJSON(anonymous: true, from: personJSON))],"naechster":null}"#)
        #expect(page.entries.first?.sender == nil)
    }

    @Test func inboxSentAnonymousHasCodeAndNoId() throws {
        let sent = try decode(CampInboxSent.self, """
        {"anonym":true,"rueckfragecode":"ABCD-EFGH-IJKL-MNOP-QRST","art":"idee","status":"neu","antwort":null,"beantwortetTag":null,"erstelltTag":"2027-02-02"}
        """)
        #expect(sent.anonymous && sent.id == nil && sent.followUpCode?.count == 24)
        let named = try decode(CampInboxSent.self, #"{"anonym":false,"id":"\#(uuid1)","art":"frage","status":"neu","antwort":null,"beantwortetTag":null,"erstelltTag":"2027-02-02"}"#)
        #expect(named.id != nil && named.followUpCode == nil)
    }

    @Test func ownInboxAndCodeViewAreDecoded() throws {
        let own = try decode(CampOwnInboxPage.self, """
        {"eintraege":[{"id":"\(uuid1)","art":"wunsch","text":"Mehr Pausen","status":"erledigt","antwort":"Ist notiert","beantwortetTag":"2027-02-03","erstelltTag":"2027-02-02"}],"naechster":null}
        """)
        #expect(own.entries.first?.reply == "Ist notiert" && own.entries.first?.status == .done)
        let view = try decode(CampInboxCodeView.self, #"{"art":"idee","status":"in_arbeit","antwort":null,"beantwortetTag":null,"erstelltTag":"2027-02-02"}"#)
        #expect(view.status == .inProgress)
    }
}

struct CampCommunicationBodyTests {
    private func json(_ value: some Encodable) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder.api.encode(value)) as? [String: Any])
    }

    @Test func agendaOrderSendsNullForTheListOfTheNextMeeting() throws {
        let body = try json(CampAgendaOrderBody(meetingId: nil, entries: [CampVersionRef(id: UUID(), version: 1)]))
        #expect(body["hoeckId"] is NSNull && (body["eintraege"] as? [Any])?.count == 1)
    }

    @Test func agendaPatchMovesAndClears() throws {
        let body = try json(CampAgendaItemPatch(version: 2, meetingId: .clear, decision: .set("Wald"), status: .discussed))
        #expect(Set(body.keys) == ["version", "hoeckId", "entscheid", "status"])
        #expect(body["hoeckId"] is NSNull && body["entscheid"] as? String == "Wald" && body["status"] as? String == "besprochen")
    }

    @Test func meetingBodiesUseCalendarDays() throws {
        let day = CampCalendarDay(DateFormats.calendarDay("2027-02-01")!)
        let create = try json(CampMeetingCreate(title: "H", kind: .team, date: day))
        #expect(Set(create.keys) == ["titel", "art", "datum"] && create["datum"] as? String == "2027-02-01")
        let patch = try json(CampMeetingPatch(version: 1, time: .clear))
        #expect(Set(patch.keys) == ["version", "zeit"] && patch["zeit"] is NSNull)
    }

    @Test func noticeBodyCarriesRecipientsFilesAndWindow() throws {
        let from = DateFormats.calendarDay("2027-02-01")!
        let create = try json(CampNoticeCreate(title: "T", important: true, visibleFrom: from, recipients: CampNoticeTarget(roles: [.team]), fileIds: [UUID()]))
        #expect(Set(create.keys) == ["titel", "wichtig", "sichtbarAb", "empfaenger", "dateiIds"])
        #expect((create["empfaenger"] as? [String: Any])?["rollen"] as? [String] == ["team"])
        let patch = try json(CampNoticePatch(version: 5, pinned: true, visibleUntil: .clear))
        #expect(Set(patch.keys) == ["version", "angeheftet", "sichtbarBis"] && patch["sichtbarBis"] is NSNull)
    }

    @Test func inboxBodiesUseTheServerNames() throws {
        let send = try json(CampInboxSend(kind: .idea, text: "x", anonymous: true))
        #expect(send["art"] as? String == "idee" && send["anonym"] as? Bool == true)
        let patch = try json(CampInboxPatch(version: 1, status: .inProgress, reply: .set("Danke"), portfolioId: .clear))
        #expect(Set(patch.keys) == ["version", "status", "antwort", "ressortId"] && patch["ressortId"] is NSNull)
    }

    @Test func filtersBuildTheQuery() {
        let id = UUID()
        let protocols = CampProtocolFilter(meetingId: id, kind: .note, search: "zelt").queryItems
        #expect(protocols.contains(URLQueryItem(name: "hoeckId", value: id.uuidString.lowercased())) && protocols.contains(URLQueryItem(name: "art", value: "notiz")))
        #expect(protocols.contains(URLQueryItem(name: "q", value: "zelt")))
        let inbox = CampInboxFilter(status: .new, kind: .question).queryItems
        #expect(inbox == [URLQueryItem(name: "status", value: "neu"), URLQueryItem(name: "art", value: "frage")])
    }
}

struct CampCommunicationServiceTests {
    private let camp = UUID(), id = UUID(), other = UUID()
    private var campPath: String { "/api/v1/lager/\(camp.uuidString.lowercased())" }
    private var idText: String { id.uuidString.lowercased() }
    private var otherText: String { other.uuidString.lowercased() }

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

    @Test func meetingRoutes() async throws {
        let day = DateFormats.calendarDay("2027-02-01")!
        var r = try await sent(#"{"hoecks":[],"naechster":null}"#) { _ = try await $0.campMeetings(campId: camp, from: day, to: day, after: other, limit: 5) }
        #expect(r.method == "GET" && r.path == campPath + "/hoecks" && r.query["von"] == "2027-02-01" && r.query["bis"] == "2027-02-01")
        #expect(r.query["limit"] == "5" && r.query["nach"] == otherText)
        r = try await sent(meetingJSON) { _ = try await $0.campMeeting(campId: camp, meetingId: id) }
        #expect(r.method == "GET" && r.path == campPath + "/hoecks/" + idText)
        let create = CampMeetingCreate(title: "H", kind: .campLeadership, date: CampCalendarDay(day), time: "19:30")
        r = try await sent(status: 201, meetingJSON) { _ = try await $0.createCampMeeting(campId: camp, create) }
        #expect(r.method == "POST" && r.path == campPath + "/hoecks" && r.body?["zeit"] as? String == "19:30" && r.body?["art"] as? String == "lagerleitung")
        r = try await sent(meetingJSON) { _ = try await $0.updateCampMeeting(campId: camp, meetingId: id, CampMeetingPatch(version: 3, title: "Neu")) }
        #expect(r.method == "PATCH" && r.path == campPath + "/hoecks/" + idText && r.body?["version"] as? Int == 3)
        r = try await sent(status: 204, "") { try await $0.deleteCampMeeting(campId: camp, meetingId: id, version: 3) }
        #expect(r.method == "DELETE" && r.query["version"] == "3")
        r = try await sent("BEGIN:VCALENDAR") { let value = try await $0.campMeetingCalendar(campId: camp, meetingId: id); #expect(value == Data("BEGIN:VCALENDAR".utf8)) }
        #expect(r.method == "GET" && r.path == campPath + "/hoecks/" + idText + ".ics")
    }

    @Test func meetingModeAndAttendanceRoutes() async throws {
        var r = try await sent(#"{"hoeck":\#(meetingJSON),"mitglieder":[],"ressortRunde":null}"#) { _ = try await $0.campMeetingMode(campId: camp, meetingId: id) }
        #expect(r.method == "GET" && r.path == campPath + "/hoecks/" + idText + "/modus")
        r = try await sent(status: 204, "") { try await $0.markCampMeetingPresent(campId: camp, meetingId: id, personId: other) }
        #expect(r.method == "PUT" && r.path == campPath + "/hoecks/" + idText + "/anwesende/" + otherText)
        r = try await sent(status: 204, "") { try await $0.unmarkCampMeetingPresent(campId: camp, meetingId: id, personId: other) }
        #expect(r.method == "DELETE" && r.path == campPath + "/hoecks/" + idText + "/anwesende/" + otherText)
        r = try await sent(#"{"uebernommen":2}"#) { let value = try await $0.adoptCampAgendaItems(campId: camp, meetingId: id, itemIds: [other]); #expect(value == 2) }
        #expect(r.method == "POST" && r.path == campPath + "/hoecks/" + idText + "/traktanden/uebernehmen" && lowered(r.body?["traktandumIds"]) == [otherText])
        r = try await sent(#"{"uebernommen":0}"#) { _ = try await $0.adoptCampAgendaItems(campId: camp, meetingId: id) }
        #expect(r.body?.isEmpty == true)
    }

    @Test func agendaRoutes() async throws {
        var r = try await sent(#"{"traktanden":[\#(agendaJSON)]}"#) { let value = try await $0.campWaitingAgendaItems(campId: camp).count; #expect(value == 1) }
        #expect(r.method == "GET" && r.path == campPath + "/traktanden/naechster")
        r = try await sent(status: 201, agendaJSON) { _ = try await $0.createCampAgendaItem(campId: camp, CampAgendaItemCreate(title: "Zeltplatz", responsibleIds: [other])) }
        #expect(r.method == "POST" && r.path == campPath + "/traktanden" && r.body?["titel"] as? String == "Zeltplatz")
        #expect(lowered(r.body?["verantwortlichePersonIds"]) == [otherText])
        r = try await sent(agendaJSON) { _ = try await $0.updateCampAgendaItem(campId: camp, itemId: id, CampAgendaItemPatch(version: 2, status: .discussed)) }
        #expect(r.method == "PATCH" && r.path == campPath + "/traktanden/" + idText && r.body?["status"] as? String == "besprochen")
        r = try await sent(status: 204, "") { try await $0.deleteCampAgendaItem(campId: camp, itemId: id, version: 2) }
        #expect(r.method == "DELETE" && r.query["version"] == "2")
        r = try await sent(status: 204, "") { try await $0.reorderCampAgenda(campId: camp, meetingId: nil, [CampVersionRef(id: id, version: 1)]) }
        #expect(r.method == "PUT" && r.path == campPath + "/traktanden/reihenfolge" && r.body?["hoeckId"] is NSNull)
    }

    @Test func protocolAndResolutionRoutes() async throws {
        var r = try await sent(#"{"protokolle":[],"naechster":null}"#) {
            _ = try await $0.campProtocols(campId: camp, filter: CampProtocolFilter(kind: .idea), limit: 10)
        }
        #expect(r.method == "GET" && r.path == campPath + "/protokolle" && r.query["art"] == "idee" && r.query["limit"] == "10")
        r = try await sent(protocolJSON) { _ = try await $0.campProtocol(campId: camp, protocolId: id) }
        #expect(r.path == campPath + "/protokolle/" + idText)
        let day = CampCalendarDay(DateFormats.calendarDay("2027-02-01")!)
        r = try await sent(status: 201, protocolJSON) { _ = try await $0.createCampProtocol(campId: camp, CampProtocolCreate(kind: .note, title: "T", date: day, fileId: other)) }
        #expect(r.method == "POST" && (r.body?["dateiId"] as? String)?.lowercased() == otherText && r.body?["datum"] as? String == "2027-02-01")
        r = try await sent(protocolJSON) { _ = try await $0.updateCampProtocol(campId: camp, protocolId: id, CampProtocolPatch(version: 4, meetingId: .clear)) }
        #expect(r.method == "PATCH" && r.path == campPath + "/protokolle/" + idText && r.body?["hoeckId"] is NSNull)
        r = try await sent(status: 204, "") { try await $0.deleteCampProtocol(campId: camp, protocolId: id, version: 4) }
        #expect(r.method == "DELETE" && r.query["version"] == "4")

        r = try await sent(#"{"beschluesse":[],"naechster":null}"#) { _ = try await $0.campResolutions(campId: camp, meetingId: id, protocolId: other) }
        #expect(r.path == campPath + "/beschluesse" && r.query["hoeckId"] == idText && r.query["protokollId"] == otherText)
        r = try await sent(resolutionJSON) { _ = try await $0.campResolution(campId: camp, resolutionId: id) }
        #expect(r.path == campPath + "/beschluesse/" + idText)
        r = try await sent(status: 201, resolutionJSON) { _ = try await $0.createCampResolution(campId: camp, CampResolutionCreate(text: "Wald")) }
        #expect(r.method == "POST" && r.body?["text"] as? String == "Wald")
        r = try await sent(resolutionJSON) { _ = try await $0.updateCampResolution(campId: camp, resolutionId: id, CampResolutionPatch(version: 1, text: "See")) }
        #expect(r.method == "PATCH" && r.path == campPath + "/beschluesse/" + idText)
        r = try await sent(status: 204, "") { try await $0.deleteCampResolution(campId: camp, resolutionId: id, version: 1) }
        #expect(r.method == "DELETE" && r.query["version"] == "1")
    }

    @Test func mentionRoutes() async throws {
        var r = try await sent(#"{"erwaehnungen":[],"naechster":null}"#) { _ = try await $0.campMentions(campId: camp, open: true) }
        #expect(r.method == "GET" && r.path == campPath + "/erwaehnungen" && r.query["offen"] == "true")
        r = try await sent(#"{"personIds":[],"neu":0}"#) { _ = try await $0.syncCampMentions(campId: camp, source: .agendaItem, sourceId: id) }
        #expect(r.method == "PUT" && r.path == campPath + "/erwaehnungen/traktandum/" + idText)
        r = try await sent(mentionJSON) { _ = try await $0.setCampMentionDone(campId: camp, mentionId: id, done: true) }
        #expect(r.method == "PATCH" && r.path == campPath + "/erwaehnungen/" + idText && r.body?["erledigt"] as? Bool == true)
        r = try await sent(status: 201, #"{"aufgabeId":"\#(uuid1)"}"#) { let value = try await $0.makeCampMentionTask(campId: camp, mentionId: id); #expect(value == UUID(uuidString: uuid1)) }
        #expect(r.method == "POST" && r.path == campPath + "/erwaehnungen/" + idText + "/als-aufgabe")
    }

    @Test func noticeRoutes() async throws {
        var r = try await sent(#"{"beitraege":[\#(noticeJSON)],"naechster":null}"#) { _ = try await $0.campNotices(campId: camp, scope: .all, limit: 5) }
        #expect(r.method == "GET" && r.path == campPath + "/pinnwand" && r.query["status"] == "alle" && r.query["limit"] == "5")
        r = try await sent(noticeJSON) { _ = try await $0.campNotice(campId: camp, noticeId: id) }
        #expect(r.path == campPath + "/pinnwand/" + idText)
        r = try await sent(status: 201, noticeJSON) { _ = try await $0.createCampNotice(campId: camp, CampNoticeCreate(title: "T", fileIds: [other])) }
        #expect(r.method == "POST" && r.path == campPath + "/pinnwand" && lowered(r.body?["dateiIds"]) == [otherText])
        r = try await sent(noticeJSON) { _ = try await $0.updateCampNotice(campId: camp, noticeId: id, CampNoticePatch(version: 5, pinned: true)) }
        #expect(r.method == "PATCH" && r.path == campPath + "/pinnwand/" + idText && r.body?["angeheftet"] as? Bool == true)
        r = try await sent(status: 204, "") { try await $0.deleteCampNotice(campId: camp, noticeId: id, version: 5) }
        #expect(r.method == "DELETE" && r.query["version"] == "5")
    }

    @Test func pollAndReactionRoutes() async throws {
        let base = campPath + "/pinnwand/" + idText + "/umfrage"
        var r = try await sent(status: 201, pollJSON) { _ = try await $0.createCampPoll(campId: camp, noticeId: id, CampPollCreate(options: ["Ja", "Nein"], multiple: true)) }
        #expect(r.method == "POST" && r.path == base && (r.body?["optionen"] as? [String]) == ["Ja", "Nein"] && r.body?["mehrfach"] as? Bool == true)
        r = try await sent(pollJSON) { _ = try await $0.updateCampPoll(campId: camp, noticeId: id, CampPollPatch(version: 1, closed: true)) }
        #expect(r.method == "PATCH" && r.path == base && r.body?["geschlossen"] as? Bool == true)
        r = try await sent(status: 204, "") { try await $0.deleteCampPoll(campId: camp, noticeId: id, version: 1) }
        #expect(r.method == "DELETE" && r.path == base && r.query["version"] == "1")
        r = try await sent(pollJSON) { _ = try await $0.voteCampPoll(campId: camp, noticeId: id, optionIds: [other]) }
        #expect(r.method == "PUT" && r.path == base + "/stimme" && lowered(r.body?["optionIds"]) == [otherText])
        r = try await sent(status: 204, "") { try await $0.withdrawCampPollVote(campId: camp, noticeId: id) }
        #expect(r.method == "DELETE" && r.path == base + "/stimme")
        r = try await sent(#"{"zaehler":{"danke":1},"eigene":"danke"}"#) { let value = try await $0.setCampReaction(campId: camp, targetId: id, .thanks).own; #expect(value == .thanks) }
        #expect(r.method == "PUT" && r.path == campPath + "/reaktionen/pinnwand_beitrag/" + idText && r.body?["emoji"] as? String == "danke")
        r = try await sent(status: 204, "") { try await $0.removeCampReaction(campId: camp, targetId: id) }
        #expect(r.method == "DELETE" && r.path == campPath + "/reaktionen/pinnwand_beitrag/" + idText)
    }

    @Test func handoutRoute() async throws {
        let r = try await sent("%PDF-1.4") { let value = try await $0.campHandout(campId: camp, .shiftPlan); #expect(value == Data("%PDF-1.4".utf8)) }
        #expect(r.method == "GET" && r.path == campPath + "/aushaenge/schichtplan")
        #expect(CampHandout.allCases.count == 6)
    }

    @Test func inboxRoutes() async throws {
        let entry = inboxJSON(anonymous: false, from: personJSON)
        var r = try await sent(#"{"eintraege":[],"naechster":null}"#) { _ = try await $0.campInbox(campId: camp, filter: CampInboxFilter(status: .new, kind: .wish)) }
        #expect(r.method == "GET" && r.path == campPath + "/eingang" && r.query["status"] == "neu" && r.query["art"] == "wunsch")
        r = try await sent(entry) { _ = try await $0.campInboxEntry(campId: camp, entryId: id) }
        #expect(r.path == campPath + "/eingang/" + idText)
        let reply = #"{"anonym":true,"rueckfragecode":"ABCD","art":"idee","status":"neu","antwort":null,"beantwortetTag":null,"erstelltTag":"2027-02-02"}"#
        r = try await sent(status: 201, reply) { _ = try await $0.sendCampInbox(campId: camp, CampInboxSend(kind: .idea, text: "x", anonymous: true)) }
        #expect(r.method == "POST" && r.path == campPath + "/eingang" && r.body?["anonym"] as? Bool == true)
        r = try await sent(#"{"eintraege":[],"naechster":null}"#) { _ = try await $0.campOwnInbox(campId: camp, after: other) }
        #expect(r.method == "GET" && r.path == campPath + "/eingang/eigene" && r.query["nach"] == otherText)
        r = try await sent(#"{"art":"idee","status":"neu","antwort":null,"beantwortetTag":null,"erstelltTag":"2027-02-02"}"#) { _ = try await $0.campInboxStatus(campId: camp, code: "ABCD") }
        #expect(r.method == "POST" && r.path == campPath + "/eingang/status" && r.body?["code"] as? String == "ABCD" && r.query.isEmpty)
        r = try await sent(entry) { _ = try await $0.updateCampInboxEntry(campId: camp, entryId: id, CampInboxPatch(version: 1, status: .done)) }
        #expect(r.method == "PATCH" && r.path == campPath + "/eingang/" + idText && r.body?["status"] as? String == "erledigt")
        r = try await sent(status: 204, "") { try await $0.deleteCampInboxEntry(campId: camp, entryId: id, version: 1) }
        #expect(r.method == "DELETE" && r.query["version"] == "1")
        r = try await sent(status: 201, entry) { _ = try await $0.makeCampInboxAgendaItem(campId: camp, entryId: id, CampInboxToAgenda(version: 1, title: "Idee")) }
        #expect(r.method == "POST" && r.path == campPath + "/eingang/" + idText + "/traktandum" && r.body?["titel"] as? String == "Idee")
    }
}
