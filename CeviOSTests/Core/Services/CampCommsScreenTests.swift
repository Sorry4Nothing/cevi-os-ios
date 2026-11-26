import Foundation
import Testing
@testable import CeviOS

private nonisolated func uid(_ n: Int) -> String { "0190a000-0000-7000-8000-0000000008\(String(format: "%02d", n))" }
private nonisolated let campUUID = UUID(uuidString: "0190a000-0000-7000-8000-000000000001")!

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

private func freshHost() -> String { host() }
private func host() -> String { "a\(UUID().uuidString.prefix(8).lowercased()).test.example.org" }

private func stub(_ host: String, _ handler: @escaping @Sendable (URLRequest) -> (Int, String)) {
    StubProtocol.register(host: host) { request in
        let (status, body) = handler(request)
        return (status, [:], Data(body.utf8))
    }
}

private nonisolated func body(_ request: URLRequest) -> String { StubProtocol.body(of: request).map { String(decoding: $0, as: UTF8.self) } ?? "" }

private nonisolated func noticeJSON(_ n: Int, pinned: Bool = false, important: Bool = false, created: String = "2027-05-20T08:00:00Z", poll: String = "null", own: String = "null") -> String {
    """
    {"id":"\(uid(n))","version":1,"titel":"Mitteilung \(n)","text":"Text","wichtig":\(important),"angeheftet":\(pinned),"sichtbarAb":null,"sichtbarBis":null,
     "vonPersonId":null,"erstelltAm":"\(created)","von":null,"empfaenger":{"anAlle":true,"rollen":[],"personen":[]},"dateien":[],"umfrage":\(poll),
     "reaktionen":{"zaehler":{"daumen":2},"eigene":\(own)}}
    """
}

private nonisolated func pollJSON(multiple: Bool = false, closed: Bool = false, ownFirst: Bool = false) -> String {
    """
    {"id":"\(uid(40))","version":1,"mehrfach":\(multiple),"schliesstAm":null,"geschlossen":\(closed),"namenFuerTeam":false,"namenSichtbar":false,"teilnehmende":3,
     "optionen":[{"id":"\(uid(41))","text":"Schwimmen","stimmen":2,"eigene":\(ownFirst),"personen":[]},{"id":"\(uid(42))","text":"Wanderung","stimmen":1,"eigene":false,"personen":[]}]}
    """
}

@MainActor
struct CampNoticesModelTests {
    @Test func pinnedAndImportantComeFirstAndEditorsAskForAll() async throws {
        let host = host()
        stub(host) { _ in (200, #"{"beitraege":[\#(noticeJSON(1, created: "2027-05-22T08:00:00Z")),\#(noticeJSON(2, important: true)),\#(noticeJSON(3, pinned: true, created: "2027-01-01T08:00:00Z"))],"naechster":null}"#) }
        let model = CampNoticesModel(active: try active(host: host))
        await model.load()
        #expect(model.sorted.map(\.title) == ["Mitteilung 3", "Mitteilung 2", "Mitteilung 1"])
        #expect(StubProtocol.requests(host: host).first?.url?.query?.contains("status=alle") == true)
        let teamHost = freshHost()
        stub(teamHost) { _ in (200, #"{"beitraege":[],"naechster":null}"#) }
        await CampNoticesModel(active: try active(.team, host: teamHost)).load()
        #expect(StubProtocol.requests(host: teamHost).first?.url?.query?.contains("status=aktiv") == true)
    }

    @Test func votingSendsTheOptionAndTheSameOptionWithdraws() async throws {
        let host = host()
        stub(host) { request in
            switch request.httpMethod {
            case "PUT": (200, pollJSON(ownFirst: true))
            case "DELETE": (204, "")
            default: (200, noticeJSON(1, poll: pollJSON()))
            }
        }
        let model = CampNoticesModel(active: try active(.team, host: host))
        let notice = try JSONDecoder.api.decode(CampNotice.self, from: Data(noticeJSON(1, poll: pollJSON()).utf8))
        await model.vote(notice, option: try #require(notice.poll?.options.first))
        let put = try #require(StubProtocol.requests(host: host).first { $0.httpMethod == "PUT" })
        #expect(put.url?.path.hasSuffix("/pinnwand/\(uid(1))/umfrage/stimme") == true && body(put).lowercased().contains(uid(41)))
        let voted = try JSONDecoder.api.decode(CampNotice.self, from: Data(noticeJSON(1, poll: pollJSON(ownFirst: true)).utf8))
        await model.vote(voted, option: try #require(voted.poll?.options.first))
        #expect(StubProtocol.requests(host: host).contains { $0.httpMethod == "DELETE" && $0.url?.path.hasSuffix("/umfrage/stimme") == true })
    }

    @Test func readersAndClosedPollsTakeNoVotesOrReactions() async throws {
        let host = host()
        stub(host) { _ in (200, "{}") }
        let notice = try JSONDecoder.api.decode(CampNotice.self, from: Data(noticeJSON(1, poll: pollJSON(closed: true)).utf8))
        let reader = CampNoticesModel(active: try active(.readOnly, host: host))
        await reader.vote(notice, option: notice.poll!.options[0])
        await reader.react(notice, .heart)
        let team = CampNoticesModel(active: try active(.team, host: host))
        await team.vote(notice, option: notice.poll!.options[0])
        #expect(StubProtocol.requests(host: host).isEmpty)
        #expect(!team.rights.editsNotices)
    }

    @Test func sameReactionAgainTakesItBack() async throws {
        let host = host()
        stub(host) { request in request.httpMethod == "DELETE" ? (204, "") : (200, noticeJSON(1)) }
        let model = CampNoticesModel(active: try active(host: host))
        let notice = try JSONDecoder.api.decode(CampNotice.self, from: Data(noticeJSON(1, own: "\"herz\"").utf8))
        await model.react(notice, .heart)
        #expect(StubProtocol.requests(host: host).first?.httpMethod == "DELETE")
    }

    @Test func pinSendsTheVersion() async throws {
        let host = host()
        stub(host) { _ in (200, noticeJSON(1, pinned: true)) }
        let model = CampNoticesModel(active: try active(host: host))
        let notice = try JSONDecoder.api.decode(CampNotice.self, from: Data(noticeJSON(1).utf8))
        await model.setFlags(notice, pinned: true)
        let patch = try #require(StubProtocol.requests(host: host).first)
        #expect(patch.httpMethod == "PATCH" && body(patch).contains("\"angeheftet\":true") && body(patch).contains("\"version\":1"))
    }
}

@MainActor
struct CampNoticeFormModelTests {
    @Test func pollNeedsTwoDifferentOptions() throws {
        let model = CampNoticeFormModel(active: try active(host: host()))
        #expect(model.pollProblem == nil) // no options, no poll
        model.options = ["Schwimmen", ""]
        #expect(model.pollProblem == "Eine Umfrage braucht mindestens zwei Optionen.")
        model.options = ["Schwimmen", "schwimmen"]
        #expect(model.pollProblem != nil)
        model.options = ["Schwimmen", "Wanderung"]
        #expect(model.pollProblem == nil && model.hasPoll)
    }

    @Test func publishMakesTheNoticeThenThePollAndRetriesOnlyThePoll() async throws {
        let host = host()
        let pollFails = LockedFlag()
        stub(host) { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/umfrage") { return pollFails.value ? (500, #"{"code":"X","message":"Fehler"}"#) : (201, pollJSON()) }
            return (201, noticeJSON(1))
        }
        pollFails.value = true
        let model = CampNoticeFormModel(active: try active(host: host))
        model.title = "Welcher Ausflug?"
        model.options = ["Schwimmen", "Wanderung"]
        model.roles = [.leadership]
        #expect(await !model.publish() && model.saveError != nil)
        pollFails.value = false
        #expect(await model.publish() && model.isDone)
        let posts = StubProtocol.requests(host: host).filter { $0.httpMethod == "POST" }
        #expect(posts.filter { $0.url?.path.hasSuffix("/pinnwand") == true }.count == 1)
        #expect(posts.filter { $0.url?.path.hasSuffix("/umfrage") == true }.count == 2)
        #expect(body(posts[0]).contains("\"leitung\""))
    }

    @Test func emptyTitleAndInputFromTheServerShowAnError() async throws {
        let host = host()
        stub(host) { _ in (400, #"{"code":"UNGUELTIGE_EINGABE","message":"Titel zu lang."}"#) }
        let model = CampNoticeFormModel(active: try active(host: host))
        #expect(await !model.publish() && model.inputError != nil)
        model.title = "X"
        #expect(await !model.publish() && model.inputError == "Titel zu lang.")
    }
}

private nonisolated final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var value: Bool { get { lock.withLock { flag } } set { lock.withLock { flag = newValue } } }
}

@MainActor
struct CampInboxModelTests {
    private nonisolated static func entry(_ n: Int, anonymous: Bool, kind: String = "feedback", agenda: Bool = false) -> String {
        """
        {"id":"\(uid(n))","version":1,"art":"\(kind)","text":"Text \(n)","anonym":\(anonymous),"status":"neu","antwort":null,"beantwortetTag":null,"erstelltTag":"2027-05-22",
         "ressortId":null,"traktandumId":\(agenda ? "\"\(uid(60))\"" : "null"),"von":{"id":"\(uid(70))","name":"Jonas","ceviName":"Fuchs"}}
        """
    }

    @Test func anonymousEntryNeverShowsAName() async throws {
        let host = host()
        stub(host) { request in
            request.url?.path.hasSuffix("/ressorts") == true ? (200, #"{"ressorts":[],"naechster":null}"#) : (200, #"{"eintraege":[\#(Self.entry(1, anonymous: true)),\#(Self.entry(2, anonymous: false, kind: "frage"))],"naechster":null}"#)
        }
        let model = CampInboxModel(active: try active(host: host))
        model.now = { DateFormats.calendarDay("2027-05-23")! }
        await model.load()
        let anonymous = try #require(model.entries.first { $0.anonymous })
        #expect(anonymous.sender == nil)
        #expect(model.sender(anonymous) == "anonym, gestern" && !model.sender(anonymous).contains("Jonas"))
        #expect(model.sender(try #require(model.entries.first { !$0.anonymous })) == "Jonas (Fuchs), gestern")
        #expect(CampInboxModel.kindName(.question) == "Rückfrage")
    }

    @Test func onlyTheCampLeadReadsAndAnswers() async throws {
        let host = host()
        stub(host) { _ in (200, "{}") }
        let leader = CampInboxModel(active: try active(.leader, host: host))
        await leader.load()
        if case .failed(let state, _) = leader.phase { #expect(state == .noAccess) } else { Issue.record("expected failure") }
        #expect(StubProtocol.requests(host: host).isEmpty)
        let closed = CampInboxModel(active: try active(status: "abgeschlossen", host: host))
        #expect(!closed.canAnswer)
    }

    @Test func replyAndAgendaItemSendTheVersion() async throws {
        let host = host()
        stub(host) { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/traktandum") { return (200, Self.entry(1, anonymous: true, agenda: true)) }
            if request.httpMethod == "PATCH" { return (200, Self.entry(1, anonymous: true)) }
            if path.hasSuffix("/ressorts") { return (200, #"{"ressorts":[],"naechster":null}"#) }
            return (200, #"{"eintraege":[\#(Self.entry(1, anonymous: true))],"naechster":null}"#)
        }
        let model = CampInboxModel(active: try active(host: host))
        await model.load()
        let item = model.entries[0]
        #expect(await model.reply(item, text: "  Danke  "))
        let patch = try #require(StubProtocol.requests(host: host).first { $0.httpMethod == "PATCH" })
        #expect(body(patch).contains("\"antwort\":\"Danke\"") && body(patch).contains("\"version\":1"))
        await model.makeAgendaItem(item)
        #expect(model.notice?.title == "Als Traktandum übernommen." && model.hasUndo && model.entries[0].agendaItemId != nil)
    }
}

@MainActor
struct CampMentionsAndNotificationsTests {
    private nonisolated static func mention(_ n: Int, done: Bool = false, task: Bool = false) -> String {
        """
        {"id":"\(uid(n))","titel":"@Tim fragt nach","quelleTyp":"pinnwand","quelleId":"\(uid(80))","erledigt":\(done),"aufgabeId":\(task ? "\"\(uid(81))\"" : "null"),"erstelltAm":"2027-05-21T08:00:00Z"}
        """
    }

    @Test func mentionBecomesATaskAndIsMarkedDone() async throws {
        let host = host()
        stub(host) { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/als-aufgabe") { return (201, #"{"aufgabeId":"\#(uid(81))"}"#) }
            if request.httpMethod == "PATCH" { return (200, Self.mention(1, done: true)) }
            return (200, #"{"erwaehnungen":[\#(Self.mention(1)),\#(Self.mention(2, done: true))],"naechster":null}"#)
        }
        let model = CampMentionsModel(active: try active(host: host))
        model.now = { DateFormats.calendarDay("2027-05-22")! }
        await model.load()
        #expect(model.open.count == 1 && model.done.count == 1 && model.caption(model.open[0]) == "Erwähnt auf der Pinnwand, gestern")
        await model.makeTask(model.open[0])
        #expect(model.notice?.title == "Als Aufgabe angelegt.")
        await model.setDone(model.open[0], true)
        let patch = try #require(StubProtocol.requests(host: host).first { $0.httpMethod == "PATCH" })
        #expect(body(patch).contains("\"erledigt\":true"))
    }

    @Test func closedCampTakesNoMentionChange() async throws {
        let host = host()
        stub(host) { _ in (200, #"{"erwaehnungen":[\#(Self.mention(1))],"naechster":null}"#) }
        let model = CampMentionsModel(active: try active(status: "abgeschlossen", host: host))
        await model.load()
        await model.makeTask(model.open[0])
        await model.setDone(model.open[0], true)
        #expect(StubProtocol.requests(host: host).count == 1 && !model.canWrite)
    }

    @Test func notificationsAreReadOneByOneAndTextComesFromTheKind() async throws {
        let host = host()
        stub(host) { request in
            request.httpMethod == "POST" ? (204, "") : (200, #"{"eintraege":[{"id":"\#(uid(1))","art":"erwaehnung","objektTyp":"aufgabe","objektId":"\#(uid(2))","gelesen":false,"erstelltAm":"2027-05-22T08:00:00Z"},{"id":"\#(uid(3))","art":"neue_art","objektTyp":"x","objektId":"\#(uid(2))","gelesen":true,"erstelltAm":"2027-05-21T08:00:00Z"}],"naechster":null}"#)
        }
        let model = CampNotificationsModel(active: try active(host: host))
        await model.load()
        #expect(model.unread.count == 1 && model.read.count == 1 && model.read[0].kind == .unknown)
        #expect(CampNotificationsModel.title(.mention) == "Erwähnung" && CampNotificationsModel.message(.unknown) == "Es gibt etwas Neues im Lager.")
        await model.markRead(model.unread[0])
        let post = try #require(StubProtocol.requests(host: host).first { $0.httpMethod == "POST" })
        #expect(post.url?.path.hasSuffix("/benachrichtigungen/gelesen") == true && body(post).lowercased().contains(uid(1)))
    }

    @Test func switchGoesBackWhenTheServerRefuses() async throws {
        let host = host()
        stub(host) { request in
            request.httpMethod == "PUT" ? (500, #"{"code":"X","message":"Fehler"}"#) : (200, #"{"arten":[{"art":"erwaehnung","aktiv":true}]}"#)
        }
        let model = CampNotificationsModel(active: try active(host: host))
        await model.loadSettings()
        #expect(model.settings == [.init(kind: .mention, enabled: true)])
        await model.set(.mention, enabled: false)
        #expect(model.settings[0].enabled && model.error != nil)
    }
}

@MainActor
struct CampPushDestinationTests {
    @Test func pushOpensTheMatchingScreen() async throws {
        let host = host()
        stub(host) { request in
            let path = request.url?.path ?? ""
            if path.contains("/aufloesen/") { return (200, #"{"lagerId":"\#(campUUID.uuidString)","objektTyp":"x","objektId":"\#(uid(1))"}"#) }
            if path == "/api/v1/lager" { return (200, #"{"lager":[{"id":"\#(campUUID.uuidString)","titel":"L","von":"2027-07-10","bis":"2027-07-17","vorbereitungAb":null,"ort":null,"adresse":null,"status":"aktiv","farbe":null,"logoMediumId":null,"wetterOrt":{"status":"kein_ort","name":null},"rolle":"lagerleitung"}]}"#) }
            return (404, "{}")
        }
        let client = APIClient(baseURL: URL(string: "https://\(host)")!, appVersion: "1.0.0", cookieStore: InMemoryCookieStore(["s": "1"]),
                               session: APIClient.makeSession(protocolClasses: [StubProtocol.self]))
        let camp = ActiveCamp()
        _ = await CampRouter.open(type: .notice, objectId: UUID(), client: client, list: CampListModel(), active: camp)
        #expect(camp.destination == .notices)
        _ = await CampRouter.open(type: .mention, objectId: UUID(), client: client, list: CampListModel(), active: camp)
        #expect(camp.destination == .mentions)
        _ = await CampRouter.open(type: .feedback, objectId: UUID(), client: client, list: CampListModel(), active: camp)
        #expect(camp.destination == .inbox)
        _ = await CampRouter.open(type: .task, objectId: UUID(), client: client, list: CampListModel(), active: camp)
        #expect(camp.destination == nil)
    }
}
