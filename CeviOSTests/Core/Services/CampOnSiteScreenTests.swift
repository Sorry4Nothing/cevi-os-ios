import Foundation
import Testing
@testable import CeviOS

private nonisolated let campUUID = UUID(uuidString: "0190a000-0000-7000-8000-000000000001")!
private nonisolated let meUUID = UUID(uuidString: "0190a000-0000-7000-8000-0000000000aa")!
private nonisolated func uid(_ n: Int) -> String { "0190a000-0000-7000-8000-0000000088\(String(format: "%02d", n))" }

@MainActor
private func campActive(_ role: CampRole = .campLeader, status: String = "aktiv", host: String) throws -> ActiveCamp {
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
private func host() -> String { "o\(UUID().uuidString.prefix(8).lowercased()).test.example.org" }

private func stub(_ host: String, _ handler: @escaping @Sendable (URLRequest) -> (Int, String)) {
    StubProtocol.register(host: host) { request in
        let (status, body) = handler(request)
        return (status, [:], Data(body.utf8))
    }
}

private nonisolated func path(_ request: URLRequest) -> String { request.url?.path ?? "" }
private nonisolated func body(_ request: URLRequest) -> String { StubProtocol.body(of: request).map { String(decoding: $0, as: UTF8.self) } ?? "" }
private let day3 = DateFormats.calendarDay("2027-07-19") ?? Date()

struct CampOnSiteRightsTests {
    @Test func rolesGetTheirActions() {
        func rights(_ role: CampRole, readOnly: Bool = false) -> CampOnSiteRights { CampOnSiteRights(role: role, readOnly: readOnly) }
        let lead = rights(.campLeader)
        #expect(lead.readsMatrix && lead.decidesRequests && lead.editsPackingTemplate && lead.reordersInfos && lead.seesShopping && lead.seesAllInfos)
        #expect(rights(.leader).setsAttendance && !rights(.leader).readsMatrix && rights(.leader).editsShopping && !rights(.leader).reordersInfos)
        #expect(rights(.team).setsAttendance && !rights(.team).seesShopping && rights(.team).ticksPacking && !rights(.team).seesAllInfos)
        #expect(!rights(.readOnly).setsAttendance && !rights(.readOnly).ticksPacking)
        let closed = rights(.campLeader, readOnly: true)
        #expect(!closed.decidesRequests && !closed.editsShopping && !closed.ticksPacking && !closed.reordersInfos && closed.readsMatrix)
    }

    @Test func textsFollowTheDesign() {
        let from = DateFormats.calendarDay("2027-07-17")!, to = DateFormats.calendarDay("2027-07-24")!
        #expect(CampOnSiteText.campDay(day3, from: from, to: to).hasPrefix("Tag 3 von 8, "))
        #expect(!CampOnSiteText.campDay(from.addingTimeInterval(-86400 * 3), from: from, to: to).hasPrefix("Tag"))
        #expect(CampOnSiteText.timeRange("07:00–10:00") == "07:00 bis 10:00" && CampOnSiteText.timeRange(" ") == nil)
        #expect(CampOnSiteText.amount(6, unit: "kg") == "6 kg" && ["1.5", "1,5"].contains(CampOnSiteText.amount(1.5, unit: nil)))
        #expect(CampOnSiteText.amount(nil, unit: "kg") == nil)
        #expect(CampOnSiteText.warning(.thunderstorm) == "Gewitter möglich" && CampOnSiteText.warning(.unknown) == nil)
        #expect(CampOnSiteText.value(.present) == "Da" && CampOnSiteText.value(.absent) == "Frei" && CampOnSiteText.value(.open) == "Offen")
    }

    @Test func rescueNumbersCallThroughTelUrls() {
        #expect(CampEmergencyModel.rescue.compactMap(\.phoneURL).map(\.absoluteString) == ["tel:144", "tel:1414"])
    }
}

@MainActor
struct CampTodayModelTests {
    private nonisolated static func today(tasks: String = "[]") -> String {
        """
        {"datum":"2027-07-19","lagertag":{"id":"\(uid(1))","datum":"2027-07-19","label":null},
         "tagesseite":{"seite":null,"bloecke":[{"id":"\(uid(2))","version":1,"seiteId":"\(uid(3))","art":"wichtig","text":"Abfahrt um 13:30","dateiId":null,"reihenfolge":0,"datei":null},
                                              {"id":"\(uid(4))","version":1,"seiteId":"\(uid(3))","art":"idee","text":"Singen","dateiId":null,"reihenfolge":1,"datei":null}],"aufgaben":\(tasks)},
         "wetter":null,"anwesenheit":null,"schichten":null,"hoecks":null}
        """
    }

    private nonisolated static func task(_ n: Int, status: String, mine: Bool = true) -> String {
        """
        {"id":"\(uid(10 + n))","version":2,"titel":"Aufgabe \(n)","ressortId":null,"teil":null,"verantwortlichPersonId":"\(mine ? meUUID.uuidString : uid(99))","status":"\(status)",
         "notiz":null,"frist":"2027-07-19","fristMeilensteinId":null,"fristVersatzTage":null,"stern":false,"laufend":false,"spaeterAb":null,"wiederholung":null,
         "reihenfolge":\(n),"quelle":null,"erledigtAm":null,"verantwortlich":null,"ressort":null,"unterstuetzung":[]}
        """
    }

    @Test func showsOnlyOwnTodosAndImportantBlocks() async throws {
        let host = host()
        stub(host) { request in
            switch path(request) {
            case let p where p.hasSuffix("/heute"): (200, Self.today(tasks: "[\(Self.task(1, status: "offen")),\(Self.task(2, status: "offen", mine: false))]"))
            case let p where p.hasSuffix("/meine-woche"): (200, #"{"von":"2027-07-19","bis":"2027-07-26","aufgaben":[],"schichten":[],"hoecks":[]}"#)
            default: (404, #"{"code":"NICHT_GEFUNDEN","message":"x"}"#)
            }
        }
        let model = CampTodayModel(active: try campActive(host: host), personId: meUUID)
        model.now = { day3 }
        await model.load()
        #expect(model.phase == .loaded && model.todos.map(\.title) == ["Aufgabe 1"] && model.important.map(\.text) == ["Abfahrt um 13:30"])
        #expect(model.shifts.isEmpty && !model.isEmpty && model.headline.hasPrefix("Tag 3 von 8"))
    }

    @Test func emptyDayAndDeniedAccess() async throws {
        let host = host()
        stub(host) { _ in (403, #"{"code":"KEINE_BERECHTIGUNG","message":"x"}"#) }
        let model = CampTodayModel(active: try campActive(.readOnly, host: host), personId: meUUID)
        await model.load()
        if case .failed(let state, _) = model.phase { #expect(state == .noAccess) } else { Issue.record("expected a failure") }
        #expect(model.isEmpty)
    }

    @Test func tickingSendsTheStatusWithTheRowVersion() async throws {
        let host = host()
        stub(host) { request in
            if request.httpMethod == "PUT" { return (200, Self.task(1, status: "erledigt")) }
            return (200, Self.today(tasks: "[\(Self.task(1, status: "offen"))]"))
        }
        let model = CampTodayModel(active: try campActive(.team, host: host), personId: meUUID)
        await model.load()
        await model.toggle(try #require(model.todos.first))
        let put = try #require(StubProtocol.requests(host: host).first { $0.httpMethod == "PUT" })
        #expect(path(put).hasSuffix("/status") && body(put).contains("\"version\":2") && body(put).contains("erledigt"))
        #expect(model.isDone(model.todos[0]))
    }

    @Test func readOnlyRoleCannotTick() async throws {
        let host = host()
        stub(host) { _ in (200, Self.today(tasks: "[\(Self.task(1, status: "offen"))]")) }
        let model = CampTodayModel(active: try campActive(.readOnly, host: host), personId: meUUID)
        await model.load()
        await model.toggle(model.todos[0])
        #expect(StubProtocol.requests(host: host).allSatisfy { $0.httpMethod == "GET" })
    }

    @Test func offlineTickWaitsInTheQueue() async throws {
        // A host without a registered reply answers like a missing network.
        let active = try campActive(.team, host: host())
        let model = CampTodayModel(active: active, personId: meUUID)
        model.todos = [try JSONDecoder.api.decode(CampTask.self, from: Data(Self.task(1, status: "offen").utf8))]
        await model.toggle(model.todos[0])
        #expect(model.queuedIds.count == 1 && model.isDone(model.todos[0]) && active.waitingCount == 1)
    }
}

@MainActor
struct CampAttendanceScreenModelTests {
    private nonisolated static let schedule = """
    {"meilensteine":[],"lagertage":[{"id":"\(uid(1))","version":1,"datum":"2027-07-19","label":null}],
     "tagesabschnitte":[{"id":"\(uid(2))","version":1,"name":"Vormittag","zeit":null,"reihenfolge":0},{"id":"\(uid(3))","version":1,"name":"Abend","zeit":null,"reihenfolge":1}]}
    """
    private nonisolated static let ownJSON = """
    {"eintraege":[{"id":"\(uid(4))","version":3,"personId":"\(meUUID)","teilnehmerId":null,"lagertagId":"\(uid(1))","tagesabschnittId":"\(uid(2))","wert":"A"}],"anfragen":[],"frist":null}
    """

    @Test func teamSeesOnlyTheOwnRowAndSetsOpenFields() async throws {
        let host = host()
        stub(host) { request in
            switch (request.httpMethod ?? "", path(request)) {
            case (_, let p) where p.hasSuffix("/zeitplan"): return (200, Self.schedule)
            case ("PUT", _): return (200, #"{"eintraege":[{"id":"\#(uid(5))","version":1,"personId":"\#(meUUID)","teilnehmerId":null,"lagertagId":"\#(uid(1))","tagesabschnittId":"\#(uid(3))","wert":"A"}]}"#)
            default: return (200, Self.ownJSON)
            }
        }
        let model = CampAttendanceModel(active: try campActive(.team, host: host), personId: meUUID, ownLabel: "Mara (Luchs)")
        model.now = { day3 }
        await model.load()
        let row = try #require(model.rows.first)
        #expect(model.rows.count == 1 && row.label == "Mara (Luchs)" && row.cells.map(\.value) == [.present, .open] && model.canSet)
        await model.setWholeDay(row)
        let put = try #require(StubProtocol.requests(host: host).first { $0.httpMethod == "PUT" })
        #expect(path(put).hasSuffix("/anwesenheit/eigene") && body(put).contains("\"wert\":\"A\""))
        #expect(model.rows[0].cells.map(\.value) == [.present, .present])
    }

    @Test func aSetFieldNeedsARequestAndTheRequestIsSent() async throws {
        let host = host()
        let blocked = #"{"code":"ANFRAGE_NOETIG","message":"x","gesperrt":[{"lagertagId":"\#(uid(1))","tagesabschnittId":"\#(uid(2))","grund":"eingetragen"}]}"#
        stub(host) { request in
            switch (request.httpMethod ?? "", path(request)) {
            case (_, let p) where p.hasSuffix("/zeitplan"): return (200, Self.schedule)
            case ("PUT", _): return (409, blocked)
            case ("POST", _):
                return (200, #"{"anfragen":[{"id":"\#(uid(6))","version":1,"personId":"\#(meUUID)","lagertagId":"\#(uid(1))","tagesabschnittId":"\#(uid(2))","wert":"F","notiz":"Arzt","status":"offen","entschiedenVon":null,"entschiedenAm":null,"erstelltAm":"2027-07-18T08:00:00Z"}]}"#)
            default: return (200, Self.ownJSON)
            }
        }
        let model = CampAttendanceModel(active: try campActive(.team, host: host), personId: meUUID, ownLabel: "Mara")
        model.now = { day3 }
        await model.load()
        await model.set(model.rows[0], section: UUID(uuidString: uid(2))!, to: .absent)
        let pending = try #require(model.pending)
        #expect(pending.fields.count == 1 && model.entries[0].value == .present)
        await model.sendRequest(note: " Arzt ")
        let post = try #require(StubProtocol.requests(host: host).first { $0.httpMethod == "POST" })
        #expect(path(post).hasSuffix("/anwesenheit/anfragen") && body(post).contains("Arzt") && model.pending == nil)
        #expect(model.rows[0].cells[0].requested == .absent && model.notice?.title == "Anfrage gesendet.")
    }

    @Test func leadershipSetsOtherPeopleWithTheVersionAndDecides() async throws {
        let host = host()
        let person = uid(7)
        stub(host) { request in
            switch (request.httpMethod ?? "", path(request)) {
            case (_, let p) where p.hasSuffix("/zeitplan"): return (200, Self.schedule)
            case (_, let p) where p.hasSuffix("/count") || p.hasSuffix("/abzaehlen") || p.contains("abz"):
                return (200, #"{"eintraege":[{"id":"\#(uid(8))","personId":"\#(person)","name":"Lea","ceviName":"Biber","geprueft":false}],"naechster":null,"da":0,"gesamt":1}"#)
            case ("PUT", _): return (200, #"{"eintraege":[{"id":"\#(uid(5))","version":4,"personId":"\#(person)","teilnehmerId":null,"lagertagId":"\#(uid(1))","tagesabschnittId":"\#(uid(2))","wert":"A"}]}"#)
            case ("POST", _): return (200, #"{"anfragen":[]}"#)
            case (_, let p) where p.hasSuffix("/anfragen"):
                return (200, #"{"anfragen":[{"id":"\#(uid(6))","version":2,"personId":"\#(person)","lagertagId":"\#(uid(1))","tagesabschnittId":"\#(uid(2))","wert":"F","notiz":null,"status":"offen","entschiedenVon":null,"entschiedenAm":null,"erstelltAm":"2027-07-18T08:00:00Z"}],"naechster":null}"#)
            default: return (200, #"{"eintraege":[{"id":"\#(uid(9))","version":3,"personId":"\#(person)","teilnehmerId":null,"lagertagId":"\#(uid(1))","tagesabschnittId":"\#(uid(2))","wert":"F"}],"naechster":null,"frist":null}"#)
            }
        }
        let model = CampAttendanceModel(active: try campActive(host: host), personId: meUUID, ownLabel: "Ich")
        model.now = { day3 }
        await model.load()
        #expect(model.rows.map(\.label) == ["Lea (Biber)"] || model.rows.map(\.label) == ["Person"])
        #expect(model.openRequests.count == 1 && model.openRequests[0].text.contains("auf «Frei» ändern"))
        await model.set(model.rows[0], section: UUID(uuidString: uid(2))!, to: .present)
        let put = try #require(StubProtocol.requests(host: host).first { $0.httpMethod == "PUT" })
        #expect(path(put).hasSuffix("/anwesenheit") && body(put).contains("\"version\":3") && body(put).lowercased().contains(person))
        await model.decide(model.openRequests[0], .accepted)
        let post = try #require(StubProtocol.requests(host: host).first { $0.httpMethod == "POST" })
        #expect(path(post).hasSuffix("/anfragen/entscheid") && body(post).contains("angenommen") && body(post).contains("\"version\":2"))
    }

    @Test func closedCampOrReadOnlyRoleShowsNoActions() async throws {
        let host = host()
        stub(host) { _ in (200, "{}") }
        let closed = CampAttendanceModel(active: try campActive(.team, status: "abgeschlossen", host: host), personId: meUUID, ownLabel: "x")
        let readOnly = CampAttendanceModel(active: try campActive(.readOnly, host: host), personId: meUUID, ownLabel: "x")
        #expect(!closed.canSet && !readOnly.canSet)
        await closed.setWholeDay(.init(id: meUUID, label: "x", cells: []))
        #expect(StubProtocol.requests(host: host).isEmpty)
    }
}

@MainActor
struct CampDayPageModelTests {
    @Test func readsChiefBlocksAndWeather() async throws {
        let host = host()
        stub(host) { _ in
            (200, """
            {"lagertag":{"id":"\(uid(1))","datum":"2027-07-19","label":null},
             "seite":{"id":"\(uid(2))","version":1,"lagertagId":"\(uid(1))","tageschefPersonId":"\(uid(3))","notiz":" ","tageschef":{"id":"\(uid(3))","name":"Mara","ceviName":"Luchs"}},
             "bloecke":[{"id":"\(uid(4))","version":1,"seiteId":"\(uid(2))","art":"wichtig","text":"Zelte kontrollieren","dateiId":null,"reihenfolge":0,"datei":null}],
             "wetter":{"datum":"2027-07-19","code":1,"tmax":24.4,"tmin":12,"regen":0,"boeen":10,"zustand":"Sonnig","warnungen":["gewitter"]},"wetterStand":null,"aufgaben":[]}
            """)
        }
        let model = CampDayPageModel(active: try campActive(host: host), personId: meUUID, dayId: UUID(uuidString: uid(1))!, date: day3)
        await model.load()
        #expect(model.chiefName == "Mara (Luchs)" && model.important.count == 1 && model.weather == "Sonnig, 24 Grad" && model.weatherWarnings == ["Gewitter möglich"])
        #expect(model.note == nil && !model.isEmpty && model.headline.hasPrefix("Tag 3, "))
    }

    @Test func dayWithoutPageIsEmptyAndListsSortByDate() async throws {
        let host = host()
        stub(host) { request in
            path(request).hasSuffix("/tagesseiten")
                ? (200, #"{"tage":[{"lagertagId":"\#(uid(2))","datum":"2027-07-20","label":null,"seite":null},{"lagertagId":"\#(uid(1))","datum":"2027-07-19","label":null,"seite":null}]}"#)
                : (200, #"{"lagertag":{"id":"\#(uid(1))","datum":"2027-07-19","label":null},"seite":null,"bloecke":[],"wetter":null,"wetterStand":null,"aufgaben":[]}"#)
        }
        let model = CampDayPageModel(active: try campActive(host: host), personId: meUUID, dayId: UUID(uuidString: uid(1))!, date: day3)
        await model.load()
        #expect(model.isEmpty)
        let list = CampDayListModel(active: try campActive(host: host))
        await list.load()
        #expect(list.rows.map { $0.id.uuidString.lowercased() } == [uid(1), uid(2)] && list.rows.allSatisfy { !$0.hasPage })
    }
}

@MainActor
struct CampShoppingModelTests {
    private nonisolated static func item(_ n: Int, _ name: String, group: String, done: Bool = false) -> String {
        """
        {"id":"\(uid(20 + n))","version":1,"name":"\(name)","menge":6,"einheit":"kg","warengruppe":"\(group)","einkaeuferPersonId":null,
         "einkaeufer":{"id":"\(uid(50))","name":"Jonas","ceviName":null},"erledigt":\(done)}
        """
    }

    @Test func groupsByDepartmentAndNamesTheBuyers() async throws {
        let host = host()
        stub(host) { _ in (200, #"{"artikel":[\#(Self.item(1, "Reis", group: "vorrat")),\#(Self.item(2, "Äpfel", group: "obst_gemuese"))],"naechster":null}"#) }
        let model = CampShoppingModel(active: try campActive(.leader, host: host))
        await model.load()
        #expect(model.groups.map(\.group.title) == ["Früchte und Gemüse", "Trockenes"] && model.groups[0].rows[0].amount == "6 kg")
        #expect(model.groups[0].rows[0].buyer == "Jonas kauft" && model.buyersLine == "Wer kauft ein: Jonas")
    }

    @Test func onlyMineSendsTheFilterAndTickingCanBeUndone() async throws {
        let host = host()
        stub(host) { request in
            request.httpMethod == "PATCH" ? (200, Self.item(1, "Reis", group: "vorrat", done: body(request).contains("true")))
                : (200, #"{"artikel":[\#(Self.item(1, "Reis", group: "vorrat"))],"naechster":null}"#)
        }
        let model = CampShoppingModel(active: try campActive(.leader, host: host))
        await model.setOnlyMine(true)
        #expect(StubProtocol.requests(host: host).last?.url?.query?.contains("einkaeufer=ich") == true)
        await model.toggle(model.groups[0].rows[0])
        #expect(model.items[0].done && model.notice?.title == "Reis abgehakt.")
        await model.undo()
        #expect(!model.items[0].done && model.lastTicked == nil)
    }

    @Test func addValidatesAndTheTeamHasNoButtons() async throws {
        let host = host()
        stub(host) { _ in (200, Self.item(1, "Milch", group: "milch_kaese")) }
        let model = CampShoppingModel(active: try campActive(.leader, host: host))
        #expect(await model.add(name: " ", amount: "", unit: "") == false && model.error != nil)
        #expect(await model.add(name: "Milch", amount: "abc", unit: "") == false)
        #expect(await model.add(name: "Milch", amount: "24,5", unit: "L"))
        let post = try #require(StubProtocol.requests(host: host).first { $0.httpMethod == "POST" })
        #expect(body(post).contains("24.5") && body(post).contains("\"einheit\":\"l\""))
        let team = CampShoppingModel(active: try campActive(.team, host: host))
        #expect(!team.canEdit)
    }

    @Test func existingItemsAreNamedWhileTyping() async throws {
        let host = host()
        stub(host) { _ in (200, #"{"artikel":[\#(Self.item(1, "Reis", group: "vorrat"))],"naechster":null}"#) }
        let model = CampShoppingModel(active: try campActive(.leader, host: host))
        await model.load()
        #expect(model.existing(matching: "Rei") == ["Reis, 6 kg vorhanden"] && model.existing(matching: "x").isEmpty && model.existing(matching: " ").isEmpty)
    }
}

@MainActor
struct CampPackingModelTests {
    private nonisolated static let list = """
    {"punkte":[{"id":"\(uid(1))","version":1,"abschnitt":"Kleidung","text":"Regenjacke","nurLagerleitung":false,"reihenfolge":1,"zustand":"abgehakt"},
               {"id":"\(uid(2))","version":1,"abschnitt":"Kleidung","text":"Pullover","nurLagerleitung":false,"reihenfolge":2,"zustand":"offen"},
               {"id":"\(uid(3))","version":1,"abschnitt":"Kleidung","text":"Weg damit","nurLagerleitung":false,"reihenfolge":3,"zustand":"entfernt"},
               {"id":"\(uid(4))","version":1,"abschnitt":"Sonstiges","text":"Erste-Hilfe-Set","nurLagerleitung":true,"reihenfolge":4,"zustand":"offen"}],
     "eigene":[{"id":"\(uid(5))","text":"Taschenlampe","abschnitt":"Sonstiges","abgehakt":false,"reihenfolge":5}]}
    """

    @Test func countsPackedPointsAndHidesRemovedOnes() async throws {
        let host = host()
        stub(host) { _ in (200, Self.list) }
        let model = CampPackingModel(active: try campActive(host: host))
        await model.load()
        #expect(model.progress == "1 von 4 eingepackt" && model.sections.map(\.title) == ["Kleidung", "Sonstiges"])
        #expect(model.sections[1].rows.map(\.text) == ["Erste-Hilfe-Set", "Taschenlampe"] && model.sections[1].rows[0].leadershipOnly && model.sections[1].rows[1].isOwn)
    }

    @Test func tickingUsesTheOwnStateAndFailureRestoresIt() async throws {
        let host = host()
        stub(host) { request in
            switch request.httpMethod ?? "" {
            case "PUT": (200, #"{"id":"\#(uid(2))","zustand":"abgehakt"}"#)
            default: (200, Self.list)
            }
        }
        let model = CampPackingModel(active: try campActive(.team, host: host))
        await model.load()
        await model.toggle(model.sections[0].rows[1])
        let put = try #require(StubProtocol.requests(host: host).first { $0.httpMethod == "PUT" })
        #expect(path(put).hasSuffix("/zustand") && body(put).contains("abgehakt") && model.packed == 2)
        let failing = freshHost()
        stub(failing) { request in request.httpMethod == "PUT" ? (500, #"{"code":"X","message":"x"}"#) : (200, Self.list) }
        let broken = CampPackingModel(active: try campActive(.team, host: failing))
        await broken.load()
        await broken.toggle(broken.sections[0].rows[1])
        #expect(broken.packed == 1 && broken.error != nil)
    }

    @Test func leadershipWritesTheTemplateOthersAddOwnPoints() async throws {
        let host = host()
        stub(host) { request in request.httpMethod == "POST" ? (200, "{}") : (200, Self.list) }
        let lead = CampPackingModel(active: try campActive(host: host))
        #expect(await lead.add(section: "", text: "x", leadershipOnly: false) == false)
        #expect(lead.addsToTemplate)
        let team = CampPackingModel(active: try campActive(.team, host: host))
        let viewer = CampPackingModel(active: try campActive(.readOnly, host: host))
        #expect(!team.addsToTemplate && team.canAdd && !viewer.canAdd)
    }
}

@MainActor
struct CampEmergencyModelTests {
    private nonisolated static let emergency = """
    {"adresse":{"ort":"Lagerhaus","adresse":"Waldweg 1","kartenLink":null},
     "kontakte":[{"quelle":"eintrag","id":"\(uid(1))","version":1,"funktion":"Sicherheit","personId":null,"name":"Tim","ceviName":"Spatz","telefon":"+41 00 000 00 00","reihenfolge":1},
                 {"quelle":"eintrag","id":"\(uid(2))","version":1,"funktion":"Ohne Nummer","personId":null,"name":"Lea","ceviName":null,"telefon":null,"reihenfolge":2}],"infos":[]}
    """

    @Test func keepsTheLastAnswerWithoutNetwork() async throws {
        let host = host()
        stub(host) { _ in (200, Self.emergency) }
        let active = try campActive(.team, host: host)
        let first = CampEmergencyModel(active: active)
        first.now = { day3 }
        await first.load()
        #expect(first.contacts.count == 2 && first.contacts[0].phoneURL?.absoluteString == "tel:+41000000000" && first.contacts[1].phoneURL == nil)
        #expect(active.emergencySnapshot?.loadedAt == day3)
        let offline = try campActive(.team, host: freshHost())
        offline.emergencySnapshot = active.emergencySnapshot
        let again = CampEmergencyModel(active: offline)
        #expect(again.phase == .loaded && again.contacts.count == 2)
        await again.load()
        #expect(again.phase == .loaded && again.staleSince != nil && again.staleTitle?.hasPrefix("Ohne Netz. Stand") == true)
        offline.leave()
        #expect(offline.emergencySnapshot == nil)
    }

    @Test func withoutSnapshotTheFailureIsShown() async throws {
        let model = CampEmergencyModel(active: try campActive(.team, host: host()))
        await model.load()
        if case .failed(let state, _) = model.phase { #expect(state == .offline) } else { Issue.record("expected a failure") }
    }

    @Test func routeComesFromTheAddress() async throws {
        let host = host()
        stub(host) { _ in (200, Self.emergency) }
        let model = CampEmergencyModel(active: try campActive(.team, host: host))
        await model.load()
        #expect(model.address?.routeURL?.host == "maps.apple.com")
    }
}

@MainActor
struct CampInfosModelTests {
    private nonisolated static let page = """
    {"abschnitte":[{"id":"\(uid(1))","version":1,"titel":"Lagerhaus","text":"a","links":[],"nurLagerleitung":false,"notfall":false,"reihenfolge":1,"dateien":[]},
                   {"id":"\(uid(2))","version":3,"titel":"Regeln","text":"b","links":[],"nurLagerleitung":false,"notfall":false,"reihenfolge":2,"dateien":[]}],"naechster":null}
    """

    @Test func leadershipMovesASectionWithTheArrowsAndTheOthersCannot() async throws {
        let host = host()
        stub(host) { _ in (200, Self.page) }
        let model = CampInfosModel(active: try campActive(host: host))
        await model.load()
        #expect(model.infos.map(\.title) == ["Lagerhaus", "Regeln"] && !model.canMove(model.infos[0], by: -1) && model.canMove(model.infos[0], by: 1))
        await model.move(model.infos[1], by: -1)
        let put = try #require(StubProtocol.requests(host: host).first { $0.httpMethod == "PUT" })
        #expect(path(put).hasSuffix("/infos/reihenfolge") && body(put).lowercased().range(of: uid(2)).map { body(put).lowercased().range(of: uid(1))!.lowerBound > $0.lowerBound } == true)
        let team = CampInfosModel(active: try campActive(.team, host: host))
        await team.load()
        #expect(!team.canReorder && team.showsRestrictedHint && !model.showsRestrictedHint)
    }
}

@MainActor
struct CampOnSiteNavigationTests {
    @Test func aPushForAttendanceOpensTheAttendance() async throws {
        let host = host()
        let campId = campUUID.uuidString.lowercased()
        stub(host) { request in
            if path(request).contains("/aufloesen/") { return (200, #"{"lagerId":"\#(campId)","objektTyp":"anwesenheit","objektId":"\#(uid(1))"}"#) }
            if path(request).hasSuffix("/lager") { return (200, #"{"lager":[{"id":"\#(campId)","titel":"Sommerlager","von":"2027-07-17","bis":"2027-07-24","vorbereitungAb":null,"ort":null,"adresse":null,"status":"aktiv","farbe":null,"logoMediumId":null,"wetterOrt":{"status":"kein_ort","name":null},"rolle":"team"}]}"#) }
            return (200, "{}")
        }
        let client = APIClient(baseURL: URL(string: "https://\(host)")!, appVersion: "1.0.0", cookieStore: InMemoryCookieStore(["s": "1"]),
                               session: APIClient.makeSession(protocolClasses: [StubProtocol.self]))
        let active = ActiveCamp()
        let state = await CampRouter.open(type: .attendance, objectId: UUID(), client: client, list: CampListModel(), active: active)
        #expect(state == nil && active.destination == .attendance)
    }
}
