import CryptoKit
import Foundation
import Testing
@testable import CeviOS

private nonisolated let campA = UUID(uuidString: "0190a000-0000-7000-8000-000000000001")!
private nonisolated let campB = UUID(uuidString: "0190a000-0000-7000-8000-000000000002")!
private nonisolated func campPath(_ id: UUID, _ rest: String = "") -> String { "/api/v1/lager/\(id.uuidString.lowercased())\(rest)" }
private nonisolated func newHost() -> String { "c\(UUID().uuidString.prefix(8).lowercased()).test.example.org" }

private func tempDirectory() -> URL { FileManager.default.temporaryDirectory.appending(path: "cache-\(UUID().uuidString)", directoryHint: .isDirectory) }

private func entry(_ text: String, at date: Date = Date(timeIntervalSince1970: 1_800_000_000)) -> CampCacheEntry {
    CampCacheEntry(data: Data(text.utf8), storedAt: date)
}

private nonisolated func campJSON(_ id: UUID, status: String = "aktiv") -> String {
    """
    {"id":"\(id.uuidString)","titel":"Sommerlager","von":"2027-07-17","bis":"2027-07-24","vorbereitungAb":null,"ort":null,
     "adresse":null,"status":"\(status)","farbe":null,"logoMediumId":null,"wetterOrt":{"status":"kein_ort","name":null},"rolle":"team"}
    """
}

private nonisolated func listJSON(_ camps: [(UUID, String)]) -> String { #"{"lager":["# + camps.map { campJSON($0.0, status: $0.1) }.joined(separator: ",") + "]}" }

private func makeClient(host: String, cache: any CampCache) -> APIClient {
    APIClient(baseURL: URL(string: "https://\(host)")!, appVersion: "1.0.0", cookieStore: InMemoryCookieStore(["s": "1"]),
              session: APIClient.makeSession(protocolClasses: [StubProtocol.self]), campCache: cache)
}

/// A server that is online (`up`) or answers nothing (`StubProtocol` fails without a registered host).
private func serve(_ host: String, _ routes: @escaping @Sendable (String) -> (Int, String)) {
    StubProtocol.register(host: host) { request in
        let (status, body) = routes(request.url?.path ?? "")
        return (status, [:], Data(body.utf8))
    }
}

struct CampFileCacheTests {
    @Test func roundTripIsEncryptedOnDisk() async throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = CampFileCache(directory: directory, keys: MemoryCampCacheKeyStore())
        await cache.store(entry("Kochen um sechs, Notfall 144"), scope: campA, key: "infos")
        #expect(await cache.entry(scope: campA, key: "infos") == entry("Kochen um sechs, Notfall 144"))
        let raw = try Data(contentsOf: await cache.url(campA))
        #expect(raw.range(of: Data("Notfall".utf8)) == nil && raw.range(of: Data("infos".utf8)) == nil)
    }

    @Test func aChangedFileIsDiscardedAndDeleted() async throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = CampFileCache(directory: directory, keys: MemoryCampCacheKeyStore())
        await cache.store(entry("a"), scope: campA, key: "k")
        let file = await cache.url(campA)
        var raw = try Data(contentsOf: file)
        raw[raw.count / 2] ^= 0xFF
        try raw.write(to: file)
        #expect(await cache.entry(scope: campA, key: "k") == nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func aFileMovedToAnotherCampDoesNotOpen() async throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = CampFileCache(directory: directory, keys: MemoryCampCacheKeyStore())
        await cache.store(entry("a"), scope: campA, key: "k")
        try FileManager.default.moveItem(at: await cache.url(campA), to: await cache.url(campB))
        #expect(await cache.entry(scope: campB, key: "k") == nil)
    }

    @Test func aWrongKeyDiscardsTheFile() async {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        await CampFileCache(directory: directory, keys: MemoryCampCacheKeyStore()).store(entry("a"), scope: campA, key: "k")
        #expect(await CampFileCache(directory: directory, keys: MemoryCampCacheKeyStore()).entry(scope: campA, key: "k") == nil)
    }

    @Test func fileAndFolderAreExcludedFromBackupAndProtected() async throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = CampFileCache(directory: directory, keys: MemoryCampCacheKeyStore())
        await cache.store(entry("a"), scope: campA, key: "k")
        #expect(try await cache.url(campA).resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        #expect(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    @Test func keepOnlyDeletesOtherCampsButNotTheList() async {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = CampFileCache(directory: directory, keys: MemoryCampCacheKeyStore())
        await cache.store(entry("a"), scope: campA, key: "k")
        await cache.store(entry("b"), scope: campB, key: "k")
        await cache.store(entry("l"), scope: nil, key: "list")
        await cache.keepOnly(campIds: [campA])
        #expect(await cache.entry(scope: campA, key: "k") != nil)
        #expect(await cache.entry(scope: campB, key: "k") == nil)
        #expect(await cache.entry(scope: nil, key: "list") != nil)
        await cache.removeAll()
        #expect(await cache.entry(scope: campA, key: "k") == nil && !FileManager.default.fileExists(atPath: directory.path))
    }
}

struct CampCachePolicyTests {
    @Test func onlyTheNamedAreasAreCached() {
        for area in CampCachePolicy.allowedAreas { #expect(CampCachePolicy.target(path: campPath(campA, "/\(area)"), query: []) != nil) }
        #expect(CampCachePolicy.target(path: campPath(campA), query: [])?.isCampDetail == true)
        #expect(CampCachePolicy.target(path: "/api/v1/lager", query: [])?.scope == nil)
    }

    @Test func listsOfChildrenAndPrivateAreasAreNeverCached() {
        let never = ["teilnehmer", "zimmer", "fahrten", "gruppen", "anwesenheit", "abzaehlen", "adressbuch", "eingang", "suche", "rechte",
                     "mitglieder", "schichtplan", "diensttausch", "todos", "protokolle", "hoecks", "dateien", "dokumente", "aenderungen"]
        for area in never {
            #expect(CampCachePolicy.target(path: campPath(campA, "/\(area)"), query: []) == nil, "\(area)")
            #expect(CampCachePolicy.target(path: campPath(campA, "/\(area)/\(campB.uuidString.lowercased())"), query: []) == nil)
        }
        #expect(CampCachePolicy.target(path: "/api/v1/lager/aufloesen/aufgabe/x", query: []) == nil)
        #expect(CampCachePolicy.target(path: "/api/v1/ich", query: []) == nil)
    }

    @Test func theQueryIsPartOfTheKey() {
        let a = CampCachePolicy.target(path: campPath(campA, "/aufgaben"), query: [URLQueryItem(name: "limit", value: "100")])
        let b = CampCachePolicy.target(path: campPath(campA, "/aufgaben"), query: [URLQueryItem(name: "limit", value: "50")])
        #expect(a != b)
    }
}

private nonisolated struct Anything: Decodable, Sendable {}

private final class Stamp: @unchecked Sendable {
    var value: Date?
    var told = false
}

struct CampCacheClientTests {
    private nonisolated static let tasks = #"{"aufgaben":[],"naechster":null}"#

    /// A client of an unknown host: every request fails like a missing network.
    private func offline(_ cache: any CampCache) -> APIClient { makeClient(host: newHost(), cache: cache) }

    private func online(_ cache: any CampCache, camps: [(UUID, String)] = [(campA, "aktiv")], _ route: @escaping @Sendable (String) -> (Int, String) = { _ in (200, Self.tasks) }) async throws -> APIClient {
        let host = newHost()
        serve(host) { $0 == "/api/v1/lager" ? (200, listJSON(camps)) : route($0) }
        let client = makeClient(host: host, cache: cache)
        _ = try await client.camps()
        return client
    }

    @Test func aReadIsKeptAndAnsweredFromTheCacheWithoutNetwork() async throws {
        let cache = CampMemoryCache()
        let client = try await online(cache)
        let fresh = Stamp()
        client.setCacheObserver { fresh.value = $0; fresh.told = true }
        let page: CampTaskPage = try await client.load("GET", campPath(campA, "/aufgaben"))
        #expect(page.tasks.isEmpty && fresh.told && fresh.value == nil)

        let away = offline(cache)
        let stamp = Stamp()
        away.setCacheObserver { stamp.value = $0 }
        let again: CampTaskPage = try await away.load("GET", campPath(campA, "/aufgaben"))
        #expect(again == page && stamp.value != nil)
        // What was never loaded is not there.
        await #expect(throws: APIError.self) { let _: CampTaskPage = try await away.load("GET", campPath(campA, "/pinnwand")) }
    }

    @Test func theCampListIsAvailableWithoutNetworkToo() async throws {
        let cache = CampMemoryCache()
        _ = try await online(cache)
        let list = try await offline(cache).camps()
        #expect(list.map(\.id) == [campA])
    }

    @Test func aClosedCampIsNeverWritten() async throws {
        let cache = CampMemoryCache()
        let client = try await online(cache, camps: [(campA, "abgeschlossen")])
        let _: CampTaskPage = try await client.load("GET", campPath(campA, "/aufgaben"))
        #expect(await cache.campIds.isEmpty)
    }

    @Test func nothingIsWrittenBeforeTheListSaysTheCampIsOpen() async throws {
        let cache = CampMemoryCache()
        let host = newHost()
        serve(host) { _ in (200, Self.tasks) }
        let _: CampTaskPage = try await makeClient(host: host, cache: cache).load("GET", campPath(campA, "/aufgaben"))
        #expect(await cache.campIds.isEmpty)
    }

    @Test func campsMissingFromTheListOrClosedAreDeleted() async throws {
        let cache = CampMemoryCache()
        await cache.store(entry("x"), scope: campA, key: "k")
        await cache.store(entry("x"), scope: campB, key: "k")
        _ = try await online(cache, camps: [(campA, "aktiv"), (campB, "archiviert")])
        #expect(await cache.campIds == [campA])
        _ = try await online(cache, camps: [])
        #expect(await cache.campIds.isEmpty)
    }

    @Test func notFoundOnTheCampDeletesItsData() async throws {
        let cache = CampMemoryCache()
        let client = try await online(cache) { $0 == campPath(campA) ? (404, "{}") : (200, Self.tasks) }
        let _: CampTaskPage = try await client.load("GET", campPath(campA, "/aufgaben"))
        #expect(await cache.campIds == [campA])
        await #expect(throws: APIError.self) { let _: Anything = try await client.load("GET", campPath(campA)) }
        #expect(await cache.campIds.isEmpty)
    }

    @Test func noAccessOnAnAreaDeletesThatEntry() async throws {
        let cache = CampMemoryCache()
        let client = try await online(cache) { $0.hasSuffix("/pinnwand") ? (403, "{}") : (200, Self.tasks) }
        let _: CampTaskPage = try await client.load("GET", campPath(campA, "/aufgaben"))
        await cache.store(entry("old"), scope: campA, key: "pinnwand")
        await #expect(throws: APIError.self) { let _: Anything = try await client.load("GET", campPath(campA, "/pinnwand")) }
        #expect(await cache.entry(scope: campA, key: "pinnwand") == nil)
    }

    @Test func excludedAreasAreNeverWritten() async throws {
        let cache = CampMemoryCache()
        let client = try await online(cache) { _ in (200, "{}") }
        for area in ["teilnehmer", "zimmer", "fahrten", "gruppen", "anwesenheit", "abzaehlen", "adressbuch", "eingang", "suche", "rechte"] {
            let _: Anything = try await client.load("GET", campPath(campA, "/\(area)"))
        }
        #expect(await cache.campIds.isEmpty)
    }

    @Test func writesAreNeverCached() async throws {
        let cache = CampMemoryCache()
        let client = try await online(cache)
        let _: Anything = try await client.load("POST", campPath(campA, "/aufgaben"), body: ["titel": "x"])
        #expect(await cache.campIds.isEmpty)
    }

    @Test func signOutDeletesEverythingAndStopsWriting() async throws {
        let cache = CampMemoryCache()
        let client = try await online(cache)
        let _: CampTaskPage = try await client.load("GET", campPath(campA, "/aufgaben"))
        await client.clearCampCache()
        let listKept = await cache.hasListEntry
        #expect(await cache.campIds.isEmpty && !listKept)
        let _: CampTaskPage = try await client.load("GET", campPath(campA, "/aufgaben"))
        #expect(await cache.campIds.isEmpty)
    }
}

@MainActor
struct CampCacheScreenTests {
    @Test func aScreenShowsTheCachedStateWithoutNetworkAndSaysSo() async throws {
        let cache = CampMemoryCache()
        let host = newHost()
        serve(host) { path in
            path == "/api/v1/lager" ? (200, listJSON([(campA, "aktiv")]))
                : (200, #"{"abschnitte":[{"id":"0190a000-0000-7000-8000-000000000077","version":1,"titel":"Lagerhaus","text":null,"links":[],"nurLagerleitung":false,"notfall":false,"reihenfolge":1,"dateien":[]}],"naechster":null}"#)
        }
        let client = makeClient(host: host, cache: cache)
        _ = try await client.camps()
        let entry = try JSONDecoder.api.decode(CampListEntry.self, from: Data(campJSON(campA).utf8))

        let active = ActiveCamp()
        active.open(entry, client: client)
        let model = CampInfosModel(active: active)
        await model.load()
        #expect(model.infos.map(\.title) == ["Lagerhaus"] && active.cachedSince == nil)

        let away = ActiveCamp()
        away.open(entry, client: makeClient(host: newHost(), cache: cache))
        let offlineModel = CampInfosModel(active: away)
        await offlineModel.load()
        #expect(offlineModel.infos.map(\.title) == ["Lagerhaus"] && offlineModel.phase == .loaded)
        #expect(away.cachedSince != nil)
        // Leaving the camp clears the hint.
        away.leave()
        #expect(away.cachedSince == nil)
    }

    @Test func withoutACacheTheScreenShowsTheOfflineState() async throws {
        let entry = try JSONDecoder.api.decode(CampListEntry.self, from: Data(campJSON(campA).utf8))
        let active = ActiveCamp()
        active.open(entry, client: makeClient(host: newHost(), cache: CampMemoryCache()))
        let model = CampInfosModel(active: active)
        await model.load()
        #expect(model.infos.isEmpty && model.phase != .loaded && active.cachedSince == nil)
    }
}
