import Foundation
import Testing
@testable import CeviOS

private nonisolated let campUUID = UUID(uuidString: "0190a000-0000-7000-8000-000000000001")!
private nonisolated let campPath = "/api/v1/lager/\(campUUID.uuidString.lowercased())"
private nonisolated let meUUID = UUID(uuidString: "0190a000-0000-7000-8000-0000000000aa")!

@MainActor
private func active(_ role: CampRole = .campLeader, status: String = "aktiv", host: String) throws -> ActiveCamp {
    let json = """
    {"id":"\(campUUID.uuidString)","titel":"Sommerlager","von":"2027-07-17","bis":"2027-07-24","vorbereitungAb":null,"ort":null,
     "adresse":null,"status":"\(status)","farbe":null,"logoMediumId":null}
    """
    let client = APIClient(baseURL: URL(string: "https://\(host)")!, appVersion: "1.0.0", cookieStore: InMemoryCookieStore(["s": "1"]),
                           session: APIClient.makeSession(protocolClasses: [StubProtocol.self]))
    let active = ActiveCamp()
    active.open(camp: try JSONDecoder.api.decode(Camp.self, from: Data(json.utf8)), role: role, client: client)
    return active
}

private func host() -> String { "r\(UUID().uuidString.prefix(8).lowercased()).test.example.org" }
private func freshHost() -> String { host() }

private func stub(_ host: String, _ handler: @escaping @Sendable (URLRequest) -> (Int, String)) {
    StubProtocol.register(host: host) { request in
        let (status, body) = handler(request)
        return (status, [:], Data(body.utf8))
    }
}

private nonisolated func body(_ request: URLRequest) -> String { StubProtocol.body(of: request).map { String(decoding: $0, as: UTF8.self) } ?? "" }
private nonisolated func uid(_ n: Int) -> String { "0190a000-0000-7000-8000-0000000099\(String(format: "%02d", n))" }

struct CampRosterRightsTests {
    @Test func rolesGetTheirActions() {
        func rights(_ role: CampRole, readOnly: Bool = false) -> CampRosterRights { CampRosterRights(role: role, readOnly: readOnly) }
        #expect(rights(.campLeader).placesPeople && rights(.campLeader).decidesSwaps && rights(.campLeader).resets && rights(.campLeader).seesAllSwaps)
        #expect(!rights(.leader).placesPeople && rights(.leader).editsShifts && rights(.leader).resets && rights(.leader).isLockedByRole)
        #expect(rights(.team).ticks && rights(.team).requestsSwaps && !rights(.team).editsShifts && !rights(.team).resets)
        #expect(!rights(.readOnly).ticks && !rights(.readOnly).requestsSwaps && !rights(.readOnly).editsShifts)
        let closed = rights(.campLeader, readOnly: true)
        #expect(!closed.placesPeople && !closed.editsShifts && !closed.decidesSwaps && !closed.ticks && !closed.isLockedByRole)
    }

    @Test func textsNeverInventNames() {
        #expect(CampRosterText.label(name: "Mara", ceviName: "Luchs") == "Mara (Luchs)")
        #expect(CampRosterText.label(name: nil, ceviName: nil) == "Person" && CampRosterText.label(name: " ", ceviName: "Luchs") == "Luchs")
        #expect(CampRosterText.summary(["Mara", "Lea", "Jonas", "Sina", "Tim"]) == "Mara, Lea, Jonas und 2 weitere")
        #expect(CampRosterText.summary(["Mara", "Lea"]) == "Mara und Lea" && CampRosterText.summary([]) == "")
        #expect(CampRosterText.initials("Mara") == "MA" && CampRosterText.initials("Jonas Brun") == "JB")
        #expect(CampRosterText.children(1) == "1 Kind" && CampRosterText.children(12) == "12 Kinder")
        #expect(CampRosterText.dayChip(DateFormats.calendarDay("2027-07-19")!).hasSuffix("19."))
    }
}

@MainActor
struct CampRoomsModelTests {
    private nonisolated static let listJSON = """
    {"zimmer":[{"id":"\(uid(1))","version":2,"name":"Zimmer Adler","art":"zimmer","plaetze":2,"notiz":"1. Stock","reihenfolge":1,"belegt":2,"ueberbelegt":false,
                "mitglieder":[{"typ":"person","id":"\(uid(2))","name":"Mara"},{"typ":"teilnehmer","id":"\(uid(3))","name":"Kim"}]}],
     "offen":{"teilnehmer":2,"team":1}}
    """
    private nonisolated static let teamJSON = """
    {"zimmer":[{"id":"\(uid(1))","version":2,"name":"Zelt 3","art":"zelt","mitglieder":[{"name":"Noa"}]}]}
    """

    @Test func loadsBothShapes() async throws {
        let host = host()
        stub(host) { _ in (200, Self.listJSON) }
        let model = CampRoomsModel(active: try active(host: host))
        await model.load()
        #expect(model.phase == .loaded && model.openCount == 3 && model.rows[0].isFull && model.rows[0].detail == "Zimmer, 1. Stock")
        let teamHost = freshHost()
        stub(teamHost) { _ in (200, Self.teamJSON) }
        let team = CampRoomsModel(active: try active(.team, host: teamHost))
        await team.load()
        #expect(team.rows[0].places == nil && team.rows[0].members.map(\.name) == ["Noa"] && !team.rights.placesPeople)
    }

    @Test func placingSendsTheRightIdsAndRemovingNeedsTheKind() async throws {
        let host = host()
        stub(host) { request in
            request.httpMethod == "POST" ? (200, #"{"eingeteilt":2,"belegt":3,"plaetze":2,"ueberbelegt":true}"#) : (200, Self.listJSON)
        }
        let model = CampRoomsModel(active: try active(host: host))
        await model.load()
        let people = [CampPersonChoice(id: UUID(uuidString: uid(5))!, isParticipant: true, label: "Lou"), CampPersonChoice(id: UUID(uuidString: uid(6))!, isParticipant: false, label: "Lea")]
        await model.place(people, in: UUID(uuidString: uid(1))!)
        let post = try #require(StubProtocol.requests(host: host).first { $0.httpMethod == "POST" })
        #expect(post.url?.path == "\(campPath)/zimmer/\(uid(1))/zuordnung" && body(post).contains("teilnehmerIds") && body(post).contains("personIds"))
        #expect(model.notice?.message?.contains("überbelegt") == true)
        await model.remove(model.rows[0].members[0], from: model.rows[0].id)
        let removal = try #require(StubProtocol.requests(host: host).last { $0.httpMethod == "POST" })
        #expect(removal.url?.path.hasSuffix("/zuordnung/entfernen") == true && body(removal).contains("personIds") && !body(removal).contains("teilnehmerIds"))
    }

    @Test func nonLeadsPlaceNothing() async throws {
        let host = host()
        stub(host) { _ in (200, Self.listJSON) }
        let model = CampRoomsModel(active: try active(.leader, host: host))
        await model.load()
        await model.place([CampPersonChoice(id: UUID(), isParticipant: false, label: "X")], in: model.rows[0].id)
        #expect(StubProtocol.requests(host: host).allSatisfy { $0.httpMethod == "GET" })
    }
}

@MainActor
struct CampTripsAndGroupsTests {
    private nonisolated static let tripsJSON = """
    {"fahrten":[
     {"id":"\(uid(11))","version":1,"richtung":"hin","art":"auto","plaetze":5,"datum":"2027-07-17","zeit":"07:30","treffpunkt":"Eingang Nord","link":"https://example.org/x",
      "fahrer":{"personId":"\(uid(12))","name":"Jonas"},"mitfahrer":[{"id":"\(uid(13))","version":3,"personId":"\(uid(14))","teilnehmerId":null,"name":"Lea","stufe":null}],"belegt":1,"frei":4,"ueberbelegt":false},
     {"id":"\(uid(15))","version":1,"richtung":"rueck","art":"oev","datum":null,"zeit":null,"link":"http://insecure.example.org","mitfahrer":[],"belegt":12,"ueberbelegt":false}],"naechster":null}
    """

    @Test func tripTextsAndDirection() async throws {
        let host = host()
        stub(host) { _ in (200, Self.tripsJSON) }
        let model = CampTripsModel(active: try active(host: host))
        await model.load()
        let car = try #require(model.visible.first)
        #expect(CampTripText.title(car) == "Auto von Jonas" && CampTripText.count(car) == "1 von 5" && CampTripText.departure(car)?.hasPrefix("Abfahrt ") == true)
        #expect(CampTripText.link(car) != nil)
        model.direction = .inbound
        let train = try #require(model.visible.first)
        #expect(CampTripText.title(train) == "ÖV-Gruppe" && CampTripText.count(train) == "12 Personen" && CampTripText.link(train) == nil && CampTripText.departure(train) == nil)
    }

    @Test func boardingAndRemovingSendTheRows() async throws {
        let host = host()
        stub(host) { request in
            if request.httpMethod == "POST" { return (200, #"{"id":"\#(uid(20))","version":1,"fahrtId":"\#(uid(11))","personId":"\#(uid(21))","teilnehmerId":null,"belegt":2,"plaetze":5,"ueberbelegt":false}"#) }
            if request.httpMethod == "DELETE" { return (204, "") }
            return (200, Self.tripsJSON)
        }
        let model = CampTripsModel(active: try active(host: host))
        await model.load()
        await model.board([CampPersonChoice(id: UUID(uuidString: uid(21))!, isParticipant: false, label: "Tim")], on: UUID(uuidString: uid(11))!)
        #expect(StubProtocol.requests(host: host).contains { $0.httpMethod == "POST" && $0.url?.path.hasSuffix("/fahrten/\(uid(11))/mitfahrer") == true })
        await model.remove(model.trips[0].passengers[0], from: model.trips[0].id)
        let delete = try #require(StubProtocol.requests(host: host).first { $0.httpMethod == "DELETE" })
        #expect(delete.url?.query?.contains("version=3") == true)
    }

    @Test func shuffleIsASuggestionFirstAndConfirmedWithTheSameSeed() async throws {
        let host = host()
        stub(host) { request in
            let text = body(request)
            if request.httpMethod == "POST" {
                return (200, #"{"vorschau":\#(text.contains("true") ? "false" : "true"),"seed":42,"geaendert":\#(text.contains("true") ? "20" : "null"),"gruppen":[{"nummer":1,"gruppeId":null,"name":"A","anzahl":10,"teilnehmer":[]},{"nummer":2,"gruppeId":null,"name":"B","anzahl":10,"teilnehmer":[]}]}"#)
            }
            return (200, #"{"gruppen":[],"ohneGruppe":0,"abgewaehlt":0}"#)
        }
        let model = CampGroupsModel(active: try active(host: host))
        await model.load()
        model.beginShuffle()
        #expect(model.shuffleCount == 2)
        await model.suggest()
        #expect(model.suggestion?.preview == true)
        #expect(await model.confirm())
        let posts = StubProtocol.requests(host: host).filter { $0.httpMethod == "POST" }
        #expect(posts.count == 2 && body(posts[0]).contains("\"uebernehmen\":false") && body(posts[1]).contains("\"uebernehmen\":true") && body(posts[1]).contains("\"seed\":42"))
        #expect(model.suggestion == nil && model.notice?.title == "Gruppen gemischt.")
    }

    @Test func onlyTheCampLeadershipMixes() async throws {
        let host = host()
        stub(host) { _ in (200, #"{"gruppen":[],"ohneGruppe":0,"abgewaehlt":0}"#) }
        let model = CampGroupsModel(active: try active(.leader, host: host))
        await model.suggest()
        #expect(model.suggestion == nil && StubProtocol.requests(host: host).isEmpty)
    }
}

@MainActor
struct CampSwapsAndCountTests {
    @Test func swapRowsTellWhoAndWhat() throws {
        let host = host()
        let model = CampSwapsModel(active: try active(host: host), personId: meUUID)
        model.context = CampRosterPreview.context()
        let open = CampRosterPreview.swapSample(open: true)
        model.swaps = [open]
        let row = try #require(model.rows.first)
        #expect(row.title == "Küche Sonntag Frühstück" && row.text == "Jonas möchte Küche Sonntag mit Lea tauschen." && row.second == "Lea macht dafür Abwasch Montag.")
        #expect(row.canDecide && model.canReject(row) && !row.canWithdraw)
    }

    @Test func decideAndWithdrawSendVersions() async throws {
        let host = host()
        let accepted = CampRosterPreview.swapJSON(open: false)
        stub(host) { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/diensttausch") { return (200, #"{"tausche":[],"naechster":null}"#) }
            if path.hasSuffix("/schichtplan") { return (200, #"{"dienste":[],"schichten":[],"statistik":[]}"#) }
            if path.hasSuffix("/zeitplan") { return (200, #"{"meilensteine":[],"lagertage":[],"tagesabschnitte":[]}"#) }
            return (200, accepted)
        }
        let model = CampSwapsModel(active: try active(host: host), personId: meUUID)
        model.context = CampRosterPreview.context()
        model.swaps = [CampRosterPreview.swapSample(open: true)]
        await model.decide(try #require(model.rows.first), .accepted)
        let post = try #require(StubProtocol.requests(host: host).first { $0.httpMethod == "POST" })
        #expect(post.url?.path.hasSuffix("/entscheid") == true && body(post).contains("\"entscheid\":\"angenommen\"") && body(post).contains("\"version\":1"))
        #expect(model.notice?.title == "Tausch angenommen.")
        // The team reads only the own requests.
        let teamHost = freshHost()
        stub(teamHost) { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/eigene") { return (200, #"{"tausche":[]}"#) }
            if path.hasSuffix("/schichtplan") { return (200, #"{"dienste":[],"schichten":[],"statistik":[]}"#) }
            return (404, "{}")
        }
        let team = CampSwapsModel(active: try active(.team, host: teamHost), personId: meUUID)
        await team.load()
        #expect(team.phase == .loaded && StubProtocol.requests(host: teamHost).contains { $0.url?.path.hasSuffix("/diensttausch/eigene") == true })
        await team.decide(CampSwapsModel.Row(id: UUID(), swap: CampRosterPreview.swapSample(open: true), title: "", text: "", second: nil, stamp: nil, canDecide: true, canWithdraw: false), .accepted)
        #expect(StubProtocol.requests(host: teamHost).allSatisfy { $0.httpMethod == "GET" })
    }

    private nonisolated static func countJSON(checked: Bool) -> String {
        #"{"eintraege":[{"id":"\#(uid(31))","teilnehmerId":null,"personId":"\#(uid(32))","name":"Mara","ceviName":"Luchs","geprueft":\#(checked),"geprueftAm":null}],"naechster":null,"da":\#(checked ? 1 : 0),"gesamt":1}"#
    }

    @Test func tickingTellsWhenSomebodyWasFaster() async throws {
        let host = host()
        stub(host) { request in
            if request.httpMethod == "PUT" { return (200, #"{"geaendert":0}"#) }
            return request.url?.path.hasSuffix("/gruppen") == true ? (200, #"{"gruppen":[],"ohneGruppe":0,"abgewaehlt":0}"#) : (200, Self.countJSON(checked: true))
        }
        let model = CampCountModel(active: try active(host: host))
        await model.load()
        #expect(model.rows[0].label == "Mara (Luchs)" && model.present == 1)
        await model.toggle(model.rows[0])
        #expect(model.notice?.title == "Schon entfernt." && model.rows[0].checked)
        let put = try #require(StubProtocol.requests(host: host).first { $0.httpMethod == "PUT" })
        #expect(body(put).contains("\"geprueft\":false") && body(put).contains("personIds"))
    }

    @Test func resetKeepsASnapshotForUndo() async throws {
        let host = host()
        stub(host) { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/zuruecksetzen") { return (200, #"{"zurueckgesetzt":1}"#) }
            if request.httpMethod == "PUT" { return (200, #"{"geaendert":1}"#) }
            return path.hasSuffix("/gruppen") ? (200, #"{"gruppen":[],"ohneGruppe":0,"abgewaehlt":0}"#) : (200, Self.countJSON(checked: true))
        }
        let model = CampCountModel(active: try active(host: host))
        await model.load()
        await model.reset()
        #expect(model.snapshot?.personIds.count == 1 && model.notice?.title == "Liste zurückgesetzt.")
        await model.undoReset()
        let put = try #require(StubProtocol.requests(host: host).first { $0.httpMethod == "PUT" })
        #expect(body(put).contains("\"geprueft\":true") && model.snapshot == nil && model.notice == nil)
    }

    @Test func readersTickNothing() async throws {
        let host = host()
        stub(host) { _ in (200, Self.countJSON(checked: false)) }
        let model = CampCountModel(active: try active(.readOnly, host: host))
        await model.load()
        await model.toggle(model.rows[0])
        await model.reset()
        #expect(StubProtocol.requests(host: host).allSatisfy { $0.httpMethod == "GET" })
    }
}

@MainActor
struct CampShiftsModelTests {
    @Test func rowsAreSentencesInTheOrderOfTheSections() throws {
        let model = CampShiftsModel(active: try active(host: host()), personId: meUUID)
        model.context = CampRosterPreview.context()
        let day = try #require(model.days.first)
        let rows = model.rows(for: day)
        #expect(rows.count == 5 && rows[0].duty.name == "Küche" && rows[0].countText == "2 von 2" && rows[0].isStaffed)
        #expect(rows[4].free == 2 && rows[4].sentence.hasSuffix("noch 2 Plätze frei"))
        #expect(rows[2].shifts.map(model.label).contains("Du, Tim"))
        #expect(rows[1].sentence.contains("Lea") && rows[1].sentence.hasSuffix("noch ein Platz frei"))
    }

    @Test func addingSendsTheWholeStaffOfTheDay() async throws {
        let host = host()
        stub(host) { _ in (200, #"{"geaendert":1}"#) }
        let model = CampShiftsModel(active: try active(host: host), personId: meUUID)
        model.context = CampRosterPreview.context()
        let day = try #require(model.days.first)
        let row = model.rows(for: day)[1]
        await model.add([CampPersonChoice(id: UUID(uuidString: uid(40))!, isParticipant: false, label: "Sina")], to: row, day: day)
        let put = try #require(StubProtocol.requests(host: host).first { $0.httpMethod == "PUT" })
        #expect(put.url?.path == "\(campPath)/schichtplan/schichten" && body(put).lowercased().contains(uid(40)) && body(put).contains("personIds"))
    }

    @Test func proposalIsConfirmedWithTheSameSeed() async throws {
        let host = host()
        stub(host) { request in
            let confirm = body(request).contains("\"uebernehmen\":true")
            return (200, #"{"vorschau":\#(confirm ? "false" : "true"),"seed":9,"gekuerzt":false,"schichten":[],"unbesetzt":[{"lagertagId":"\#(uid(41))","dienstId":"\#(uid(42))","fehlend":2}],"statistik":[],"geaendert":\#(confirm ? "3" : "null")}"#)
        }
        let model = CampShiftsModel(active: try active(host: host), personId: meUUID)
        model.context = CampRosterPreview.context()
        await model.suggest()
        #expect(model.proposal?.preview == true && model.proposalMissing == 2)
        #expect(await model.confirmProposal())
        let confirmBody = body(try #require(StubProtocol.requests(host: host).last { $0.httpMethod == "POST" }))
        #expect(confirmBody.contains("\"seed\":9") && confirmBody.contains("\"nurAnwesende\":true"))
        #expect(model.notice?.message == "3 Schichten eingeteilt.")
    }

    @Test func teamAndReadersCannotEdit() async throws {
        let host = host()
        stub(host) { _ in (200, #"{"geaendert":1}"#) }
        let model = CampShiftsModel(active: try active(.team, host: host), personId: meUUID)
        model.context = CampRosterPreview.context()
        await model.suggest()
        #expect(await !model.createDuty(name: "X", sectionId: UUID(), minStaff: 1, night: false))
        #expect(StubProtocol.requests(host: host).isEmpty)
    }
}

@MainActor
struct CampPlanningPushTests {
    @Test func planningPushOpensTheSwaps() async throws {
        let host = host()
        stub(host) { request in
            let path = request.url?.path ?? ""
            if path.contains("/aufloesen/") { return (200, #"{"lagerId":"\#(campUUID.uuidString)","objektTyp":"diensttausch","objektId":"\#(uid(1))"}"#) }
            if path == "/api/v1/lager" { return (200, #"{"lager":[{"id":"\#(campUUID.uuidString)","titel":"L","von":"2027-07-10","bis":"2027-07-17","vorbereitungAb":null,"ort":null,"adresse":null,"status":"aktiv","farbe":null,"logoMediumId":null,"rolle":"team"}]}"#) }
            return (404, "{}")
        }
        let client = APIClient(baseURL: URL(string: "https://\(host)")!, appVersion: "1.0.0", cookieStore: InMemoryCookieStore(["s": "1"]),
                               session: APIClient.makeSession(protocolClasses: [StubProtocol.self]))
        let camp = ActiveCamp()
        _ = await CampRouter.open(type: .planning, objectId: UUID(), client: client, list: CampListModel(), active: camp)
        #expect(camp.destination == .swaps)
    }
}
