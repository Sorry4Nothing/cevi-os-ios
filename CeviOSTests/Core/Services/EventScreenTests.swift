import Foundation
import Testing
@testable import CeviOS

/// Models of the screens K1 to K4, A1 to A4, A6 and A7, against the simulated server of the UI tests.
@MainActor
struct EventScreenTests {
    private struct Credentials: Encodable { let username: String; let password: String }

    private func client(_ username: String) async throws -> APIClient {
        let client = APIClient(
            baseURL: URL(string: "https://ui-test.example.org")!, appVersion: "1.0.0", cookieStore: InMemoryCookieStore(),
            session: APIClient.makeSession(protocolClasses: [UITestBackend.self])
        )
        try await client.send("POST", "/api/auth/sign-in/username", body: Credentials(username: username, password: "geheim-geheim"))
        return client
    }

    private func decode<T: Decodable>(_ json: String) throws -> T { try JSONDecoder.api.decode(T.self, from: Data(json.utf8)) }

    private var future: Date { Date.now.addingTimeInterval(3 * 86_400) }

    // MARK: A1 to A4

    @Test func eventBecomesAProgramWithUnitsOtherTagsAndPlace() throws {
        let event: CalendarEvent = try decode("""
        {"id":"0190a000-0000-7000-8000-000000000001","titel":"Waldspiel","status":"neu","ganztaegig":false,"beginn":"2027-03-06T13:00:00Z",
         "ende":"2027-03-06T16:00:00Z","tagVon":null,"tagBis":null,"ort":"Pfadiheim","anlass":null,"kinder":[],
         "tags":[{"id":"0190a000-0000-7000-8000-000000000002","name":"Wölfe","typ":"stufe"},
                 {"id":"0190a000-0000-7000-8000-000000000003","name":"Team Mat","typ":"team"}]}
        """)
        let program = Program(event: event)
        #expect(program.units.map(\.name) == ["Wölfe"] && program.otherTags.map(\.name) == ["Team Mat"] && program.place == "Pfadiheim")
        // An unknown status never offers answers.
        #expect(program.status == .review)
    }

    @Test func childrenAnswersAreSummarisedWithoutNames() {
        func child(_ answer: Answer?) -> ProgramChild { ProgramChild(id: UUID(), firstName: "X", answer: answer) }
        #expect(ProgramAnswerSummary.lines(for: []).isEmpty)
        #expect(ProgramAnswerSummary.lines(for: [child(nil), child(.yes)]) == [.open(1)])
        #expect(ProgramAnswerSummary.lines(for: [child(.no), child(nil), child(nil)]) == [.open(2), .declined(1)])
        #expect(ProgramAnswerSummary.lines(for: [child(.yes), child(.yes)]) == [.allYes(2)])
    }

    @Test func parentsListShowsOnlyTheirUnitsEvents() async throws {
        let client = try await client("eltern.test")
        let model = ProgramListModel()
        await model.load(client: client)
        #expect(model.state == .loaded)
        let titles = model.sections.flatMap(\.programs).map(\.title)
        #expect(titles.contains("Waldnachmittag") && titles.contains("Sommerlager Beispiel 2027"))
        let camp = try #require(model.sections.flatMap(\.programs).first { $0.title.hasPrefix("Sommerlager") })
        #expect(camp.occasion?.isOpen == true && camp.units.map(\.name) == ["Jungschar"])
    }

    @Test func subtitleNamesTheGroupsOfTheChildrenOrOfTheLeader() throws {
        let unit = "11111111-1111-1111-1111-111111111111"
        func profile(children: String, roles: String) throws -> Profile {
            try decode("""
            {"id":"22222222-2222-2222-2222-222222222222","name":"T","ceviName":null,"benutzername":"t","mussPasswortAendern":false,
             "datenschutzGelesenAm":null,"telefon":null,"bildUrl":null,"pushChat":true,"pushProgramme":true,"geschlecht":null,"abteilungsleitung":false,"entwickler":false,"clientArt":"web","rechte":[],
             "rollen":[\(roles)],"stufen":[{"id":"\(unit)","name":"Wölfe","kuerzel":"W"}],"kinder":[\(children)]}
            """)
        }
        let child = #"{"id":"33333333-3333-3333-3333-333333333333","vorname":"M","nachname":"N","stufeId":"\#(unit)"}"#
        #expect(ProgramListModel.subtitle(for: try profile(children: child, roles: "")) == "Gruppen deiner Kinder: Wölfe")
        #expect(ProgramListModel.subtitle(for: try profile(children: "", roles: #"{"stufeId":"\#(unit)","typ":"leitung"}"#)) == "Deine Gruppen: Wölfe")
        #expect(ProgramListModel.subtitle(for: nil) == nil)
    }

    @Test func detailComesFromTheEventAndShowsLeaderCounts() async throws {
        let client = try await client("leitung.test")
        let model = ProgramDetailModel()
        let forest = UUID(uuidString: World.Ids.forest)!
        await model.load(programId: forest, client: client)
        let program = try #require(model.program)
        #expect(program.title == "Waldnachmittag" && program.meetingPoint == "Bahnhof Beispielstadt" && program.ownRegistration == .open)
        await model.loadChildCounts(programId: forest, client: client)
        #expect(model.childCounts != nil)
    }

    // MARK: K1

    @Test func suggestionFormChecksTitleGroupAndTime() {
        let now = Date.now
        let ok = SuggestEventModel.validate(title: "Elternabend", tagCount: 1, start: now.addingTimeInterval(3600), end: now.addingTimeInterval(7200), now: now)
        #expect(ok.isEmpty)
        let bad = SuggestEventModel.validate(title: "  ", tagCount: 0, start: now.addingTimeInterval(7200), end: now.addingTimeInterval(3600), now: now)
        #expect(bad.title != nil && bad.tags == "Wähle mindestens eine Gruppe." && bad.time != nil)
        #expect(SuggestEventModel.validate(title: "x", tagCount: 1, start: now.addingTimeInterval(-7200), end: now.addingTimeInterval(-3600), now: now).time != nil)
    }

    @Test func parentsMaySeeNoSuggestionForm() async throws {
        let model = SuggestEventModel()
        await model.load(client: try await client("eltern.test"))
        #expect(model.phase == .noRight)
    }

    @Test func leaderSendsAndWithdrawsASuggestion() async throws {
        let client = try await client("leitung.test")
        let model = SuggestEventModel()
        await model.load(client: client)
        #expect(model.phase == .ready && !model.tags.isEmpty)
        // Nothing is sent while a field is missing.
        await model.send(client: client)
        #expect(model.sent == nil && model.errors.title != nil && model.errors.tags != nil)
        model.title = "Elternabend Sommerlager"
        model.toggle(model.tags[0])
        await model.send(client: client)
        let sent = try #require(model.sent)
        #expect(model.errors.isEmpty && sent.groups == [model.tags[0].name] && model.summaryText != nil)
        await model.undo(client: client)
        #expect(model.sent == nil && model.title == "Elternabend Sommerlager")
    }

    // MARK: K2 and K3

    @Test func bookedRoomShowsItsReasonAndFreeRoomIsRequested() async throws {
        let client = try await client("leitung.test")
        let model = RequestRoomModel()
        await model.load(client: client)
        #expect(model.phase == .ready && model.rooms.count == 2 && model.roomId == model.rooms.first?.id)
        model.purpose = "Elternabend vorbereiten"
        model.roomId = UUID(uuidString: World.roomBooked)
        await model.send(client: client)
        #expect(model.sent == nil && model.bookedMessage?.contains("schon gebucht") == true)
        model.roomId = UUID(uuidString: World.roomMain)
        await model.send(client: client)
        let sent = try #require(model.sent)
        #expect(model.bookedMessage == nil && sent.roomName == "Pfadiheim Beispielwald")
        await model.undo(client: client)
        #expect(model.sent == nil)
    }

    @Test func roomFormNeedsRoomPurposeAndTime() {
        let now = Date.now
        let errors = RequestRoomModel.validate(roomId: nil, purpose: "", start: now.addingTimeInterval(60), end: now, now: now)
        #expect(errors.room != nil && errors.purpose != nil && errors.time != nil)
    }

    @Test func ownRoomRequestsLoadWithTheirStates() async throws {
        let model = MyRoomRequestsModel()
        await model.load(client: try await client("leitung.test"))
        #expect(model.phase == .loaded)
        #expect(Set(model.requests.map(\.status)).isSuperset(of: [.confirmed, .declined]))
        #expect(MyRoomRequestsModel.chip(for: .requested) == .open && MyRoomRequestsModel.chip(for: .cancelled) == .cancelled)
    }

    // MARK: K4

    private let occasion = UUID(uuidString: World.occasion)!

    @Test func registrationFormChecksRequiredFieldsAndOptions() throws {
        let fields: [EventField] = try decode("""
        [{"schluessel":"a","beschriftung":"A","typ":"ja_nein","optionen":[],"pflicht":true},
         {"schluessel":"b","beschriftung":"B","typ":"auswahl","optionen":["1","2"],"pflicht":true},
         {"schluessel":"c","beschriftung":"C","typ":"text","optionen":[],"pflicht":false}]
        """)
        #expect(EventRegistrationModel.validate(fields: fields, answers: [:]).keys.sorted() == ["a", "b"])
        #expect(EventRegistrationModel.validate(fields: fields, answers: ["a": .bool(true), "b": .text("3")]).keys.sorted() == ["b"])
        #expect(EventRegistrationModel.validate(fields: fields, answers: ["a": .bool(false), "b": .text("2"), "c": .text("ok")]).isEmpty)
        #expect(EventRegistrationModel.validate(fields: fields, answers: ["a": .bool(true), "b": .text("1"), "c": .text(String(repeating: "x", count: 501))])["c"] != nil)
    }

    @Test func parentRegistersAChildAndUndoes() async throws {
        let client = try await client("eltern.test")
        let model = EventRegistrationModel(occasionId: occasion)
        await model.load(client: client)
        #expect(model.phase == .ready && model.form?.participants.count == 2 && model.form?.registrationFor == .child)
        #expect(model.participant?.account.contains { $0.label == "Stufe" } == true)
        // Without the required answers nothing is sent.
        await model.send(client: client)
        #expect(model.sent == nil && model.fieldErrors.keys.contains("schwimmt"))
        let fields = try #require(model.form?.fields)
        model.set(.bool(true), for: fields[0])
        model.set(.text("152"), for: fields[1])
        model.selectParticipant(1)
        #expect(model.answers.isEmpty)
        model.selectParticipant(0)
        model.set(.bool(true), for: fields[0])
        model.set(.text("152"), for: fields[1])
        await model.send(client: client)
        let sent = try #require(model.sent)
        #expect(sent.canUndo && sent.rows.contains("T-Shirt-Grösse: 152") && sent.rows.contains("Mein Kind schwimmt sicher: Ja"))
        await model.unregister(client: client)
        #expect(model.sent == nil && !model.isRegistered)
    }

    @Test func headerLineNamesDatesAndDeadline() throws {
        let form: EventRegistrationForm = try decode("""
        {"id":"0190a000-0000-7000-8000-000000000001","terminId":"0190a000-0000-7000-8000-000000000002","titel":"Lager","ganztaegig":true,
         "beginn":null,"ende":null,"tagVon":"2027-07-17","tagBis":"2027-07-24","anmeldungOffen":false,"frist":"2027-03-31T10:00:00Z",
         "anmeldungFuer":"kind","felder":[],"teilnehmende":[]}
        """)
        #expect(form.headerLine == "17. Juli bis 24. Juli 2027, Anmeldeschluss war am 31. März")
    }

    // MARK: A6 and A7

    @Test func calendarLinkIsCreatedOnceShownOnceAndRevoked() async throws {
        let client = try await client("eltern.test")
        let model = CalendarLinkModel()
        await model.load(client: client)
        await model.create(client: client)
        let link = try #require(model.newLink)
        #expect(model.phase == .loaded(try #require(try? await client.calendarLinkStatus())))
        #expect(link.url(base: URL(string: "https://ui-test.example.org")!)?.path().hasSuffix(".ics") == true)
        #expect(!"\(link)".contains("ui-test-token"))
        await model.revoke(client: client)
        if case .loaded(let status) = model.phase { #expect(!status.isActive) } else { Issue.record("not loaded") }
    }

    @Test func notificationGroupsFollowTheKindsOfTheServer() async throws {
        let model = NotificationsModel()
        await model.load(client: try await client("leitung.test"))
        #expect(model.phase == .loaded)
        #expect(model.visibleGroups.map(\.id).starts(with: ["tasks", "mentions"]))
        let tasks = try #require(model.visibleGroups.first)
        #expect(!model.isOn(tasks))
    }

    @Test func profileGroupsNameUnitsFunctionAndCamps() throws {
        let unit = "11111111-1111-1111-1111-111111111111"
        let profile: Profile = try decode("""
        {"id":"22222222-2222-2222-2222-222222222222","name":"T","ceviName":null,"benutzername":"t","mussPasswortAendern":false,
         "datenschutzGelesenAm":null,"telefon":null,"bildUrl":null,"pushChat":true,"pushProgramme":true,"geschlecht":null,"abteilungsleitung":false,"entwickler":false,"clientArt":"web","rechte":[],
         "rollen":[{"stufeId":"\(unit)","typ":"stufenleitung"}],"stufen":[{"id":"\(unit)","name":"Wölfe","kuerzel":"W"}],"kinder":[]}
        """)
        #expect(ProfileGroups.names(for: profile, camps: ["Sommerlager"]) == ["Stufe Wölfe", "Funktion Stufenleitung", "Lager Sommerlager"])
    }
}
