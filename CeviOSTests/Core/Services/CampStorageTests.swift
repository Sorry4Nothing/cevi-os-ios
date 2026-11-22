import Foundation
import Testing
@testable import CeviOS

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder.api.decode(T.self, from: Data(json.utf8))
}

private let uuid1 = "0190a000-0000-7000-8000-000000000001"
private let uuid2 = "0190a000-0000-7000-8000-000000000002"
private let fileJSON = """
{"id":"\(uuid2)","version":1,"anzeigename":"Zeltplan.pdf","link":"https://example.sharepoint.com/f/1","typ":"application/pdf","groesse":1200,
 "hinzugefuegtVon":null,"hinzugefuegtAm":"2027-02-02T08:00:00Z"}
"""
private let documentJSON = """
{"quelle":"dokument","id":"\(uuid1)","version":2,"titel":"Zeltplan","stichworte":["zelt","plan"],"teamSichtbar":true,"datei":\(fileJSON),
 "art":"pdf","sharepoint":true,"erstelltAm":"2027-02-02T08:00:00Z"}
"""
private let contactJSON = """
{"id":"\(uuid1)","version":3,"name":"Beispiel Hof","funktion":"Bauer","gruppe":null,"telefon":"+41 79 000 00 00","email":null,"notiz":null,
 "behalten":false,"aufraeumenAb":"2027-09-01","erstelltAm":"2027-02-02T08:00:00Z"}
"""

struct CampStorageModelTests {
    @Test func documentCarriesVersionFileAndKind() throws {
        let page = try decode(CampDocumentPage.self, #"{"dokumente":[\#(documentJSON)],"naechster":"\#(uuid2)"}"#)
        let document = try #require(page.documents.first)
        #expect(document.version == 2 && document.kind == .pdf && document.isSharePoint == true && document.file?.displayName == "Zeltplan.pdf")
        #expect(page.next?.uuidString.lowercased() == uuid2)
    }

    @Test func documentOfAnotherModuleWithDeletedFileDecodes() throws {
        let json = #"{"quelle":"lager_pinnwand","id":"\#(uuid1)","version":null,"titel":"Bild","stichworte":[],"teamSichtbar":null,"datei":null,"art":null,"sharepoint":null,"erstelltAm":"2027-02-02T08:00:00Z"}"#
        let document = try decode(CampDocument.self, json)
        #expect(document.version == nil && document.file == nil && document.kind == nil && document.teamVisible == nil)
    }

    @Test func unknownDocumentKindDoesNotBreakTheList() throws {
        let json = documentJSON.replacing(#""art":"pdf""#, with: #""art":"video""#)
        #expect(try decode(CampDocument.self, json).kind == .unknown)
        #expect(try decode(CampDocument.self, documentJSON.replacing(#""art":"pdf""#, with: #""art":"bild""#)).kind == .image)
    }

    @Test func fileLinkOpensOnlyOverHttps() throws {
        let file = try decode(CampFileRef.self, fileJSON)
        #expect(file.openableLink == file.link)
        let plain = try decode(CampFileRef.self, fileJSON.replacing("https://", with: "http://"))
        #expect(plain.openableLink == nil)
        let other = try decode(CampFileRef.self, fileJSON.replacing("https://example.sharepoint.com/f/1", with: "file:///etc/hosts"))
        #expect(other.openableLink == nil)
    }

    @Test func contactDecodesWithCleanUpDay() throws {
        let page = try decode(CampContactPage.self, #"{"kontakte":[\#(contactJSON)],"naechster":null}"#)
        let contact = try #require(page.contacts.first)
        #expect(contact.version == 3 && contact.keep == false && contact.cleanUpFrom != nil && contact.phone == "+41 79 000 00 00" && page.next == nil)
        let kept = try decode(CampContact.self, contactJSON.replacing(#""behalten":false,"aufraeumenAb":"2027-09-01""#, with: #""behalten":true,"aufraeumenAb":null"#))
        #expect(kept.keep && kept.cleanUpFrom == nil)
    }

    @Test func searchHitsDecodeAndUnknownTypeIsTolerated() throws {
        let json = #"{"treffer":[{"typ":"aufgabe","id":"\#(uuid1)","titel":"Zelte","auszug":null},{"typ":"neu","id":"\#(uuid2)","titel":"X","auszug":"…Zelt…"}]}"#
        let result = try decode(CampSearchResult.self, json)
        #expect(result.hits.map(\.type) == [.task, .unknown] && result.hits[0].excerpt == nil && result.hits[1].excerpt == "…Zelt…")
    }

    @Test func documentFilterBuildsQuery() {
        let items = CampDocumentFilter(search: "zelt", keywords: ["a", "b"], type: .sharepoint).queryItems
        #expect(items.contains(URLQueryItem(name: "q", value: "zelt")) && items.contains(URLQueryItem(name: "stichwort", value: "a,b")))
        #expect(items.contains(URLQueryItem(name: "typ", value: "sharepoint")))
        #expect(CampDocumentFilter().queryItems.isEmpty)
    }

    @Test func contactPatchClearsWithNull() throws {
        var patch = CampContactPatch(version: 3)
        patch.phone = .clear
        patch.keep = true
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder.api.encode(patch)) as? [String: Any])
        #expect(object["telefon"] is NSNull && object["behalten"] as? Bool == true && object["email"] == nil && object["version"] as? Int == 3)
    }

    @Test func linkErrorCodesAreNamed() {
        #expect(CampRules.linkInvalidCode == "LINK_UNGUELTIG" && CampRules.linkHostNotAllowedCode == "LINK_HOST_NICHT_ERLAUBT")
    }
}

struct CampStorageServiceTests {
    private let camp = UUID(), id = UUID(), other = UUID()
    private var campPath: String { "/api/v1/lager/\(camp.uuidString.lowercased())" }
    private var idText: String { id.uuidString.lowercased() }

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

    @Test func fileRoutes() async throws {
        let link = URL(string: "https://example.sharepoint.com/f/1")!
        var r = try await sent(status: 201, fileJSON) { _ = try await $0.createCampFile(campId: camp, CampFileCreate(displayName: "Zeltplan.pdf", link: link, type: "application/pdf", size: 1200)) }
        #expect(r.method == "POST" && r.path == campPath + "/dateien" && r.body?["anzeigename"] as? String == "Zeltplan.pdf" && r.body?["groesse"] as? Int == 1200)
        r = try await sent(fileJSON) { _ = try await $0.campFile(campId: camp, fileId: id) }
        #expect(r.method == "GET" && r.path == campPath + "/dateien/" + idText)
        r = try await sent(status: 204, "") { try await $0.deleteCampFile(campId: camp, fileId: id, version: 1) }
        #expect(r.method == "DELETE" && r.path == campPath + "/dateien/" + idText && r.query["version"] == "1")
    }

    @Test func documentRoutes() async throws {
        var r = try await sent(#"{"dokumente":[],"naechster":null}"#) {
            _ = try await $0.campDocuments(campId: camp, filter: CampDocumentFilter(search: "zelt", type: .pdf), after: other, limit: 20)
        }
        #expect(r.method == "GET" && r.path == campPath + "/dokumente" && r.query["q"] == "zelt" && r.query["typ"] == "pdf" && r.query["limit"] == "20" && r.query["nach"] == other.uuidString.lowercased())
        r = try await sent(documentJSON) { _ = try await $0.campDocument(campId: camp, documentId: id) }
        #expect(r.method == "GET" && r.path == campPath + "/dokumente/" + idText)
        r = try await sent(status: 201, documentJSON) { _ = try await $0.createCampDocument(campId: camp, CampDocumentCreate(title: "Zeltplan", fileId: other, teamVisible: true)) }
        #expect(r.method == "POST" && r.path == campPath + "/dokumente" && r.body?["titel"] as? String == "Zeltplan" && r.body?["teamSichtbar"] as? Bool == true)
        r = try await sent(documentJSON) { _ = try await $0.updateCampDocument(campId: camp, documentId: id, CampDocumentPatch(version: 2, keywords: ["a"])) }
        #expect(r.method == "PATCH" && r.path == campPath + "/dokumente/" + idText && r.body?["version"] as? Int == 2 && r.body?["stichworte"] as? [String] == ["a"])
        r = try await sent(status: 204, "") { try await $0.deleteCampDocument(campId: camp, documentId: id, version: 2) }
        #expect(r.method == "DELETE" && r.path == campPath + "/dokumente/" + idText && r.query["version"] == "2")
    }

    @Test func contactRoutes() async throws {
        var r = try await sent(#"{"kontakte":[],"naechster":null}"#) { _ = try await $0.campContacts(campId: camp, search: "hof", limit: 10) }
        #expect(r.method == "GET" && r.path == campPath + "/adressbuch" && r.query["q"] == "hof" && r.query["limit"] == "10")
        r = try await sent(contactJSON) { _ = try await $0.campContact(campId: camp, contactId: id) }
        #expect(r.method == "GET" && r.path == campPath + "/adressbuch/" + idText)
        r = try await sent(status: 201, contactJSON) { _ = try await $0.createCampContact(campId: camp, CampContactCreate(name: "Beispiel Hof", phone: "0790000000", keep: true)) }
        #expect(r.method == "POST" && r.path == campPath + "/adressbuch" && r.body?["telefon"] as? String == "0790000000" && r.body?["behalten"] as? Bool == true)
        r = try await sent(contactJSON) { _ = try await $0.updateCampContact(campId: camp, contactId: id, CampContactPatch(version: 3, keep: false)) }
        #expect(r.method == "PATCH" && r.path == campPath + "/adressbuch/" + idText && r.body?["behalten"] as? Bool == false)
        r = try await sent(status: 204, "") { try await $0.deleteCampContact(campId: camp, contactId: id, version: 3) }
        #expect(r.method == "DELETE" && r.path == campPath + "/adressbuch/" + idText && r.query["version"] == "3")
    }

    @Test func searchRoute() async throws {
        let r = try await sent(#"{"treffer":[]}"#) { let value = try await $0.searchCamp(campId: camp, text: "Zelt", type: .document); #expect(value.hits.isEmpty) }
        #expect(r.method == "GET" && r.path == campPath + "/suche" && r.query["q"] == "Zelt" && r.query["typ"] == "dokument")
    }
}
