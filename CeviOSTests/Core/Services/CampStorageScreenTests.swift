import Foundation
import Testing
@testable import CeviOS

private nonisolated let campUUID = UUID(uuidString: "0190a000-0000-7000-8000-000000000001")!
private nonisolated func uid(_ n: Int) -> String { "0190a000-0000-7000-8000-0000000099\(String(format: "%02d", n))" }

@MainActor
private func campActive(_ role: CampRole = .campLeader, status: String = "aktiv", host: String) throws -> ActiveCamp {
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

private func host() -> String { "s\(UUID().uuidString.prefix(8).lowercased()).test.example.org" }

private func stub(_ host: String, _ handler: @escaping @Sendable (URLRequest) -> (Int, String)) {
    StubProtocol.register(host: host) { request in
        let (status, body) = handler(request)
        return (status, [:], Data(body.utf8))
    }
}

private nonisolated func path(_ request: URLRequest) -> String { request.url?.path ?? "" }
private nonisolated func body(_ request: URLRequest) -> String { StubProtocol.body(of: request).map { String(decoding: $0, as: UTF8.self) } ?? "" }

private nonisolated func documentJSON(_ n: Int, link: String = "https://example.org/a", kind: String = "pdf", size: Int? = 240_000, created: String = "2027-07-17T08:00:00Z") -> String {
    """
    {"quelle":"dokument","id":"\(uid(n))","version":1,"titel":"Plan \(n)","stichworte":["Fahrt"],"teamSichtbar":true,
     "datei":{"id":"\(uid(n + 50))","version":1,"anzeigename":"Plan","link":"\(link)","typ":null,"groesse":\(size.map(String.init) ?? "null"),"hinzugefuegtVon":null,"hinzugefuegtAm":"2027-07-01T08:00:00Z"},
     "art":"\(kind)","sharepoint":false,"erstelltAm":"\(created)"}
    """
}

private nonisolated func contactJSON(_ n: Int, keep: Bool = false) -> String {
    """
    {"id":"\(uid(n))","version":2,"name":"Kontakt \(n)","funktion":null,"gruppe":"Küche","telefon":"+41 00 000 00 00","email":"a@example.org","notiz":null,
     "behalten":\(keep),"aufraeumenAb":\(keep ? "null" : "\"2028-01-12\""),"erstelltAm":"2027-06-01T08:00:00Z"}
    """
}

struct CampStorageRightsTests {
    @Test func onlyTheCampLeadershipReadsTheAddressBook() {
        func rights(_ role: CampRole, readOnly: Bool = false) -> CampStorageRights { CampStorageRights(role: role, readOnly: readOnly) }
        #expect(rights(.campLeader).seesAddressBook && rights(.campLeader).editsAddressBook)
        #expect(!rights(.leader).seesAddressBook && !rights(.team).seesAddressBook && !rights(.readOnly).seesAddressBook)
        #expect(rights(.campLeader, readOnly: true).seesAddressBook && !rights(.campLeader, readOnly: true).editsAddressBook)
        #expect(rights(.campLeader).searchTypes.contains(.addressBook) && !rights(.leader).searchTypes.contains(.addressBook))
        #expect(rights(.leader).searchTypes.contains(.shopping) && !rights(.team).searchTypes.contains(.shopping))
    }

    @Test func linksAreOnlyOpenedWhenTheyAreHttps() throws {
        func file(_ link: String) throws -> CampFileRef {
            try JSONDecoder.api.decode(CampFileRef.self, from: Data(#"{"id":"\#(uid(1))","version":1,"anzeigename":"a","link":"\#(link)","typ":null,"groesse":null,"hinzugefuegtVon":null,"hinzugefuegtAm":"2027-07-01T08:00:00Z"}"#.utf8))
        }
        #expect(try file("https://example.org/a").openableLink != nil)
        #expect(try file("http://example.org/a").openableLink == nil && file("javascript:alert(1)").openableLink == nil)
    }

    @Test func textsFollowTheDesign() throws {
        let document = try JSONDecoder.api.decode(CampDocument.self, from: Data(documentJSON(1).utf8))
        let now = DateFormats.calendarDay("2027-07-19") ?? Date()
        #expect(CampStorageText.subtitle(document).hasPrefix("PDF, 240"))
        #expect(CampStorageText.isNew(document, now: now) && !CampStorageText.isNew(document, now: now.addingTimeInterval(86400 * 30)))
        let link = try JSONDecoder.api.decode(CampDocument.self, from: Data(documentJSON(2, kind: "link", size: nil).utf8))
        #expect(CampStorageText.subtitle(link) == "Link")
        #expect(CampStorageText.term("  ") == nil && CampStorageText.term(" Plan ") == "Plan" && CampStorageText.term(String(repeating: "a", count: 150))?.count == 100)
        #expect(CampStorageText.phoneURL("+41 00 000 00 00")?.absoluteString == "tel:+41000000000" && CampStorageText.phoneURL("abc") == nil)
        #expect(CampStorageText.mailURL("a@example.org")?.absoluteString == "mailto:a@example.org" && CampStorageText.mailURL("a b@c") == nil && CampStorageText.mailURL(nil) == nil)
        #expect(CampStorageText.destination(.document) == .documents && CampStorageText.destination(.task) == nil)
    }

    @Test func hitsAreGroupedByKindInTheOrderOfTheBestHit() throws {
        let hits = try ["aufgabe", "protokoll", "aufgabe"].enumerated().map { index, type in
            try JSONDecoder.api.decode(CampSearchHit.self, from: Data(#"{"typ":"\#(type)","id":"\#(uid(index + 1))","titel":"t","auszug":null}"#.utf8))
        }
        let groups = CampSearchGroup.group(hits)
        #expect(groups.map(\.type) == [.task, .meetingProtocol] && groups[0].title == "Aufgaben, 2" && groups[1].title == "Protokolle, 1")
    }
}

@MainActor
struct CampDocumentsModelTests {
    @Test func loadsAllPagesWithTheFilterAndKeepsLinksOutOfTheModelState() async throws {
        let host = host()
        stub(host) { request in
            let next = request.url?.query?.contains("nach=") == true ? "null" : "\"\(uid(2))\""
            let id = next == "null" ? 2 : 1
            return (200, #"{"dokumente":[\#(documentJSON(id))],"naechster":\#(next)}"#)
        }
        let model = CampDocumentsModel(active: try campActive(host: host))
        model.query = " Plan "
        model.type = .pdf
        await model.load()
        #expect(model.documents.count == 2 && model.phase == .loaded && model.isFiltered)
        let first = try #require(StubProtocol.requests(host: host).first)
        #expect(path(first).hasSuffix("/dokumente") && first.url?.query?.contains("q=Plan") == true && first.url?.query?.contains("typ=pdf") == true)
    }

    @Test func aFailedLoadShowsTheFailureWithoutContent() async throws {
        let host = host()
        stub(host) { _ in (500, "{}") }
        let model = CampDocumentsModel(active: try campActive(.team, host: host))
        await model.load()
        if case .failed = model.phase {} else { Issue.record("expected a failure") }
    }

    @Test func clearingTheFilterReloadsEverything() async throws {
        let model = CampDocumentsModel(active: try campActive(host: host()))
        model.query = "x"
        model.type = .link
        model.clearFilter()
        #expect(!model.isFiltered)
    }
}

@MainActor
struct CampAddressBookModelTests {
    @Test func theCampLeadershipLoadsAndKeepsAContact() async throws {
        let host = host()
        stub(host) { request in
            if request.httpMethod == "PATCH" { return (200, contactJSON(1, keep: true)) }
            return (200, #"{"kontakte":[\#(contactJSON(1))],"naechster":null}"#)
        }
        let model = CampAddressBookModel(active: try campActive(host: host))
        await model.load()
        #expect(model.contacts.count == 1 && !model.isLocked && CampStorageText.cleanUp(model.contacts[0]) != nil)
        await model.setKeep(model.contacts[0], true)
        let patch = try #require(StubProtocol.requests(host: host).first { $0.httpMethod == "PATCH" })
        #expect(path(patch).hasSuffix("/adressbuch/\(uid(1))") && body(patch).contains(#""behalten":true"#) && body(patch).contains(#""version":2"#))
        #expect(model.contacts[0].keep && CampStorageText.cleanUp(model.contacts[0]) == nil)
    }

    @Test func otherRolesAreLockedOutWithoutAnyRequest() async throws {
        let host = host()
        stub(host) { _ in (200, #"{"kontakte":[],"naechster":null}"#) }
        let model = CampAddressBookModel(active: try campActive(.leader, host: host))
        await model.load()
        #expect(model.isLocked && StubProtocol.requests(host: host).isEmpty)
        await model.setKeep(try JSONDecoder.api.decode(CampContact.self, from: Data(contactJSON(1).utf8)), true)
        #expect(StubProtocol.requests(host: host).isEmpty)
    }

    @Test func aForbiddenAnswerLocksTheScreen() async throws {
        let host = host()
        stub(host) { _ in (403, "{}") }
        let model = CampAddressBookModel(active: try campActive(host: host))
        await model.load()
        #expect(model.isLocked)
    }

    @Test func addingNeedsANameAndSortsTheContact() async throws {
        let host = host()
        stub(host) { request in request.httpMethod == "POST" ? (201, contactJSON(5)) : (200, #"{"kontakte":[\#(contactJSON(9))],"naechster":null}"#) }
        let model = CampAddressBookModel(active: try campActive(host: host))
        await model.load()
        #expect(await model.add(name: "  ", phone: "", email: "") == false && model.error != nil)
        #expect(await model.add(name: "Kontakt 5", phone: "+41 00 000 00 00", email: "") == true)
        #expect(model.contacts.map(\.name) == ["Kontakt 5", "Kontakt 9"] && model.notice?.title == "Kontakt gesichert.")
        let post = try #require(StubProtocol.requests(host: host).first { $0.httpMethod == "POST" })
        #expect(path(post).hasSuffix("/adressbuch") && body(post).contains(#""telefon":"+41 00 000 00 00""#) && !body(post).contains("email"))
    }

    @Test func aClosedCampChangesNothing() async throws {
        let host = host()
        stub(host) { _ in (200, #"{"kontakte":[],"naechster":null}"#) }
        let model = CampAddressBookModel(active: try campActive(status: "abgeschlossen", host: host))
        #expect(await model.add(name: "Kontakt", phone: "", email: "") == false)
        #expect(StubProtocol.requests(host: host).isEmpty)
    }
}

@MainActor
struct CampSearchModelTests {
    @Test func searchesWithTheTypeAndShowsOnlyWhatTheServerReturns() async throws {
        let host = host()
        stub(host) { _ in (200, #"{"treffer":[{"typ":"aufgabe","id":"\#(uid(1))","titel":"Offerte","auszug":null},{"typ":"neuerTyp","id":"\#(uid(2))","titel":"x","auszug":"y"}]}"#) }
        let model = CampSearchModel(active: try campActive(.team, host: host))
        model.query = "Offerte"
        model.type = .task
        await model.load()
        #expect(model.hits.count == 2 && model.groups.map(\.type) == [.task, .unknown] && model.phase == .loaded)
        let request = try #require(StubProtocol.requests(host: host).first)
        #expect(path(request).hasSuffix("/suche") && request.url?.query?.contains("q=Offerte") == true && request.url?.query?.contains("typ=aufgabe") == true)
    }

    @Test func aShortQueryAsksNothing() async throws {
        let host = host()
        stub(host) { _ in (200, #"{"treffer":[]}"#) }
        let model = CampSearchModel(active: try campActive(host: host))
        model.query = "O"
        await model.load()
        #expect(model.term == nil && model.hits.isEmpty && StubProtocol.requests(host: host).isEmpty && model.phase == .loaded)
    }

    @Test func aFailureIsShownAndAnEmptyAnswerIsNoFailure() async throws {
        let host = host()
        stub(host) { _ in (500, "{}") }
        let model = CampSearchModel(active: try campActive(host: host))
        model.query = "Oferte"
        await model.load()
        if case .failed = model.phase {} else { Issue.record("expected a failure") }
        stub(host) { _ in (200, #"{"treffer":[]}"#) }
        await model.load()
        #expect(model.phase == .loaded && model.hits.isEmpty)
    }
}
