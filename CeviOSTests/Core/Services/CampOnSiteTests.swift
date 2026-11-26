import Foundation
import Testing
@testable import CeviOS

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder.api.decode(T.self, from: Data(json.utf8))
}

private let uuid1 = "0190a000-0000-7000-8000-000000000001"
private let uuid2 = "0190a000-0000-7000-8000-000000000002"
private let uuid3 = "0190a000-0000-7000-8000-000000000003"

private let personJSON = #"{"id":"\#(uuid2)","name":"Pat Muster","ceviName":"Pinguin"}"#
private let fileJSON = """
{"id":"\(uuid3)","version":1,"anzeigename":"Plan.pdf","link":"https://example.org/f","typ":null,"groesse":null,"hinzugefuegtVon":null,"hinzugefuegtAm":"2027-07-10T08:00:00Z"}
"""
private let taskJSON = """
{"id":"\(uuid1)","version":1,"titel":"Zelte prüfen","ressortId":"\(uuid2)","teil":null,"verantwortlichPersonId":null,"status":"offen","notiz":null,"frist":"2027-07-12",
 "fristMeilensteinId":null,"fristVersatzTage":null,"stern":false,"laufend":false,"spaeterAb":null,"wiederholung":null,"reihenfolge":0,"quelle":null,"erledigtAm":null,
 "verantwortlich":{"id":"\(uuid2)","name":"Pat Muster","ceviName":null,"automatisch":true},"ressort":{"id":"\(uuid2)","kuerzel":"si","name":"Sicherheit"},"unterstuetzung":[\(personJSON)]}
"""
private let pageJSON = #"{"id":"\#(uuid1)","version":2,"lagertagId":"\#(uuid2)","tageschefPersonId":"\#(uuid2)","notiz":"Ausflug","tageschef":\#(personJSON)}"#
private let blockJSON = #"{"id":"\#(uuid1)","version":1,"seiteId":"\#(uuid2)","art":"programmbild","text":"Plan","dateiId":"\#(uuid3)","reihenfolge":0,"datei":\#(fileJSON)}"#
private let weatherDayJSON = #"{"datum":"2027-07-12","code":61,"tmax":24.5,"tmin":11,"regen":3.2,"boeen":38,"zustand":"Regen","warnungen":["regen","sturm"]}"#
private let meetingTeamJSON = #"{"id":"\#(uuid1)","version":1,"datum":"2027-07-12","zeit":"19:30","titel":"Höck","ort":null}"#
private let shiftJSON = """
{"id":"\(uuid1)","version":1,"dienstId":"\(uuid2)","lagertagId":"\(uuid3)","datum":"2027-07-12","tagesabschnittId":"\(uuid3)","personId":"\(uuid2)","teilnehmerId":null,"name":"Pat Muster","ceviName":null,"stufe":null}
"""
private let itemJSON = """
{"id":"\(uuid1)","version":3,"name":"Reis","menge":2.5,"einheit":"kg","warengruppe":"vorrat","einkaeuferPersonId":"\(uuid2)","einkaeufer":\(personJSON),"erledigt":false}
"""
private let packingPointJSON = #"{"id":"\#(uuid1)","version":1,"abschnitt":"Kleider","text":"Regenjacke","nurLagerleitung":false,"reihenfolge":0,"zustand":"abgehakt"}"#
private let ownPointJSON = #"{"id":"\#(uuid2)","abschnitt":"Kleider","text":"Mütze","abgehakt":true,"reihenfolge":1}"#
private let contactJSON = #"{"quelle":"eintrag","id":"\#(uuid1)","version":2,"funktion":"Lagerarzt","personId":null,"name":"Dr. Muster","ceviName":null,"telefon":"000 000 00 00","reihenfolge":0}"#
private let infoJSON = """
{"id":"\(uuid1)","version":1,"titel":"Anreise","text":"Treffpunkt Bahnhof","links":[{"titel":"Plan","url":"https://example.org/plan"}],"nurLagerleitung":false,"notfall":true,"reihenfolge":0,"dateien":[\(fileJSON)]}
"""
private let emergencyJSON = """
{"adresse":{"ort":"Testdorf","adresse":"Teststrasse 1","kartenLink":"https://maps.example.org/x"},"kontakte":[\(contactJSON),
 {"quelle":"ressort","id":null,"version":null,"funktion":"Leitung Sicherheit","personId":"\(uuid2)","name":"Pat Muster","ceviName":"Pinguin","telefon":null,"reihenfolge":null}],"infos":[\(infoJSON)]}
"""

private func encoded<T: Encodable>(_ value: T) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: JSONEncoder.api.encode(value)) as? [String: Any])
}

struct CampOnSiteModelTests {
    @Test func dayPageDetailDecodesEverySource() throws {
        let detail = try decode(CampDayPageDetail.self, """
        {"lagertag":{"id":"\(uuid2)","datum":"2027-07-12","label":"Tag 3"},"seite":\(pageJSON),"bloecke":[\(blockJSON),
         {"id":"\(uuid2)","version":1,"seiteId":"\(uuid2)","art":"hinweis","text":"x","dateiId":null,"reihenfolge":1}],
         "wetter":\(weatherDayJSON),"wetterStand":"2027-07-12T06:00:00Z","aufgaben":[\(taskJSON)]}
        """)
        #expect(detail.day.label == "Tag 3" && detail.page?.chief?.name == "Pat Muster" && detail.page?.note == "Ausflug")
        #expect(detail.blocks[0].kind == .programPicture && detail.blocks[0].file?.displayName == "Plan.pdf" && detail.blocks[1].kind == .unknown && detail.blocks[1].file == nil)
        #expect(detail.weather?.warnings == [.rain, .unknown] && detail.weatherAsOf != nil && detail.tasks.first?.title == "Zelte prüfen")
        let bare = try decode(CampDayPageDetail.self, #"{"lagertag":{"id":"\#(uuid2)","datum":"2027-07-12","label":null},"seite":null,"bloecke":[],"wetter":null,"wetterStand":null,"aufgaben":[]}"#)
        #expect(bare.page == nil && bare.weather == nil && bare.tasks.isEmpty)
    }

    @Test func dayPageListAndWriteAnswer() throws {
        let list = try decode(CampDayPageList.self, #"{"tage":[{"lagertagId":"\#(uuid1)","datum":"2027-07-11","label":null,"seite":null},{"lagertagId":"\#(uuid2)","datum":"2027-07-12","label":"Ausflug","seite":\#(pageJSON)}]}"#)
        #expect(list.days[0].page == nil && list.days[1].page?.chiefPersonId != nil && list.days[1].id.uuidString.lowercased() == uuid2)
        let written = try decode(CampDayPage.self, #"{"id":"\#(uuid1)","version":1,"lagertagId":"\#(uuid2)","tageschefPersonId":null,"notiz":null}"#)
        #expect(written.chief == nil)
    }

    @Test func weatherDecodesPlaceOnly() throws {
        let weather = try decode(CampWeather.self, #"{"ort":{"status":"gefunden","name":"Beispielort BE"},"stand":"2027-07-12T06:00:00Z","tage":[\#(weatherDayJSON)]}"#)
        #expect(weather.place.status == .found && weather.place.name == "Beispielort BE" && weather.days.first?.maxTemperature == 24.5 && weather.days.first?.gusts == 38)
        let off = try decode(CampWeather.self, #"{"ort":{"status":"kein_ort","name":null},"stand":null,"tage":[]}"#)
        #expect(off.place.status == .noPlace && off.place.name == nil && off.asOf == nil && off.days.isEmpty)
    }

    @Test func unknownPlaceStatusDecodesTolerantly() throws {
        let place = try decode(CampWeatherPlace.self, #"{"status":"neu","name":null}"#)
        #expect(place.status == .unknown)
    }

    @Test func todayHoldsOnlyWhatTheRoleMayRead() throws {
        let today = try decode(CampToday.self, """
        {"datum":"2027-07-12","lagertag":{"id":"\(uuid2)","datum":"2027-07-12","label":null},
         "tagesseite":{"seite":\(pageJSON),"bloecke":[\(blockJSON)],"aufgaben":[\(taskJSON)]},
         "wetter":{"tag":\(weatherDayJSON),"stand":null},
         "anwesenheit":{"zeilen":[{"lagertagId":"\(uuid2)","tagesabschnittId":"\(uuid3)","wert":"A","leitende":2,"teilnehmende":10}]},
         "schichten":{"dienste":[{"id":"\(uuid2)","version":1,"name":"Küche","beschreibung":null,"mindestbesetzung":2,"nacht":false,"tagesabschnittId":"\(uuid3)","reihenfolge":0}],"schichten":[\(shiftJSON)]},
         "hoecks":[\(meetingTeamJSON)]}
        """)
        #expect(today.page?.blocks.count == 1 && today.weather?.day?.condition == "Regen" && today.attendance?.rows.first?.participants == 10)
        #expect(today.shifts?.duties.first?.name == "Küche" && today.shifts?.shifts.first?.name == "Pat Muster")
        guard case .team(let meeting)? = today.meetings?.first else { Issue.record("team shape"); return }
        #expect(meeting.title == "Höck")
        let team = try decode(CampToday.self, #"{"datum":"2027-07-12","lagertag":null,"tagesseite":null,"wetter":null,"anwesenheit":null,"schichten":null,"hoecks":[]}"#)
        #expect(team.day == nil && team.page == nil && team.attendance == nil && team.shifts == nil && team.meetings?.isEmpty == true)
    }

    @Test func myWeekDecodesShiftsWithDuty() throws {
        let week = try decode(CampMyWeek.self, """
        {"von":"2027-07-12","bis":"2027-07-18","aufgaben":[\(taskJSON)],
         "schichten":[{"id":"\(uuid1)","version":1,"dienstId":"\(uuid2)","lagertagId":"\(uuid3)","datum":"2027-07-12","tagesabschnittId":"\(uuid3)","personId":"\(uuid2)",
                       "teilnehmerId":null,"name":"Pat Muster","ceviName":null,"stufe":null,"dienst":{"id":"\(uuid2)","name":"Nachtwache","nacht":true}}],
         "hoecks":null}
        """)
        #expect(week.tasks?.count == 1 && week.shifts?.first?.duty?.night == true && week.shifts?.first?.shift.name == "Pat Muster" && week.meetings == nil)
    }

    @Test func dataSurvivesStoringAndLoadingAgain() throws {
        // A later cache stores the models as they are: encode with the API encoder, decode with the API decoder.
        let emergency = try decode(CampEmergency.self, emergencyJSON)
        #expect(try decode(CampEmergency.self, String(decoding: JSONEncoder.api.encode(emergency), as: UTF8.self)) == emergency)
        let today = try decode(CampToday.self, """
        {"datum":"2027-07-12","lagertag":null,"tagesseite":{"seite":\(pageJSON),"bloecke":[\(blockJSON)],"aufgaben":[\(taskJSON)]},"wetter":{"tag":\(weatherDayJSON),"stand":"2027-07-12T06:00:00Z"},
         "anwesenheit":null,"schichten":{"dienste":[],"schichten":[\(shiftJSON)]},"hoecks":[\(meetingTeamJSON)]}
        """)
        #expect(try decode(CampToday.self, String(decoding: JSONEncoder.api.encode(today), as: UTF8.self)) == today)
        let week = try decode(CampMyWeek.self, #"{"von":"2027-07-12","bis":"2027-07-18","aufgaben":null,"schichten":[{"id":"\#(uuid1)","version":1,"dienstId":"\#(uuid2)","lagertagId":"\#(uuid3)","datum":"2027-07-12","tagesabschnittId":"\#(uuid3)","personId":null,"teilnehmerId":"\#(uuid2)","name":"Mia Muster","ceviName":null,"stufe":"Wölfe","dienst":null}],"hoecks":null}"#)
        #expect(try decode(CampMyWeek.self, String(decoding: JSONEncoder.api.encode(week), as: UTF8.self)) == week)
    }

    @Test func shoppingDecodesAndGroups() throws {
        let page = try decode(CampShoppingPage.self, """
        {"artikel":[\(itemJSON),{"id":"\(uuid2)","version":1,"name":"Brot","menge":null,"einheit":null,"warengruppe":"brot","einkaeuferPersonId":null,"einkaeufer":null,"erledigt":true},
                    {"id":"\(uuid3)","version":1,"name":"Salz","menge":1,"einheit":null,"warengruppe":"neu","einkaeuferPersonId":null,"einkaeufer":null,"erledigt":false}],"naechster":null}
        """)
        #expect(page.items[0].amount == 2.5 && page.items[0].buyer?.name == "Pat Muster" && page.items[1].amount == nil && page.items[1].done && page.items[2].group == .unknown)
        #expect(page.byGroup.map(\.group) == [.bread, .pantry] || page.byGroup.map(\.group) == [.bread, .pantry, .unknown])
        #expect(page.byGroup.first?.items.first?.name == "Brot")
    }

    @Test func shoppingTotalsDecode() throws {
        let page = try decode(CampShoppingTotalPage.self, #"{"artikel":[{"name":"Reis","menge":3,"einheit":"kg","warengruppe":"vorrat","einkaeuferPersonId":null,"einkaeufer":null,"erledigt":false,"anzahl":2,"eintraege":[{"id":"\#(uuid1)","version":1},{"id":"\#(uuid2)","version":4}]}],"naechster":"\#(uuid3)"}"#)
        #expect(page.items.first?.count == 2 && page.items.first?.entries.last?.version == 4 && page.next != nil)
        let suggestions = try decode(CampShoppingSuggestionList.self, #"{"vorschlaege":[{"name":"Reis","haeufigkeit":4}]}"#)
        #expect(suggestions.suggestions.first?.frequency == 4)
    }

    @Test func shoppingPatchSendsOnlyWhatChanged() throws {
        let tick = try encoded(CampShoppingPatch(version: 3, done: true))
        #expect(Set(tick.keys) == ["version", "erledigt"] && tick["erledigt"] as? Bool == true)
        let clear = try encoded(CampShoppingPatch(version: 3, amount: .clear, buyerPersonId: .clear))
        #expect(clear["menge"] is NSNull && clear["einkaeuferPersonId"] is NSNull && clear["einheit"] == nil)
        #expect(CampShoppingBuyerFilter.me.queryValue == "ich" && CampShoppingBuyerFilter.person(UUID(uuidString: uuid1)!).queryValue == uuid1)
    }

    @Test func packingListDecodesTemplateAndOwnPoints() throws {
        let list = try decode(CampPackingList.self, #"{"punkte":[\#(packingPointJSON),{"id":"\#(uuid2)","version":1,"abschnitt":"Kleider","text":"Mütze","nurLagerleitung":true,"reihenfolge":1}],"eigene":[\#(ownPointJSON)]}"#)
        #expect(list.points[0].state == .checked && list.points[1].state == nil && list.points[1].leadershipOnly && list.own.first?.checked == true)
        #expect(throws: DecodingError.self) { try decode(CampPackingStateResult.self, #"{"id":"\#(uuid1)","zustand":"weg"}"#) }
    }

    @Test func emergencyDecodesAddressContactsAndInfos() throws {
        let emergency = try decode(CampEmergency.self, emergencyJSON)
        #expect(emergency.address.place == "Testdorf" && emergency.contacts.count == 2 && emergency.infos.first?.isEmergency == true)
        #expect(emergency.contacts[0].source == .entry && emergency.contacts[0].version == 2 && emergency.contacts[1].source == .portfolio && emergency.contacts[1].phone == nil)
        #expect(emergency.infos.first?.links.first?.url == "https://example.org/plan" && emergency.infos.first?.files.count == 1)
        let other = try decode(CampEmergencyContact.self, contactJSON.replacingOccurrences(of: #""eintrag""#, with: #""neu""#))
        #expect(other.source == .unknown)
    }

    @Test func routeUsesTheMapLinkThenTheAddress() throws {
        let linked = CampEmergencyAddress(place: "Testdorf", address: "Teststrasse 1", mapLink: URL(string: "https://maps.example.org/x"))
        #expect(linked.routeURL?.absoluteString == "https://maps.example.org/x")
        let unsafe = CampEmergencyAddress(place: "Testdorf", address: "Teststrasse 1", mapLink: URL(string: "http://maps.example.org/x"))
        let route = try #require(unsafe.routeURL)
        #expect(route.host == "maps.apple.com" && URLComponents(url: route, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "daddr" }?.value == "Teststrasse 1, Testdorf")
        #expect(CampEmergencyAddress(place: nil, address: " ", mapLink: nil).routeURL == nil)
    }

    @Test func phoneURLKeepsDigitsOnly() throws {
        func contact(_ phone: String?) throws -> CampEmergencyContact {
            try decode(CampEmergencyContact.self, #"{"quelle":"eintrag","id":null,"version":null,"funktion":"x","personId":null,"name":"x","ceviName":null,"telefon":\#(phone.map { "\"\($0)\"" } ?? "null"),"reihenfolge":null}"#)
        }
        #expect(try contact("+41 (0)00 000 00 00").phoneURL?.absoluteString == "tel:+410000000000")
        #expect(try contact("abc").phoneURL == nil && contact(nil).phoneURL == nil)
    }

    @Test func mapLinkBodySendsNullToRemove() throws {
        #expect(try encoded(CampMapLinkBody(mapLink: nil))["kartenLink"] is NSNull)
        #expect(try encoded(CampMapLinkBody(mapLink: URL(string: "https://maps.example.org/x")))["kartenLink"] as? String == "https://maps.example.org/x")
    }
}

struct CampOnSiteServiceTests {
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

    @Test func dayPageRoutes() async throws {
        var r = try await sent(#"{"tage":[]}"#) { _ = try await $0.campDayPages(campId: camp) }
        #expect(r.method == "GET" && r.path == campPath + "/tagesseiten")
        r = try await sent(#"{"lagertag":{"id":"\#(uuid2)","datum":"2027-07-12","label":null},"seite":null,"bloecke":[],"wetter":null,"wetterStand":null,"aufgaben":[]}"#) { _ = try await $0.campDayPage(campId: camp, dayId: id) }
        #expect(r.path == campPath + "/tagesseiten/" + idText)
        r = try await sent(status: 201, pageJSON) { _ = try await $0.createCampDayPage(campId: camp, dayId: id, CampDayPageCreate(chiefPersonId: other, note: "A")) }
        #expect(r.method == "POST" && r.body?["tageschefPersonId"] as? String == otherText.uppercased() || r.body?["tageschefPersonId"] as? String == otherText)
        r = try await sent(pageJSON) { _ = try await $0.updateCampDayPage(campId: camp, dayId: id, CampDayPagePatch(version: 2, chiefPersonId: .clear)) }
        #expect(r.method == "PATCH" && r.body?["version"] as? Int == 2 && r.body?["tageschefPersonId"] is NSNull && r.body?["notiz"] == nil)
        r = try await sent(status: 201, blockJSON) { _ = try await $0.createCampDayBlock(campId: camp, dayId: id, CampDayBlockCreate(kind: .programPicture, text: "Plan", fileId: other)) }
        #expect(r.method == "POST" && r.path == campPath + "/tagesseiten/" + idText + "/bloecke" && r.body?["art"] as? String == "programmbild" && r.body?["dateiId"] != nil)
        r = try await sent(blockJSON) { _ = try await $0.updateCampDayBlock(campId: camp, dayId: id, blockId: other, CampDayBlockPatch(version: 1, text: "B")) }
        #expect(r.method == "PATCH" && r.path == campPath + "/tagesseiten/" + idText + "/bloecke/" + otherText)
        r = try await sent(status: 204, "") { try await $0.deleteCampDayBlock(campId: camp, dayId: id, blockId: other, version: 1) }
        #expect(r.method == "DELETE" && r.query["version"] == "1")
    }

    @Test func weatherRoutes() async throws {
        var r = try await sent(#"{"ort":{"status":"offen","name":null},"stand":null,"tage":[]}"#) { _ = try await $0.campWeather(campId: camp) }
        #expect(r.method == "GET" && r.path == campPath + "/wetter")
    }

    @Test func aggregateRoutes() async throws {
        var r = try await sent(#"{"datum":"2027-07-12","lagertag":null,"tagesseite":null,"wetter":null,"anwesenheit":null,"schichten":null,"hoecks":null}"#) { _ = try await $0.campToday(campId: camp) }
        #expect(r.method == "GET" && r.path == campPath + "/heute")
        r = try await sent(#"{"von":"2027-07-12","bis":"2027-07-18","aufgaben":null,"schichten":null,"hoecks":null}"#) { _ = try await $0.campMyWeek(campId: camp) }
        #expect(r.method == "GET" && r.path == campPath + "/meine-woche")
    }

    @Test func aggregateWithoutReadablePartIsForbidden() async throws {
        let host = "a\(UUID().uuidString.prefix(8).lowercased()).test.example.org"
        StubProtocol.register(host: host) { _ in (403, [:], Data(#"{"code":"KEIN_RECHT","message":"x"}"#.utf8)) }
        let client = APIClient(baseURL: URL(string: "https://\(host)")!, appVersion: "1.0.0", cookieStore: InMemoryCookieStore(["s": "1"]), session: APIClient.makeSession(protocolClasses: [StubProtocol.self]))
        do { _ = try await client.campToday(campId: camp); Issue.record("expected 403") } catch let error as APIError { #expect(error.kind == .forbidden) }
    }

    @Test func shoppingRoutes() async throws {
        var r = try await sent(#"{"artikel":[],"naechster":null}"#) { _ = try await $0.campShopping(campId: camp, buyer: .me, done: false, after: other, limit: 20) }
        #expect(r.method == "GET" && r.path == campPath + "/einkauf" && r.query["einkaeufer"] == "ich" && r.query["erledigt"] == "false" && r.query["limit"] == "20" && r.query["nach"] == otherText)
        r = try await sent(#"{"artikel":[],"naechster":null}"#) { _ = try await $0.campShoppingTotals(campId: camp, buyer: .person(other), done: true) }
        #expect(r.path == campPath + "/einkauf/zusammen" && r.query["einkaeufer"] == otherText && r.query["erledigt"] == "true")
        var names: [CampShoppingSuggestion] = []
        r = try await sent(#"{"vorschlaege":[{"name":"Reis","haeufigkeit":2}]}"#) { names = try await $0.campShoppingSuggestions(campId: camp, prefix: "Re", limit: 5) }
        #expect(r.path == campPath + "/einkauf/vorschlaege" && r.query["q"] == "Re" && r.query["limit"] == "5" && names.count == 1)
        r = try await sent(#"{"vorschlaege":[]}"#) { _ = try await $0.campShoppingSuggestions(campId: camp, prefix: "") }
        #expect(r.query["q"] == nil && r.query["limit"] == "10")
        r = try await sent(itemJSON) { _ = try await $0.campShoppingItem(campId: camp, itemId: id) }
        #expect(r.path == campPath + "/einkauf/" + idText)
        r = try await sent(status: 201, itemJSON) { _ = try await $0.createCampShoppingItem(campId: camp, CampShoppingCreate(name: "Reis", amount: 2.5, unit: "kg", group: .pantry)) }
        #expect(r.method == "POST" && r.body?["menge"] as? Double == 2.5 && r.body?["warengruppe"] as? String == "vorrat" && r.body?["einkaeuferPersonId"] == nil)
        r = try await sent(itemJSON) { _ = try await $0.updateCampShoppingItem(campId: camp, itemId: id, CampShoppingPatch(version: 3, done: true)) }
        #expect(r.method == "PATCH" && r.body?["erledigt"] as? Bool == true && r.body?["version"] as? Int == 3)
        r = try await sent(status: 204, "") { try await $0.deleteCampShoppingItem(campId: camp, itemId: id, version: 3) }
        #expect(r.method == "DELETE" && r.query["version"] == "3")
    }

    @Test func packingRoutes() async throws {
        var r = try await sent(#"{"punkte":[],"eigene":[]}"#) { _ = try await $0.campPackingList(campId: camp) }
        #expect(r.method == "GET" && r.path == campPath + "/packliste")
        r = try await sent(status: 201, packingPointJSON) { _ = try await $0.createCampPackingPoint(campId: camp, CampPackingPointCreate(section: "Kleider", text: "Regenjacke", leadershipOnly: true)) }
        #expect(r.method == "POST" && r.path == campPath + "/packliste/punkte" && r.body?["nurLagerleitung"] as? Bool == true)
        r = try await sent(packingPointJSON) { _ = try await $0.updateCampPackingPoint(campId: camp, pointId: id, CampPackingPointPatch(version: 1, text: "Jacke")) }
        #expect(r.method == "PATCH" && r.path == campPath + "/packliste/punkte/" + idText)
        r = try await sent(status: 204, "") { try await $0.deleteCampPackingPoint(campId: camp, pointId: id, version: 1) }
        #expect(r.method == "DELETE" && r.query["version"] == "1")
        var state: CampPackingState?
        r = try await sent(#"{"id":"\#(uuid1)","zustand":"abgehakt"}"#) { state = try await $0.setCampPackingState(campId: camp, pointId: id, .checked) }
        #expect(r.method == "PUT" && r.path == campPath + "/packliste/punkte/" + idText + "/zustand" && r.body?["zustand"] as? String == "abgehakt" && state == .checked)
        r = try await sent(status: 201, ownPointJSON) { _ = try await $0.createOwnCampPackingPoint(campId: camp, CampOwnPackingPointCreate(section: "Kleider", text: "Mütze")) }
        #expect(r.method == "POST" && r.path == campPath + "/packliste/eigene" && r.body?["version"] == nil)
        r = try await sent(ownPointJSON) { _ = try await $0.updateOwnCampPackingPoint(campId: camp, pointId: id, CampOwnPackingPointPatch(checked: true)) }
        #expect(r.method == "PATCH" && r.path == campPath + "/packliste/eigene/" + idText && r.body?["abgehakt"] as? Bool == true)
        r = try await sent(status: 204, "") { try await $0.deleteOwnCampPackingPoint(campId: camp, pointId: id) }
        #expect(r.method == "DELETE" && r.path == campPath + "/packliste/eigene/" + idText && r.query.isEmpty)
    }

    @Test func emergencyRoutes() async throws {
        var emergency: CampEmergency?
        var r = try await sent(emergencyJSON) { emergency = try await $0.campEmergency(campId: camp) }
        #expect(r.method == "GET" && r.path == campPath + "/notfall" && emergency?.contacts.count == 2)
        var link: URL?
        r = try await sent(#"{"kartenLink":"https://maps.example.org/x"}"#) { link = try await $0.setCampMapLink(campId: camp, URL(string: "https://maps.example.org/x")) }
        #expect(r.method == "PUT" && r.path == campPath + "/notfall/karte" && link?.host == "maps.example.org")
        r = try await sent(status: 201, contactJSON) { _ = try await $0.createCampEmergencyContact(campId: camp, CampEmergencyContactCreate(function: "Lagerarzt", name: "Dr. Muster", phone: "000 000 00 00")) }
        #expect(r.method == "POST" && r.path == campPath + "/notfall/kontakte" && r.body?["funktion"] as? String == "Lagerarzt" && r.body?["telefon"] != nil)
        r = try await sent(contactJSON) { _ = try await $0.updateCampEmergencyContact(campId: camp, contactId: id, CampEmergencyContactPatch(version: 2, phone: .clear)) }
        #expect(r.method == "PATCH" && r.path == campPath + "/notfall/kontakte/" + idText && r.body?["telefon"] is NSNull)
        r = try await sent(status: 204, "") { try await $0.deleteCampEmergencyContact(campId: camp, contactId: id, version: 2) }
        #expect(r.method == "DELETE" && r.query["version"] == "2")
    }

    @Test func infoRoutes() async throws {
        var r = try await sent(#"{"abschnitte":[\#(infoJSON)],"naechster":null}"#) { _ = try await $0.campInfos(campId: camp, after: other, limit: 10) }
        #expect(r.method == "GET" && r.path == campPath + "/infos" && r.query["limit"] == "10" && r.query["nach"] == otherText)
        r = try await sent(infoJSON) { _ = try await $0.campInfo(campId: camp, infoId: id) }
        #expect(r.path == campPath + "/infos/" + idText)
        r = try await sent(status: 201, infoJSON) { _ = try await $0.createCampInfo(campId: camp, CampInfoCreate(title: "Anreise", links: [CampInfoLink(title: "Plan", url: "https://example.org/plan")], isEmergency: true)) }
        let link = try #require((r.body?["links"] as? [[String: Any]])?.first)
        #expect(r.method == "POST" && r.path == campPath + "/infos" && r.body?["titel"] as? String == "Anreise" && r.body?["notfall"] as? Bool == true && link["titel"] as? String == "Plan")
        r = try await sent(infoJSON) { _ = try await $0.updateCampInfo(campId: camp, infoId: id, CampInfoPatch(version: 1, text: .clear)) }
        #expect(r.method == "PATCH" && r.body?["text"] is NSNull && r.body?["titel"] == nil)
        r = try await sent(status: 204, "") { try await $0.deleteCampInfo(campId: camp, infoId: id, version: 1) }
        #expect(r.method == "DELETE" && r.query["version"] == "1")
        r = try await sent(status: 204, "") { try await $0.reorderCampInfos(campId: camp, [CampVersionRef(id: id, version: 1), CampVersionRef(id: other, version: 2)]) }
        #expect(r.method == "PUT" && r.path == campPath + "/infos/reihenfolge" && (r.body?["eintraege"] as? [Any])?.count == 2)
    }
}
