import Foundation
import Testing
@testable import CeviOS

struct ProgramTests {
    private static func json(
        id: String = "11111111-1111-1111-1111-111111111111",
        status: String = "aktiv",
        allDay: Bool = false,
        start: String? = "2026-11-07T13:00:00.000Z",
        end: String? = "2026-11-07T16:00:00.000Z",
        dayFrom: String? = nil,
        dayTo: String? = nil,
        children: String = "[]",
        extra: String = ""
    ) -> Data {
        func q(_ s: String?) -> String { s.map { "\"\($0)\"" } ?? "null" }
        return Data("""
        {"id":"\(id)","titel":"Treff","status":"\(status)","sichtbarkeit":"eltern","ganztaegig":\(allDay),
         "beginn":\(q(start)),"ende":\(q(end)),"tagVon":\(q(dayFrom)),"tagBis":\(q(dayTo)),"googleOrt":null,
         "stufen":[{"id":"22222222-2222-2222-2222-222222222222","name":"Stufe A"}],"googleBeschreibung":null,
         "kinder":\(children)\(extra)}
        """.utf8)
    }

    private func decode(_ data: Data) throws -> Program {
        try JSONDecoder.api.decode(Program.self, from: data)
    }

    @Test func decodesListEntryWithChildAnswers() throws {
        let children = #"[{"id":"33333333-3333-3333-3333-333333333333","vorname":"Mia","status":"ja"},{"id":"44444444-4444-4444-4444-444444444444","vorname":"Leo","status":null}]"#
        let program = try decode(Self.json(children: children))
        #expect(program.status == .active)
        #expect(program.children.map(\.answer) == [.yes, nil])
        #expect(program.units.first?.name == "Stufe A")
        #expect(program.isRegistrationOpen == nil)
    }

    @Test func decodesDetailFields() throws {
        let extra = #","treffpunkt":"14:00 Uhr","schlussOrt":null,"schlussZeit":"17:00","mitnehmen":"Wasser","teilnahmeOffen":false,"eigeneAnmeldung":"offen""#
        let program = try decode(Self.json(extra: extra))
        #expect(program.meetingPoint == "14:00 Uhr")
        #expect(program.isRegistrationOpen == false)
        #expect(!program.canAnswer)
        #expect(program.ownRegistration == .open)
        #expect(program.ownRegistration?.answer == nil)
    }

    @Test func reviewAndCancelledStatusesAreDecoded() throws {
        #expect(try decode(Self.json(status: "pruefen")).status == .review)
        #expect(try decode(Self.json(status: "abgesagt")).status == .cancelled)
    }

    @Test func multiDayAllDayProgramAppearsOnEveryDay() throws {
        let program = try decode(Self.json(allDay: true, start: nil, end: nil, dayFrom: "2026-07-10", dayTo: "2026-07-12"))
        #expect(program.days.map(DateFormats.calendarDayText) == ["2026-07-10", "2026-07-11", "2026-07-12"])
    }

    @Test func timedProgramOverMidnightCoversBothDays() throws {
        // 22:00 to 02:00 Swiss time (UTC+1 in November).
        let program = try decode(Self.json(start: "2026-11-07T21:00:00Z", end: "2026-11-08T01:00:00Z"))
        #expect(program.days.map(DateFormats.calendarDayText) == ["2026-11-07", "2026-11-08"])
    }

    @Test func programEndingAtMidnightDoesNotSpillIntoTheNextDay() throws {
        let program = try decode(Self.json(start: "2026-11-07T21:00:00Z", end: "2026-11-07T23:00:00Z"))
        #expect(program.days.map(DateFormats.calendarDayText) == ["2026-11-07"])
    }

    @Test func sectionsGroupByDayAndCutAtTheWindow() throws {
        let long = try decode(Self.json(id: "55555555-5555-5555-5555-555555555555", allDay: true, start: nil, end: nil, dayFrom: "2026-07-10", dayTo: "2026-07-14"))
        let short = try decode(Self.json(id: "66666666-6666-6666-6666-666666666666", allDay: true, start: nil, end: nil, dayFrom: "2026-07-11", dayTo: "2026-07-11"))
        let from = try #require(DateFormats.calendarDay("2026-07-11"))
        let to = try #require(DateFormats.calendarDay("2026-07-12"))
        let sections = ProgramListModel.sections(for: [long, short], from: from, to: to)
        #expect(sections.map { DateFormats.calendarDayText($0.day) } == ["2026-07-11", "2026-07-12"])
        #expect(sections[0].programs.count == 2)
        #expect(sections[1].programs.count == 1)
    }
}

struct ParticipationTests {
    @Test func closedProgramShowsClearMessageAndReloads() {
        let error = APIError.from(status: 409, data: Data(#"{"code":"PROGRAMM_GESCHLOSSEN","message":"x"}"#.utf8))
        let message = ParticipationMessages.message(for: error)
        #expect(message.reload)
        #expect(message.text.contains("nicht mehr möglich"))
    }

    @Test func forbiddenAndNotFoundReload() {
        #expect(ParticipationMessages.message(for: .from(status: 403, data: Data())).reload)
        #expect(ParticipationMessages.message(for: .from(status: 404, data: Data())).reload)
    }

    @Test func otherErrorsShowTheServerTextWithoutReload() {
        let error = APIError.from(status: 429, data: Data())
        let message = ParticipationMessages.message(for: error)
        #expect(!message.reload)
        #expect(message.text == "Bitte kurz warten.")
    }

    @Test func answerIsSentAsPutWithStatusBody() async throws {
        let host = "a\(UUID().uuidString.prefix(8).lowercased()).test.example.org"
        StubProtocol.register(host: host) { _ in (204, [:], Data()) }
        let client = APIClient(
            baseURL: URL(string: "https://\(host)")!, appVersion: "1.0.0", cookieStore: InMemoryCookieStore(["s": "1"]),
            session: APIClient.makeSession(protocolClasses: [StubProtocol.self])
        )
        let program = UUID(), child = UUID()
        try await client.setParticipation(programId: program, childId: child, answer: .no)
        let request = try #require(StubProtocol.requests(host: host).first)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path == "/api/v1/programme/\(program.uuidString.lowercased())/teilnahmen/\(child.uuidString.lowercased())")
    }
}
