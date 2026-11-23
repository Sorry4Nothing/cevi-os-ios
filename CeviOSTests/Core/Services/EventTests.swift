import Foundation
import Testing
@testable import CeviOS

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder.api.decode(T.self, from: Data(json.utf8))
}

private let uuid1 = "0190a000-0000-7000-8000-000000000001"
private let uuid2 = "0190a000-0000-7000-8000-000000000002"
private let tagJSON = #"{"id":"\#(uuid2)","name":"Biber","typ":"stufe"}"#
private let eventJSON = """
{"id":"\(uuid1)","titel":"Samstagsprogramm","status":"aktiv","ganztaegig":false,"beginn":"2027-03-06T13:00:00Z","ende":"2027-03-06T16:00:00Z",
 "tagVon":null,"tagBis":null,"ort":"Waldhaus","tags":[\(tagJSON)],
 "anlass":{"id":"\(uuid2)","anmeldeschluss":null,"anmeldungOffen":true,"angemeldet":false},
 "kinder":[{"id":"\(uuid2)","vorname":"Mia","status":null}]}
"""
private let suggestionJSON = """
{"id":"\(uuid1)","status":"in_outlook_eingetragen","titel":"Bräteln","ganztaegig":true,"beginn":null,"ende":null,"tagVon":"2027-05-01","tagBis":"2027-05-02",
 "ort":null,"beschreibung":null,"bemerkung":"Bitte prüfen","tags":[\(tagJSON)],"begruendung":null,"entschiedenAm":"2027-04-01T08:00:00Z",
 "erstelltAm":"2027-03-30T08:00:00Z","vorgeschlagenVon":null}
"""
private let requestJSON = """
{"id":"\(uuid1)","raumId":"\(uuid2)","raumName":"Kellerraum","beginn":"2027-04-01T17:00:00Z","ende":"2027-04-01T19:00:00Z","zweck":"Sitzung",
 "status":"bestaetigt","begruendung":null,"entschiedenAm":"2027-03-30T08:00:00Z","erstelltAm":"2027-03-29T08:00:00Z"}
"""
private let formJSON = """
{"id":"\(uuid1)","terminId":"\(uuid2)","titel":"Sommerfest","ganztaegig":true,"beginn":null,"ende":null,"tagVon":"2027-06-19","tagBis":"2027-06-19",
 "anmeldungOffen":true,"frist":"2027-06-10T21:59:59Z","anmeldungFuer":"kind",
 "felder":[{"schluessel":"essen","beschriftung":"Essen","typ":"auswahl","optionen":["normal","vegi"],"pflicht":true},
           {"schluessel":"neu","beschriftung":"Neu","typ":"foto","optionen":[],"pflicht":false}],
 "teilnehmende":[{"kindId":"\(uuid2)","name":"Mia","konto":[{"schluessel":"vorname","beschriftung":"Vorname","wert":"Mia"}],
   "anmeldung":{"id":"\(uuid1)","status":"angemeldet","antworten":{"essen":"vegi","allergie":false},"geaendertAm":"2027-06-01T08:00:00Z"}}]}
"""

struct EventModelTests {
    @Test func calendarPageDecodesTimedEventWithOccasionAndChildren() throws {
        let page = try decode(CalendarEventPage.self, #"{"termine":[\#(eventJSON)],"weitere":true,"naechste":"abc"}"#)
        let event = try #require(page.events.first)
        #expect(!event.isAllDay && event.start != nil && event.dayFrom == nil && event.status == .active && event.place == "Waldhaus")
        #expect(event.tags.first?.kind == .unit && event.occasion?.isOpen == true && event.occasion?.deadline == nil)
        #expect(event.children.first?.answer == nil && event.children.first?.firstName == "Mia")
        #expect(page.hasMore && page.next == "abc")
    }

    @Test func allDayEventAndUnknownValuesAreTolerated() throws {
        let json = eventJSON.replacing(#""ganztaegig":false,"beginn":"2027-03-06T13:00:00Z","ende":"2027-03-06T16:00:00Z","#, with: #""ganztaegig":true,"beginn":null,"ende":null,"#)
            .replacing(#""tagVon":null,"tagBis":null"#, with: #""tagVon":"2027-03-06","tagBis":"2027-03-07""#)
            .replacing(#""aktiv""#, with: #""neu""#).replacing(#""typ":"stufe""#, with: #""typ":"gruppe""#).replacing(#""anlass":{"#, with: #""x":{"#)
        let event = try decode(CalendarEvent.self, json)
        #expect(event.isAllDay && event.start == nil && event.dayFrom != nil && event.dayTo != nil)
        #expect(event.status == .unknown && event.tags.first?.kind == .unknown && event.occasion == nil)
    }

    @Test func appendingAPageKeepsAnEventOnce() throws {
        let first = try decode(CalendarEventPage.self, #"{"termine":[\#(eventJSON)],"weitere":true,"naechste":"a"}"#)
        let second = try decode(CalendarEventPage.self, #"{"termine":[\#(eventJSON)],"weitere":false,"naechste":null}"#)
        let merged = first.appending(second)
        #expect(merged.events.count == 1 && !merged.hasMore && merged.next == nil)
    }

    @Test func detailAddsUnitPageAndOwnAnswer() throws {
        let extra = #","treffpunkt":"Bahnhof 13:00","schlussOrt":null,"schlussZeit":"16:00","mitnehmen":"Znüni","teilnahmeOffen":true,"eigeneAnmeldung":"offen"}"#
        let detail = try decode(CalendarEventDetail.self, String(eventJSON.dropLast()) + extra)
        #expect(detail.id.uuidString.lowercased() == uuid1 && detail.meetingPoint == "Bahnhof 13:00" && detail.endPlace == nil && detail.endTime == "16:00")
        #expect(detail.bring == "Znüni" && detail.isParticipationOpen && detail.ownRegistration == .open && detail.event.title == "Samstagsprogramm")
        let plain = try decode(CalendarEventDetail.self, String(eventJSON.dropLast()) + #","treffpunkt":null,"schlussOrt":null,"schlussZeit":null,"mitnehmen":null,"teilnahmeOffen":false}"#)
        #expect(plain.ownRegistration == nil && !plain.isParticipationOpen)
    }

    @Test func calendarLinkStatusDecodesWithAndWithoutLink() throws {
        let active = try decode(CalendarLinkStatus.self, #"{"aktiv":true,"erstelltAm":"2027-03-01T08:00:00Z","zuletztAbgerufenAm":null,"endung":"Ab3_"}"#)
        #expect(active.isActive && active.createdAt != nil && active.lastFetchedAt == nil && active.suffix == "Ab3_")
        let none = try decode(CalendarLinkStatus.self, #"{"aktiv":false,"erstelltAm":null,"zuletztAbgerufenAm":null,"endung":null}"#)
        #expect(!none.isActive && none.suffix == nil)
    }

    @Test func newCalendarLinkBuildsTheAddressAndNeverPrintsIt() throws {
        let token = String(repeating: "A", count: 39) + "Ab3_"
        let link = try decode(CalendarLinkNew.self, #"{"token":"\#(token)","pfad":"/ical/\#(token).ics","erstelltAm":"2027-03-01T08:00:00Z","endung":"Ab3_"}"#)
        #expect(link.url(base: URL(string: "https://api.test.example.org")!)?.absoluteString == "https://api.test.example.org/ical/\(token).ics")
        for text in ["\(link)", String(reflecting: link), String(describing: link)] {
            #expect(!text.contains(token))
        }
    }

    @Test func suggestionDecodesFixedStatusAndMissingProposer() throws {
        let s = try decode(EventSuggestion.self, suggestionJSON)
        #expect(s.status == .enteredInCalendar && s.isAllDay && s.dayTo != nil && s.beginnIsNil && s.proposedBy == nil && s.note == "Bitte prüfen")
        let page = try decode(EventSuggestionPage.self, #"{"vorschlaege":[\#(suggestionJSON)],"weitere":true,"naechste":"\#(uuid2)"}"#)
        #expect(page.suggestions.count == 1 && page.next?.uuidString.lowercased() == uuid2)
        #expect(throws: Error.self) { try decode(EventSuggestion.self, suggestionJSON.replacing("in_outlook_eingetragen", with: "neu")) }
        let options = try decode(EventSuggestionOptions.self, #"{"darfVorschlagen":true,"tags":[\#(tagJSON)]}"#)
        #expect(options.mayPropose && options.tags.count == 1)
    }

    @Test func suggestionBodyEncodesAllDayAndTimed() throws {
        let tag = UUID()
        let day = try #require(DateFormats.calendarDay("2027-05-01"))
        let allDay = EventSuggestionCreate(title: "A", time: .allDay(from: day, to: day), tagIds: [tag])
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder.api.encode(allDay)) as? [String: Any])
        #expect(object["ganztaegig"] as? Bool == true && object["tagVon"] as? String == "2027-05-01" && object["tagBis"] as? String == "2027-05-01")
        #expect(object["beginn"] == nil && object["ort"] == nil && object["tagIds"] as? [String] == [tag.uuidString.lowercased()])
        let start = try #require(DateFormats.timestamp("2027-05-01T10:00:00Z"))
        let timed = EventSuggestionCreate(title: "B", time: .timed(start: start, end: start.addingTimeInterval(3600)), place: "Hof", note: "x", tagIds: [tag])
        object = try #require(JSONSerialization.jsonObject(with: JSONEncoder.api.encode(timed)) as? [String: Any])
        #expect(object["ganztaegig"] as? Bool == false && object["beginn"] as? String == "2027-05-01T10:00:00Z" && object["tagVon"] == nil)
        #expect(object["ort"] as? String == "Hof" && object["bemerkung"] as? String == "x")
    }

    @Test func roomsAndRequestsDecode() throws {
        let room = #"{"id":"\#(uuid1)","name":"Kellerraum","ort":null,"beschreibung":null,"kapazitaet":12,"aktiv":true,"team":{"id":"\#(uuid2)","name":"Material"}}"#
        let page = try decode(RoomPage.self, #"{"raeume":[\#(room)],"weitere":false,"naechste":null}"#)
        #expect(page.rooms.first?.capacity == 12 && page.rooms.first?.team?.name == "Material")
        let noTeam = try decode(Room.self, room.replacing(#""team":{"id":"\#(uuid2)","name":"Material"}"#, with: #""team":null"#))
        #expect(noTeam.team == nil)
        let requests = try decode(RoomRequestPage.self, #"{"anfragen":[\#(requestJSON)],"weitere":false,"naechste":null}"#)
        #expect(requests.requests.first?.status == .confirmed && requests.requests.first?.requesterName == nil)
        let open = try decode(RoomRequest.self, requestJSON.replacing(#""status":"bestaetigt""#, with: #""status":"angefragt","vonName":"Max Muster""#))
        #expect(open.status == .requested && open.requesterName == "Max Muster")
        #expect(try decode(RoomRequestState.self, #"{"id":"\#(uuid1)","status":"abgelehnt"}"#).status == .declined)
    }

    @Test func decisionEncodesWithAndWithoutReason() throws {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder.api.encode(RoomDecision.accept)) as? [String: Any])
        #expect(object["entscheid"] as? String == "annehmen" && object["begruendung"] == nil)
        object = try #require(JSONSerialization.jsonObject(with: JSONEncoder.api.encode(RoomDecision.decline(reason: "Besetzt"))) as? [String: Any])
        #expect(object["entscheid"] as? String == "ablehnen" && object["begruendung"] as? String == "Besetzt")
    }

    @Test func registrationFormDecodesFieldsAccountValuesAndAnswers() throws {
        let form = try decode(EventRegistrationForm.self, formJSON)
        #expect(form.registrationFor == .child && form.isOpen && form.deadline != nil && form.dayFrom != nil && form.start == nil)
        #expect(form.fields.map(\.kind) == [.choice, .unknown] && form.fields[0].options == ["normal", "vegi"] && form.fields[0].isRequired)
        let participant = try #require(form.participants.first)
        #expect(participant.childId != nil && participant.account.first?.value == "Mia")
        #expect(participant.registration?.status == .registered)
        #expect(participant.registration?.answers == ["essen": .text("vegi"), "allergie": .bool(false)])
    }

    @Test func answerBodyKeepsBooleanAndText() throws {
        let body = EventRegistrationBody(childId: nil, answers: ["a": .bool(true), "b": .text("x")])
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder.api.encode(body)) as? [String: Any])
        let answers = try #require(object["antworten"] as? [String: Any])
        #expect(object["kindId"] == nil && answers["a"] as? Bool == true && answers["b"] as? String == "x")
    }
}

private extension EventSuggestion {
    var beginnIsNil: Bool { start == nil && end == nil }
}

struct EventRulesTests {
    private func error(_ status: Int, _ code: String, _ message: String = "Servertext", extra: String = "") -> APIError {
        APIError.from(status: status, data: Data(#"{"code":"\#(code)","message":"\#(message)"\#(extra)}"#.utf8))
    }

    @Test func codesAreNamed() {
        #expect(EventRules.roomBookedCode == "RAUM_BELEGT" && EventRules.requestLimitCode == "ANFRAGE_LIMIT" && EventRules.invalidStateCode == "STATUS_UNGUELTIG")
        #expect(EventRules.timeInPastCode == "ZEIT_VERGANGEN" && EventRules.timeTooLongCode == "ZEIT_ZU_LANG" && EventRules.ownRequestCode == "EIGENE_ANFRAGE")
        #expect(EventRules.registrationClosedCode == "ANMELDUNG_GESCHLOSSEN" && EventRules.suggestionDecidedCode == "VORSCHLAG_ENTSCHIEDEN")
    }

    @Test func roomConflictsGetOwnTextAndInputErrorsKeepTheServerText() {
        let booked = EventRules.roomError(error(409, EventRules.roomBookedCode))
        #expect(booked.contains("schon gebucht") && booked != "Servertext")
        #expect(EventRules.roomError(error(400, EventRules.timeInPastCode, "Die Zeit liegt in der Vergangenheit.")) == "Die Zeit liegt in der Vergangenheit.")
        #expect(EventRules.roomError(error(409, "ANDERES", "Anderer Text")) == "Anderer Text")
        #expect(EventRules.roomError(error(409, EventRules.invalidStateCode)).contains("nicht mehr ändern"))
    }

    @Test func suggestionAndRegistrationTexts() {
        #expect(EventRules.suggestionError(error(409, EventRules.suggestionLimitCode)).contains("zehn offene"))
        #expect(EventRules.suggestionError(error(400, "TAG_UNBEKANNT", "Tag fehlt.")) == "Tag fehlt.")
        #expect(EventRules.registrationError(error(409, EventRules.registrationClosedCode)).contains("geschlossen"))
        #expect(EventRules.registrationError(error(400, "KIND_ID_PFLICHT", "Kind fehlt.")) == "Kind fehlt.")
    }

    @Test func answerErrorsCarryKeyAndCodeOnly() {
        let body = error(400, EventRules.answersInvalidCode, extra: #","fehler":[{"schluessel":"essen","code":"PFLICHT"},{"schluessel":"x","code":"UNBEKANNT"}]"#)
        let errors = EventRules.answerErrors(body)
        #expect(errors == [EventAnswerError(code: "PFLICHT", key: "essen"), EventAnswerError(code: "UNBEKANNT", key: "x")])
        #expect(EventRules.answerErrors(error(400, "UNGUELTIGE_EINGABE")) == nil)
        #expect(EventRules.answerErrors(error(409, EventRules.answersInvalidCode)) == nil)
        #expect(EventRules.answerErrorText("PFLICHT") != EventRules.answerErrorText("TYP"))
    }
}

struct EventServiceTests {
    private let id = UUID(), other = UUID()
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

    @Test func calendarRoutes() async throws {
        let from = try #require(DateFormats.calendarDay("2027-03-01")), to = try #require(DateFormats.calendarDay("2027-03-31"))
        var r = try await sent(#"{"termine":[],"weitere":false,"naechste":null}"#) { _ = try await $0.calendarEvents(from: from, to: to, after: "tok", limit: 20) }
        #expect(r.method == "GET" && r.path == "/api/v1/termine/mein" && r.query["von"] == "2027-03-01" && r.query["bis"] == "2027-03-31")
        #expect(r.query["limit"] == "20" && r.query["nach"] == "tok")
        r = try await sent(#"{"termine":[],"weitere":false,"naechste":null}"#) { _ = try await $0.calendarEvents(from: from, to: to) }
        #expect(r.query["nach"] == nil && r.query["limit"] == "50")
        r = try await sent(String(eventJSON.dropLast()) + #","treffpunkt":null,"schlussOrt":null,"schlussZeit":null,"mitnehmen":null,"teilnahmeOffen":true}"#) { _ = try await $0.calendarEvent(id: id) }
        #expect(r.method == "GET" && r.path == "/api/v1/termine/" + idText)
    }

    @Test func calendarLinkRoutes() async throws {
        var r = try await sent(#"{"aktiv":false,"erstelltAm":null,"zuletztAbgerufenAm":null,"endung":null}"#) { _ = try await $0.calendarLinkStatus() }
        #expect(r.method == "GET" && r.path == "/api/v1/ich/kalender-link")
        let token = String(repeating: "B", count: 43)
        r = try await sent(status: 201, #"{"token":"\#(token)","pfad":"/ical/\#(token).ics","erstelltAm":"2027-03-01T08:00:00Z","endung":"BBBB"}"#) {
            let link = try await $0.createCalendarLink()
            #expect(link.url(base: URL(string: "https://api.test.example.org")!)?.path == "/ical/\(token).ics")
        }
        #expect(r.method == "POST" && r.path == "/api/v1/ich/kalender-link" && r.body == nil)
        r = try await sent(status: 204, "") { try await $0.revokeCalendarLink() }
        #expect(r.method == "DELETE" && r.path == "/api/v1/ich/kalender-link")
    }

    @Test func suggestionRoutes() async throws {
        var r = try await sent(#"{"darfVorschlagen":false,"tags":[]}"#) { _ = try await $0.eventSuggestionOptions() }
        #expect(r.method == "GET" && r.path == "/api/v1/termin-vorschlaege/optionen")
        r = try await sent(#"{"vorschlaege":[],"weitere":false,"naechste":null}"#) { _ = try await $0.myEventSuggestions(after: other, limit: 10) }
        #expect(r.method == "GET" && r.path == "/api/v1/termin-vorschlaege/meine" && r.query["nach"] == otherText && r.query["limit"] == "10")
        let day = try #require(DateFormats.calendarDay("2027-05-01"))
        r = try await sent(status: 201, #"{"id":"\#(uuid1)","status":"offen"}"#) {
            let created = try await $0.createEventSuggestion(EventSuggestionCreate(title: "A", time: .allDay(from: day, to: day), tagIds: [other]))
            #expect(created.status == .open)
        }
        #expect(r.method == "POST" && r.path == "/api/v1/termin-vorschlaege" && r.body?["titel"] as? String == "A")
        r = try await sent(suggestionJSON) { _ = try await $0.eventSuggestion(id: id) }
        #expect(r.method == "GET" && r.path == "/api/v1/termin-vorschlaege/" + idText)
        r = try await sent(status: 204, "") { try await $0.withdrawEventSuggestion(id: id) }
        #expect(r.method == "DELETE" && r.path == "/api/v1/termin-vorschlaege/" + idText)
    }

    @Test func roomRoutes() async throws {
        var r = try await sent(#"{"raeume":[],"weitere":false,"naechste":null}"#) { _ = try await $0.rooms(after: "Keller", limit: 5) }
        #expect(r.method == "GET" && r.path == "/api/v1/raeume" && r.query["nach"] == "Keller" && r.query["limit"] == "5")
        let start = try #require(DateFormats.timestamp("2027-04-01T17:00:00Z"))
        r = try await sent(status: 201, #"{"id":"\#(uuid1)","status":"angefragt"}"#) {
            _ = try await $0.requestRoom(roomId: id, RoomRequestCreate(start: start, end: start.addingTimeInterval(7200), purpose: "Sitzung"))
        }
        #expect(r.method == "POST" && r.path == "/api/v1/raeume/\(idText)/anfragen" && r.body?["zweck"] as? String == "Sitzung" && r.body?["beginn"] as? String == "2027-04-01T17:00:00Z")
        r = try await sent(#"{"anfragen":[],"weitere":false,"naechste":null}"#) { _ = try await $0.myRoomRequests(after: other) }
        #expect(r.method == "GET" && r.path == "/api/v1/raeume/anfragen/meine" && r.query["nach"] == otherText)
        r = try await sent(#"{"anfragen":[],"weitere":false,"naechste":null}"#) { _ = try await $0.openRoomRequests() }
        #expect(r.method == "GET" && r.path == "/api/v1/raeume/anfragen/offen" && r.query["nach"] == nil)
        r = try await sent(status: 204, "") { try await $0.cancelRoomRequest(id: id) }
        #expect(r.method == "DELETE" && r.path == "/api/v1/raeume/anfragen/" + idText)
        r = try await sent(#"{"id":"\#(uuid1)","status":"abgelehnt"}"#) { _ = try await $0.decideRoomRequest(id: id, .decline(reason: "Besetzt")) }
        #expect(r.method == "POST" && r.path == "/api/v1/raeume/anfragen/\(idText)/entscheid" && r.body?["entscheid"] as? String == "ablehnen")
    }

    @Test func roomConflictReachesTheCallerWithItsCode() async throws {
        let host = "a\(UUID().uuidString.prefix(8).lowercased()).test.example.org"
        StubProtocol.register(host: host) { _ in (409, [:], Data(#"{"code":"RAUM_BELEGT","message":"Der Raum ist belegt."}"#.utf8)) }
        let client = APIClient(
            baseURL: URL(string: "https://\(host)")!, appVersion: "1.0.0", cookieStore: InMemoryCookieStore(["s": "1"]),
            session: APIClient.makeSession(protocolClasses: [StubProtocol.self])
        )
        do {
            _ = try await client.requestRoom(roomId: id, RoomRequestCreate(start: .now, end: .now, purpose: "x"))
            Issue.record("expected a conflict")
        } catch let error as APIError {
            #expect(error.kind == .conflict && error.code == EventRules.roomBookedCode)
        }
    }

    @Test func registrationRoutes() async throws {
        var r = try await sent(formJSON) { _ = try await $0.eventRegistrationForm(occasionId: id) }
        #expect(r.method == "GET" && r.path == "/api/v1/anlaesse/" + idText)
        let registration = #"{"id":"\#(uuid1)","status":"angemeldet","antworten":{"essen":"vegi"},"geaendertAm":"2027-06-01T08:00:00Z"}"#
        r = try await sent(registration) { _ = try await $0.registerForEvent(occasionId: id, childId: other, answers: ["essen": .text("vegi")]) }
        #expect(r.method == "PUT" && r.path == "/api/v1/anlaesse/\(idText)/anmeldung" && r.body?["kindId"] as? String == otherText)
        #expect((r.body?["antworten"] as? [String: Any])?["essen"] as? String == "vegi")
        r = try await sent(registration) { _ = try await $0.registerForEvent(occasionId: id, childId: nil, answers: [:]) }
        #expect(r.body?["kindId"] == nil)
        r = try await sent(status: 204, "") { try await $0.unregisterFromEvent(occasionId: id, childId: other) }
        #expect(r.method == "DELETE" && r.path == "/api/v1/anlaesse/\(idText)/anmeldung" && r.query["kindId"] == otherText)
        r = try await sent(status: 204, "") { try await $0.unregisterFromEvent(occasionId: id, childId: nil) }
        #expect(r.query["kindId"] == nil)
    }
}
