import Foundation
import Testing
@testable import CeviOS

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder.api.decode(T.self, from: Data(json.utf8))
}

private let uuid1 = "0190a000-0000-7000-8000-000000000001"
private let uuid2 = "0190a000-0000-7000-8000-000000000002"
private let uuid3 = "0190a000-0000-7000-8000-000000000003"

private let participantJSON = #"{"id":"\#(uuid1)","version":2,"vorname":"Mia","nachname":"Muster","stufe":"Wölfe","abgewaehlt":false,"ceviName":"Funke"}"#
private let roomJSON = #"{"id":"\#(uuid1)","version":1,"name":"Zelt 1","art":"zelt","plaetze":4,"notiz":null,"reihenfolge":0}"#
private let tripJSON = """
{"id":"\(uuid1)","version":3,"richtung":"hin","art":"auto","name":"Auto 1","fahrerPersonId":"\(uuid2)","plaetze":4,"datum":"2027-07-10","zeit":"09:30",
 "von":"Bahnhof","nach":"Lagerplatz","treffpunkt":null,"link":null,"zielBezeichnung":"Lagerhaus","zielAdresse":null,"zielLat":46.9,"zielLon":7.4,"zielLink":null,
 "fahrer":{"personId":"\(uuid2)","name":"Pat Muster"},
 "mitfahrer":[{"id":"\(uuid3)","version":1,"personId":null,"teilnehmerId":"\(uuid1)","name":"Mia Muster","stufe":null}],"belegt":1,"frei":3,"ueberbelegt":false}
"""
private let swapJSON = """
{"id":"\(uuid1)","version":1,"vonPersonId":"\(uuid2)","schichtId":"\(uuid3)","mitPersonId":null,"mitSchichtId":null,"notiz":null,"status":"offen",
 "entschiedenVon":null,"entschiedenAm":null,"erstelltAm":"2027-07-10T08:00:00Z"}
"""
private let proposalJSON = """
{"vorschau":true,"seed":42,"gekuerzt":false,
 "schichten":[{"lagertagId":"\(uuid1)","datum":"2027-07-12","dienstId":"\(uuid2)","tagesabschnittId":"\(uuid3)","personId":"\(uuid1)","teilnehmerId":null,"name":"Pat Muster"}],
 "unbesetzt":[{"lagertagId":"\(uuid1)","dienstId":"\(uuid2)","fehlend":1}],
 "statistik":[{"personId":"\(uuid1)","teilnehmerId":null,"name":"Pat Muster","vorher":0,"neu":1,"gesamt":1,"nachtwachen":0}]}
"""

struct CampRosterModelTests {
    @Test func participantsAndImportDecode() throws {
        let page = try decode(CampParticipantPage.self, #"{"teilnehmer":[\#(participantJSON),{"id":"\#(uuid2)","version":1,"vorname":"Tim","nachname":"Test","stufe":null,"abgewaehlt":true}],"naechster":null}"#)
        #expect(page.participants.first?.ceviName == "Funke" && page.participants.last?.ceviName == nil && page.participants.last?.deselected == true)
        let result = try decode(CampParticipantImportResult.self, """
        {"vorschau":true,"angelegt":0,"neu":[{"zeile":1,"vorname":"A","nachname":"B","stufe":null,"ceviName":null}],
         "fehler":[{"zeile":2,"code":"VORNAME_FEHLT","message":"x"},{"zeile":3,"code":"NEUER_CODE","message":"y"}],"doppelt":[{"zeile":4,"grund":"im_text"}]}
        """)
        #expect(result.preview && result.new.count == 1 && result.errors.map(\.code) == [.firstNameMissing, .unknown] && result.duplicates.first?.reason == .inText)
    }

    @Test func countPageDecodes() throws {
        let page = try decode(CampCountPage.self, """
        {"eintraege":[{"id":"\(uuid1)","teilnehmerId":"\(uuid1)","vorname":"Mia","nachname":"Muster","stufe":null,"ceviName":null,"geprueft":true,"geprueftAm":"2027-07-10T08:00:00Z"},
         {"id":"\(uuid2)","personId":"\(uuid2)","name":"Pat Muster","geprueft":false,"geprueftAm":null}],"naechster":null,"da":1,"gesamt":2}
        """)
        #expect(page.entries[0].checked && page.entries[0].checkedAt != nil && page.entries[1].personId != nil && page.present == 1 && page.total == 2)
    }

    @Test func roomListIsFullOrTeamView() throws {
        let list = try decode(CampRoomList.self, """
        {"zimmer":[{"id":"\(uuid1)","version":1,"name":"Zelt 1","art":"zelt","plaetze":4,"notiz":null,"reihenfolge":0,"belegt":5,"ueberbelegt":true,
                    "mitglieder":[{"typ":"teilnehmer","id":"\(uuid2)","name":"Mia"},{"typ":"neu","id":"\(uuid3)","name":"X"}]},
                   {"id":"\(uuid2)","version":1,"name":"Zimmer 2","art":"zimmer","mitglieder":[{"name":"Pat"}]}],"offen":{"teilnehmer":3,"team":1}}
        """)
        guard case .full(let room) = list.rooms[0], case .team(let view) = list.rooms[1] else { Issue.record("shapes"); return }
        #expect(room.overbooked && room.occupied == 5 && room.members.map(\.kind) == [.participant, .unknown])
        #expect(view.members.first?.name == "Pat" && list.open?.participants == 3)
    }

    @Test func roomOccupancyReadsPlacedAndRemoved() throws {
        let placed = try decode(CampRoomOccupancy.self, #"{"eingeteilt":2,"belegt":5,"plaetze":4,"ueberbelegt":true}"#)
        let removed = try decode(CampRoomOccupancy.self, #"{"entfernt":1,"belegt":4,"plaetze":4,"ueberbelegt":false}"#)
        #expect(placed.changed == 2 && placed.overbooked && removed.changed == 1 && !removed.overbooked)
    }

    @Test func tripDecodes() throws {
        let trip = try decode(CampTrip.self, tripJSON)
        #expect(trip.kind == .car && trip.free == 3 && trip.driver?.name == "Pat Muster" && trip.passengers.first?.participantId != nil)
        #expect(trip.destinationLat == 46.9 && trip.date == DateFormats.calendarDay("2027-07-10") && trip.meetingPoint == nil)
        let without = try decode(CampTripWithoutPage.self, #"{"personen":[{"personId":null,"teilnehmerId":"\#(uuid1)","name":"Mia","stufe":null}],"gesamt":1,"naechster":"abc"}"#)
        #expect(without.next == "abc" && without.total == 1)
        let boarding = try decode(CampTripBoarding.self, #"{"id":"\#(uuid1)","version":1,"fahrtId":"\#(uuid2)","personId":null,"teilnehmerId":"\#(uuid3)","belegt":2,"plaetze":null,"ueberbelegt":false}"#)
        #expect(boarding.tripId.uuidString.lowercased() == uuid2 && boarding.places == nil)
    }

    @Test func groupsAndShuffleDecode() throws {
        let list = try decode(CampGroupList.self, """
        {"gruppen":[{"id":"\(uuid1)","version":1,"name":"Rot","reihenfolge":0,"personen":[{"personId":"\(uuid2)","name":"Pat","ceviName":null,"rolle":"leitung"}],
          "teilnehmer":[{"id":"\(uuid3)","vorname":"Mia","nachname":"Muster","stufe":null}]}],"ohneGruppe":2,"abgewaehlt":1}
        """)
        #expect(list.groups[0].people[0].role == .leader && list.groups[0].participants[0].ceviName == nil && list.withoutGroup == 2)
        let shuffle = try decode(CampGroupShuffle.self, """
        {"vorschau":true,"seed":7,"gruppen":[{"nummer":1,"gruppeId":null,"name":"Gruppe 1","anzahl":1,"teilnehmer":[{"id":"\(uuid1)","vorname":"Mia","nachname":"Muster","stufe":null}]},
          {"nummer":2,"gruppeId":null,"name":"Gruppe 2","anzahl":0,"teilnehmer":[]}]}
        """)
        #expect(shuffle.preview && shuffle.seed == 7 && shuffle.groups.count == 2 && shuffle.changed == nil && shuffle.groups[0].groupId == nil)
    }

    @Test func shiftPlanAndProposalDecode() throws {
        let plan = try decode(CampShiftPlan.self, """
        {"dienste":[{"id":"\(uuid1)","version":1,"name":"Küche","beschreibung":null,"mindestbesetzung":2,"nacht":false,"tagesabschnittId":"\(uuid2)","reihenfolge":0}],
         "schichten":[{"id":"\(uuid3)","version":1,"dienstId":"\(uuid1)","lagertagId":"\(uuid2)","datum":"2027-07-12","tagesabschnittId":"\(uuid2)","personId":"\(uuid1)","teilnehmerId":null,"name":"Pat Muster","ceviName":null,"stufe":null}],
         "statistik":[{"personId":"\(uuid1)","teilnehmerId":null,"name":"Pat Muster","anzahl":1,"nachtwachen":0}]}
        """)
        #expect(plan.duties[0].minStaff == 2 && plan.shifts[0].participantId == nil && plan.statistics[0].count == 1)
        #expect(plan.freePlaces(duty: plan.duties[0], dayId: UUID(uuidString: uuid2)!) == 1)
        let proposal = try decode(CampShiftProposal.self, proposalJSON)
        #expect(proposal.preview && proposal.seed == 42 && !proposal.truncated && proposal.unfilled[0].missing == 1 && proposal.statistics[0].added == 1 && proposal.changed == nil)
    }

    @Test func swapDecodes() throws {
        let swap = try decode(CampShiftSwap.self, swapJSON)
        #expect(swap.status == .open && swap.withPersonId == nil && swap.decidedAt == nil && swap.createdAt.timeIntervalSince1970 > 0)
    }

    @Test func shiftSentenceIsAWholeGermanSentence() {
        let monday = DateFormats.calendarDay("2027-07-12")!
        #expect(CampShiftText.sentence(duty: "Küche", date: monday, section: "Vormittag", people: ["Person X"], free: 1) == "Küche, Montag Vormittag, Person X, noch ein Platz frei")
        #expect(CampShiftText.sentence(duty: "Küche", date: monday, section: "Vormittag", people: ["A", "B", "C"], free: 0) == "Küche, Montag Vormittag, A, B und C")
        #expect(CampShiftText.sentence(duty: "Nachtwache", date: monday, section: "Nacht", people: [], free: 2) == "Nachtwache, Montag Nacht, noch 2 Plätze frei")
    }

    @Test func planSentencesFollowSectionsDaysAndDuties() throws {
        let section = try decode(CampDaySection.self, #"{"id":"\#(uuid2)","version":1,"name":"Vormittag","zeit":null,"reihenfolge":0}"#)
        let day = try decode(CampDay.self, #"{"id":"\#(uuid3)","version":1,"datum":"2027-07-12","label":null}"#)
        let plan = try decode(CampShiftPlan.self, """
        {"dienste":[{"id":"\(uuid1)","version":1,"name":"Küche","beschreibung":null,"mindestbesetzung":2,"nacht":false,"tagesabschnittId":"\(uuid2)","reihenfolge":0}],
         "schichten":[{"id":"\(uuid1)","version":1,"dienstId":"\(uuid1)","lagertagId":"\(uuid3)","datum":"2027-07-12","tagesabschnittId":"\(uuid2)","personId":"\(uuid1)","teilnehmerId":null,"name":"Pat","ceviName":null,"stufe":null}],
         "statistik":[]}
        """)
        #expect(plan.sentences(days: [day], sections: [section]) == ["Küche, Montag Vormittag, Pat, noch ein Platz frei"])
    }
}

struct CampRosterBodyTests {
    private func json(_ value: some Encodable) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder.api.encode(value)) as? [String: Any])
    }

    @Test func patchesSendOnlyChangesAndNull() throws {
        let participant = try json(CampParticipantPatch(version: 2, level: .clear))
        #expect(Set(participant.keys) == ["version", "stufe"] && participant["stufe"] is NSNull)
        let trip = try json(CampTripPatch(version: 1, name: .set("Auto 2"), places: .clear, date: .set(CampCalendarDay(DateFormats.calendarDay("2027-07-10")!))))
        #expect(Set(trip.keys) == ["version", "name", "plaetze", "datum"] && trip["plaetze"] is NSNull && trip["datum"] as? String == "2027-07-10")
        let room = try json(CampRoomPatch(version: 1, note: .clear))
        #expect(Set(room.keys) == ["version", "notiz"])
        let duty = try json(CampDutyPatch(version: 1, minStaff: 3, night: true))
        #expect(Set(duty.keys) == ["version", "mindestbesetzung", "nacht"])
    }

    @Test func groupAssignSendsNullToLeaveEveryGroup() throws {
        let body = try json(CampGroupAssign(groupId: nil, participantIds: [UUID()]))
        #expect(body["gruppeId"] is NSNull && (body["teilnehmerIds"] as? [Any])?.count == 1 && body["rolle"] == nil)
    }

    @Test func suggestionAndConfirmationAreSeparateBodies() throws {
        let options = CampShiftOptions(dayIds: nil, onlyPresent: false, withParticipants: true)
        let suggest = try json(CampShiftProposalBody(confirm: false, seed: nil, options: options))
        #expect(Set(suggest.keys) == ["uebernehmen", "nurAnwesende", "mitTeilnehmenden"] && suggest["uebernehmen"] as? Bool == false)
        let confirm = try json(CampShiftProposalBody(confirm: true, seed: 42, options: CampShiftOptions(dayIds: [UUID()])))
        #expect(confirm["uebernehmen"] as? Bool == true && confirm["seed"] as? Int == 42 && (confirm["lagertagIds"] as? [Any])?.count == 1)
    }

    @Test func swapBodiesUseTheServerNames() throws {
        let decide = try json(CampShiftSwapDecide(decision: .rejected, version: 2))
        #expect(Set(decide.keys) == ["entscheid", "version"] && decide["entscheid"] as? String == "abgelehnt")
        let create = try json(CampShiftSwapCreate(shiftId: UUID(), note: "Krank"))
        #expect(Set(create.keys) == ["schichtId", "notiz"])
    }

    @Test func countFilterBuildsTheQuery() {
        let group = UUID()
        let items = CampCountFilter(kind: .team, level: "Biber", groupId: group).queryItems
        #expect(items == [URLQueryItem(name: "art", value: "team"), URLQueryItem(name: "stufe", value: "Biber"), URLQueryItem(name: "gruppe", value: group.uuidString.lowercased())])
    }
}

struct CampRosterServiceTests {
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

    @Test func participantRoutes() async throws {
        var r = try await sent(#"{"teilnehmer":[],"naechster":null}"#) { _ = try await $0.campParticipants(campId: camp, level: "Biber", after: other, limit: 20) }
        #expect(r.method == "GET" && r.path == campPath + "/teilnehmer" && r.query["stufe"] == "Biber" && r.query["limit"] == "20" && r.query["nach"] == otherText)
        r = try await sent(participantJSON) { _ = try await $0.campParticipant(campId: camp, participantId: id) }
        #expect(r.path == campPath + "/teilnehmer/" + idText)
        r = try await sent(status: 201, participantJSON) { _ = try await $0.createCampParticipant(campId: camp, CampParticipantCreate(firstName: "Mia", lastName: "Muster")) }
        #expect(r.method == "POST" && r.body?["vorname"] as? String == "Mia")
        r = try await sent(participantJSON) { _ = try await $0.updateCampParticipant(campId: camp, participantId: id, CampParticipantPatch(version: 2, firstName: "Mi")) }
        #expect(r.method == "PATCH" && r.body?["version"] as? Int == 2)
        r = try await sent(status: 204, "") { try await $0.deleteCampParticipant(campId: camp, participantId: id, version: 2) }
        #expect(r.method == "DELETE" && r.query["version"] == "2")
        let empty = #"{"vorschau":true,"angelegt":0,"neu":[],"fehler":[],"doppelt":[]}"#
        r = try await sent(empty) { _ = try await $0.previewCampParticipantImport(campId: camp, text: "A;B") }
        #expect(r.method == "POST" && r.path == campPath + "/teilnehmer/import" && r.body?["uebernehmen"] as? Bool == false && r.body?["text"] as? String == "A;B")
        r = try await sent(empty) { _ = try await $0.importCampParticipants(campId: camp, text: "A;B") }
        #expect(r.body?["uebernehmen"] as? Bool == true)
    }

    @Test func countRoutes() async throws {
        var r = try await sent(#"{"eintraege":[],"naechster":null,"da":0,"gesamt":0}"#) { _ = try await $0.campCount(campId: camp, filter: CampCountFilter(kind: .participants, groupId: other)) }
        #expect(r.method == "GET" && r.path == campPath + "/abzaehlen" && r.query["art"] == "teilnehmer" && r.query["gruppe"] == otherText)
        var changed = 0
        r = try await sent(#"{"geaendert":2}"#) { changed = try await $0.setCampCount(campId: camp, checked: true, participantIds: [id]) }
        #expect(r.method == "PUT" && r.path == campPath + "/abzaehlen" && r.body?["geprueft"] as? Bool == true && changed == 2)
        r = try await sent(#"{"zurueckgesetzt":5}"#) { changed = try await $0.resetCampCount(campId: camp) }
        #expect(r.method == "POST" && r.path == campPath + "/abzaehlen/zuruecksetzen" && r.body?["bestaetigt"] as? Bool == true && changed == 5)
    }

    @Test func roomRoutes() async throws {
        var r = try await sent(#"{"zimmer":[]}"#) { _ = try await $0.campRooms(campId: camp) }
        #expect(r.method == "GET" && r.path == campPath + "/zimmer")
        r = try await sent(status: 201, roomJSON) { _ = try await $0.createCampRoom(campId: camp, CampRoomCreate(name: "Zelt 1", kind: .tent, places: 4)) }
        #expect(r.method == "POST" && r.body?["art"] as? String == "zelt" && r.body?["plaetze"] as? Int == 4)
        r = try await sent(roomJSON) { _ = try await $0.updateCampRoom(campId: camp, roomId: id, CampRoomPatch(version: 1, places: 6)) }
        #expect(r.method == "PATCH" && r.path == campPath + "/zimmer/" + idText)
        r = try await sent(status: 204, "") { try await $0.deleteCampRoom(campId: camp, roomId: id, version: 1) }
        #expect(r.method == "DELETE" && r.query["version"] == "1")
        r = try await sent(#"{"eintraege":[],"naechster":null}"#) { _ = try await $0.campOpenRoomPeople(campId: camp, kind: .team) }
        #expect(r.path == campPath + "/zimmer/offen" && r.query["art"] == "team")
        let answer = #"{"eingeteilt":1,"belegt":1,"plaetze":4,"ueberbelegt":false}"#
        r = try await sent(answer) { _ = try await $0.placeInCampRoom(campId: camp, roomId: id, CampRoomPeople(participantIds: [other])) }
        #expect(r.method == "POST" && r.path == campPath + "/zimmer/" + idText + "/zuordnung" && (r.body?["teilnehmerIds"] as? [Any])?.count == 1)
        r = try await sent(#"{"entfernt":1,"belegt":0,"plaetze":4,"ueberbelegt":false}"#) { _ = try await $0.removeFromCampRoom(campId: camp, roomId: id, CampRoomPeople(personIds: [other])) }
        #expect(r.path == campPath + "/zimmer/" + idText + "/zuordnung/entfernen")
    }

    @Test func tripRoutes() async throws {
        var r = try await sent(#"{"fahrten":[],"naechster":null}"#) { _ = try await $0.campTrips(campId: camp, direction: .inbound) }
        #expect(r.method == "GET" && r.path == campPath + "/fahrten" && r.query["richtung"] == "rueck")
        r = try await sent(tripJSON) { _ = try await $0.campTrip(campId: camp, tripId: id) }
        #expect(r.path == campPath + "/fahrten/" + idText)
        r = try await sent(status: 201, tripJSON) { _ = try await $0.createCampTrip(campId: camp, CampTripCreate(direction: .outbound, kind: .publicTransport, from: "Bern")) }
        #expect(r.method == "POST" && r.body?["art"] as? String == "oev" && r.body?["von"] as? String == "Bern")
        r = try await sent(tripJSON) { _ = try await $0.updateCampTrip(campId: camp, tripId: id, CampTripPatch(version: 3, time: .set("10:00"))) }
        #expect(r.method == "PATCH" && r.body?["zeit"] as? String == "10:00")
        r = try await sent(status: 204, "") { try await $0.deleteCampTrip(campId: camp, tripId: id, version: 3) }
        #expect(r.method == "DELETE" && r.query["version"] == "3")
        r = try await sent(#"{"personen":[],"gesamt":0,"naechster":null}"#) { _ = try await $0.campPeopleWithoutTrip(campId: camp, direction: .outbound, after: "abc") }
        #expect(r.path == campPath + "/fahrten/ohne" && r.query["richtung"] == "hin" && r.query["nach"] == "abc")
        let boarding = #"{"id":"\#(uuid1)","version":1,"fahrtId":"\#(uuid2)","personId":null,"teilnehmerId":null,"belegt":1,"plaetze":4,"ueberbelegt":false}"#
        r = try await sent(status: 201, boarding) { _ = try await $0.addCampPassenger(campId: camp, tripId: id, CampTripPassengerCreate(participantId: other)) }
        #expect(r.method == "POST" && r.path == campPath + "/fahrten/" + idText + "/mitfahrer" && r.body?["teilnehmerId"] != nil)
        r = try await sent(status: 204, "") { try await $0.removeCampPassenger(campId: camp, tripId: id, passengerId: other, version: 1) }
        #expect(r.method == "DELETE" && r.path == campPath + "/fahrten/" + idText + "/mitfahrer/" + otherText && r.query["version"] == "1")
    }

    @Test func groupRoutes() async throws {
        var r = try await sent(#"{"gruppen":[],"ohneGruppe":0,"abgewaehlt":0}"#) { _ = try await $0.campGroups(campId: camp) }
        #expect(r.method == "GET" && r.path == campPath + "/gruppen")
        let row = #"{"id":"\#(uuid1)","version":1,"name":"Rot","reihenfolge":0}"#
        r = try await sent(status: 201, row) { _ = try await $0.createCampGroup(campId: camp, CampGroupCreate(name: "Rot")) }
        #expect(r.method == "POST" && r.body?["name"] as? String == "Rot")
        r = try await sent(row) { _ = try await $0.updateCampGroup(campId: camp, groupId: id, CampGroupPatch(version: 1, name: "Blau")) }
        #expect(r.method == "PATCH" && r.path == campPath + "/gruppen/" + idText)
        r = try await sent(status: 204, "") { try await $0.deleteCampGroup(campId: camp, groupId: id, version: 1) }
        #expect(r.method == "DELETE" && r.query["version"] == "1")
        var changed = 0
        r = try await sent(#"{"geaendert":3}"#) { changed = try await $0.assignCampGroup(campId: camp, CampGroupAssign(groupId: id, personIds: [other], role: .leader)) }
        #expect(r.method == "PUT" && r.path == campPath + "/gruppen/zuordnung" && r.body?["rolle"] as? String == "leitung" && changed == 3)
        r = try await sent(#"{"geaendert":1}"#) { changed = try await $0.deselectCampParticipants(campId: camp, deselected: true, participantIds: [other]) }
        #expect(r.method == "PUT" && r.path == campPath + "/gruppen/abgewaehlt" && r.body?["abgewaehlt"] as? Bool == true && changed == 1)
    }

    @Test func groupShuffleSuggestsFirstAndConfirmsWithTheSameSeed() async throws {
        let preview = #"{"vorschau":true,"seed":7,"gruppen":[{"nummer":1,"gruppeId":null,"name":"G1","anzahl":0,"teilnehmer":[]},{"nummer":2,"gruppeId":null,"name":"G2","anzahl":0,"teilnehmer":[]}]}"#
        var suggestion: CampGroupShuffle?
        var r = try await sent(preview) { suggestion = try await $0.suggestCampGroupShuffle(campId: camp, count: 2) }
        #expect(r.method == "POST" && r.path == campPath + "/gruppen/mischen" && r.body?["uebernehmen"] as? Bool == false && r.body?["anzahl"] as? Int == 2 && r.body?["seed"] == nil)
        let confirmed = try #require(suggestion)
        r = try await sent(#"{"vorschau":false,"seed":7,"gruppen":[],"geaendert":4}"#) { _ = try await $0.confirmCampGroupShuffle(campId: camp, confirmed) }
        #expect(r.body?["uebernehmen"] as? Bool == true && r.body?["seed"] as? Int == 7 && r.body?["anzahl"] as? Int == 2)
    }

    @Test func shiftPlanRoutes() async throws {
        var r = try await sent(#"{"dienste":[],"schichten":[],"statistik":[]}"#) { _ = try await $0.campShiftPlan(campId: camp) }
        #expect(r.method == "GET" && r.path == campPath + "/schichtplan")
        let duty = #"{"id":"\#(uuid1)","version":1,"name":"Küche","beschreibung":null,"mindestbesetzung":1,"nacht":false,"tagesabschnittId":"\#(uuid2)","reihenfolge":0}"#
        r = try await sent(status: 201, duty) { _ = try await $0.createCampDuty(campId: camp, CampDutyCreate(name: "Küche", sectionId: other)) }
        #expect(r.method == "POST" && r.path == campPath + "/schichtplan/dienste" && r.body?["tagesabschnittId"] != nil)
        r = try await sent(duty) { _ = try await $0.updateCampDuty(campId: camp, dutyId: id, CampDutyPatch(version: 1, night: true)) }
        #expect(r.method == "PATCH" && r.path == campPath + "/schichtplan/dienste/" + idText)
        r = try await sent(status: 204, "") { try await $0.deleteCampDuty(campId: camp, dutyId: id, version: 1) }
        #expect(r.method == "DELETE" && r.query["version"] == "1")
        var changed = 0
        r = try await sent(#"{"geaendert":2}"#) { changed = try await $0.setCampShifts(campId: camp, CampShiftStaff(dayId: id, dutyId: other, personIds: [])) }
        #expect(r.method == "PUT" && r.path == campPath + "/schichtplan/schichten" && (r.body?["personIds"] as? [Any])?.isEmpty == true && changed == 2)
    }

    @Test func shiftSuggestionAndConfirmationAreTwoRequests() async throws {
        let options = CampShiftOptions(dayIds: [id], onlyPresent: false, withParticipants: false)
        var proposal: CampShiftProposal?
        var r = try await sent(proposalJSON) { proposal = try await $0.suggestCampShifts(campId: camp, options: options, seed: 5) }
        #expect(r.method == "POST" && r.path == campPath + "/schichtplan/vorschlag" && r.body?["uebernehmen"] as? Bool == false && r.body?["seed"] as? Int == 5)
        #expect(r.body?["nurAnwesende"] as? Bool == false && (r.body?["lagertagIds"] as? [Any])?.count == 1)
        let suggestion = try #require(proposal)
        r = try await sent(proposalJSON) { _ = try await $0.confirmCampShifts(campId: camp, suggestion, options: options) }
        #expect(r.body?["uebernehmen"] as? Bool == true && r.body?["seed"] as? Int == 42)
    }

    @Test func swapRoutes() async throws {
        var r = try await sent(#"{"tausche":[],"naechster":null}"#) { _ = try await $0.campShiftSwaps(campId: camp, status: .open, after: other) }
        #expect(r.method == "GET" && r.path == campPath + "/diensttausch" && r.query["status"] == "offen" && r.query["nach"] == otherText)
        var own: [CampShiftSwap] = []
        r = try await sent(#"{"tausche":[\#(swapJSON)]}"#) { own = try await $0.ownCampShiftSwaps(campId: camp) }
        #expect(r.path == campPath + "/diensttausch/eigene" && own.count == 1)
        r = try await sent(status: 201, swapJSON) { _ = try await $0.requestCampShiftSwap(campId: camp, CampShiftSwapCreate(shiftId: other, withPersonId: id)) }
        #expect(r.method == "POST" && r.path == campPath + "/diensttausch" && r.body?["mitPersonId"] != nil)
        r = try await sent(swapJSON) { _ = try await $0.decideCampShiftSwap(campId: camp, swapId: id, CampShiftSwapDecide(decision: .accepted, version: 1)) }
        #expect(r.method == "POST" && r.path == campPath + "/diensttausch/" + idText + "/entscheid" && r.body?["entscheid"] as? String == "angenommen")
        r = try await sent(swapJSON) { _ = try await $0.withdrawCampShiftSwap(campId: camp, swapId: id, version: 1) }
        #expect(r.method == "POST" && r.path == campPath + "/diensttausch/" + idText + "/zurueckziehen" && r.body?["version"] as? Int == 1)
    }

    @Test func memberAndTemplateLists() async throws {
        var members: [CampMember] = []
        var r = try await sent(#"{"mitglieder":[{"personId":"\#(idText)","name":"Lea","bildUrl":"/api/v1/personen/\#(idText)/bild?v=3","rolle":"team","ressorts":["PR"]}]}"#) {
            members = try await $0.campMembers(campId: camp)
        }
        #expect(r.method == "GET" && r.path == campPath + "/mitglieder")
        #expect(members.first?.id == id && members.first?.name == "Lea" && members.first?.role == .team && members.first?.portfolios == ["PR"])
        var templates: [CampTemplateEntry] = []
        r = try await sent(#"{"vorlagen":[{"id":"\#(idText)","art":"packliste","name":"Standard","anzahl":12}]}"#) {
            templates = try await $0.campTemplates(campId: camp)
        }
        #expect(r.method == "GET" && r.path == campPath + "/vorlagen")
        #expect(templates.first?.kind == .packingList && templates.first?.count == 12)
    }
}
