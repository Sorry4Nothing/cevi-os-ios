import Foundation
import Testing
@testable import CeviOS

private nonisolated let campA = UUID(uuidString: "0190a000-0000-7000-8000-000000000001")!
private nonisolated let campB = UUID(uuidString: "0190a000-0000-7000-8000-000000000002")!
private nonisolated let meetingId = UUID(uuidString: "0190a000-0000-7000-8000-0000000000e1")!
private nonisolated let pdf = Data("%PDF-1.7\n1 0 obj\n".utf8)
private nonisolated let ics = Data("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nEND:VCALENDAR\r\n".utf8)

private func tempDirectory() -> URL { FileManager.default.temporaryDirectory.appending(path: "downloads-\(UUID().uuidString)", directoryHint: .isDirectory) }
private nonisolated func newHost() -> String { "d\(UUID().uuidString.prefix(8).lowercased()).test.example.org" }

private nonisolated func campJSON(_ id: UUID, status: String = "aktiv") -> String {
    """
    {"id":"\(id.uuidString)","titel":"Sommerlager","von":"2027-07-17","bis":"2027-07-24","vorbereitungAb":null,"ort":null,
     "adresse":null,"status":"\(status)","farbe":null,"logoMediumId":null,"wetterOrt":{"status":"kein_ort","name":null},"rolle":"leitung"}
    """
}

private nonisolated func listJSON(_ camps: [(UUID, String)]) -> String { #"{"lager":["# + camps.map { campJSON($0.0, status: $0.1) }.joined(separator: ",") + "]}" }

private func client(host: String, store: any CampDownloadStore) -> APIClient {
    APIClient(baseURL: URL(string: "https://\(host)")!, appVersion: "1.0.0", cookieStore: InMemoryCookieStore(["s": "1"]),
              session: APIClient.makeSession(protocolClasses: [StubProtocol.self]), campDownloads: store)
}

struct CampFileDownloadsTests {
    @Test func aFileIsKeptWithAGeneratedNameAndListed() async throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CampFileDownloads(directory: directory)
        let saved = try await store.save(pdf, source: .handout(.roomList), campId: campA, campTitle: "Sommerlager", title: "Zimmerliste")
        #expect(saved.fileName == saved.id.uuidString.lowercased() + ".pdf" && saved.size == pdf.count && saved.kind == .pdf)
        let url = try #require(await store.fileURL(saved))
        #expect(try Data(contentsOf: url) == pdf && url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL)
        #expect(await store.list() == [saved])
        // A second store on the same folder finds it again (the index is on disk).
        #expect(await CampFileDownloads(directory: directory).list() == [saved])
    }

    @Test func theFolderIsExcludedFromTheBackup() async throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try await CampFileDownloads(directory: directory).save(ics, source: .meetingCalendar(meetingId), campId: campA, campTitle: "S", title: "K")
        #expect(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    @Test func filesOfTheWrongKindOrSizeAreRefused() async {
        let store = CampFileDownloads(directory: tempDirectory())
        for (data, source) in [(Data("<html>Fehler</html>".utf8), CampDownloadSource.handout(.roomList)), (Data(), .handout(.roomList)),
                               (pdf, .meetingCalendar(meetingId)), (ics, .handout(.shiftPlan)),
                               (Data("%PDF-".utf8) + Data(count: CampDownloadKind.maxBytes), .handout(.tripList))] {
            await #expect(throws: CampDownloadError.invalid) { try await store.save(data, source: source, campId: campA, campTitle: "S", title: "T") }
        }
        #expect(await store.list().isEmpty)
    }

    @Test func aNewDownloadReplacesTheOldOfTheSameSource() async throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CampFileDownloads(directory: directory)
        let first = try await store.save(pdf, source: .handout(.roomList), campId: campA, campTitle: "S", title: "Zimmerliste")
        let second = try await store.save(pdf + Data("x".utf8), source: .handout(.roomList), campId: campA, campTitle: "S", title: "Zimmerliste")
        _ = try await store.save(pdf, source: .handout(.roomList), campId: campB, campTitle: "T", title: "Zimmerliste")
        let (firstURL, secondURL, count) = (await store.fileURL(first), await store.fileURL(second), await store.list().count)
        #expect(count == 2 && firstURL == nil && secondURL != nil)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".pdf") }
        #expect(files.count == 2)
    }

    @Test func removeDeletesTheFileAndTheCampTakesItsDownloadsWithIt() async throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CampFileDownloads(directory: directory)
        let one = try await store.save(pdf, source: .handout(.roomList), campId: campA, campTitle: "S", title: "a")
        let two = try await store.save(pdf, source: .handout(.shiftPlan), campId: campA, campTitle: "S", title: "b")
        _ = try await store.save(pdf, source: .handout(.roomList), campId: campB, campTitle: "T", title: "c")
        await store.remove(one.id)
        let (oneURL, left) = (await store.fileURL(one), await store.list().count)
        #expect(oneURL == nil && left == 2)
        await store.removeCamp(campA)
        let (twoURL, camps) = (await store.fileURL(two), await store.list().map(\.campId))
        #expect(twoURL == nil && camps == [campB])
        await store.keepOnly(campIds: [])
        #expect(await store.list().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".pdf") }.isEmpty)
    }

    @Test func removeAllDeletesTheFolder() async throws {
        let directory = tempDirectory()
        let store = CampFileDownloads(directory: directory)
        _ = try await store.save(pdf, source: .handout(.roomList), campId: campA, campTitle: "S", title: "a")
        await store.removeAll()
        let none = await store.list().isEmpty
        #expect(none && !FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func anIndexEntryWithAForeignFileNameIsIgnored() async throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID()
        let evil = CampDownload(id: id, campId: campA, campTitle: "S", title: "x", sourceKey: "aushang:zimmerliste", kind: .pdf,
                                fileName: "../../secret.pdf", savedAt: Date(), size: 1)
        try JSONEncoder().encode([evil]).write(to: directory.appending(path: "index.json"))
        let store = CampFileDownloads(directory: directory)
        let (none, evilURL) = (await store.list().isEmpty, await store.fileURL(evil))
        #expect(none && evilURL == nil)
    }
}

struct CampDownloadClientTests {
    private func serve(_ host: String, camps: [(UUID, String)], _ route: @escaping @Sendable (String) -> (Int, Data) = { _ in (200, Data("{}".utf8)) }) {
        StubProtocol.register(host: host) { request in
            let path = request.url?.path ?? ""
            if path == "/api/v1/lager" { return (200, [:], Data(listJSON(camps).utf8)) }
            let (status, body) = route(path)
            return (status, [:], body)
        }
    }

    @Test func downloadsAreFetchedFromTheDescribedRoutes() async throws {
        let host = newHost()
        serve(host, camps: [(campA, "aktiv")]) { $0.hasSuffix(".ics") ? (200, ics) : (200, pdf) }
        let api = client(host: host, store: CampFileDownloads(directory: tempDirectory()))
        #expect(try await api.campDownloadData(.handout(.doorSigns), campId: campA) == pdf)
        #expect(try await api.campDownloadData(.meetingCalendar(meetingId), campId: campA) == ics)
        let paths = StubProtocol.requests(host: host).compactMap { $0.url?.path }
        #expect(paths.contains("/api/v1/lager/\(campA.uuidString.lowercased())/aushaenge/tuerschilder"))
        #expect(paths.contains("/api/v1/lager/\(campA.uuidString.lowercased())/hoecks/\(meetingId.uuidString.lowercased()).ics"))
    }

    @Test func aCampThatIsGoneFromTheListLosesItsDownloadsButAClosedOneKeepsThem() async throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CampFileDownloads(directory: directory)
        _ = try await store.save(pdf, source: .handout(.roomList), campId: campA, campTitle: "A", title: "a")
        _ = try await store.save(pdf, source: .handout(.roomList), campId: campB, campTitle: "B", title: "b")
        let host = newHost()
        serve(host, camps: [(campB, "abgeschlossen")])
        _ = try await client(host: host, store: store).camps()
        #expect(await store.list().map(\.campId) == [campB])
    }

    @Test func notFoundOnTheCampDeletesItsDownloadsButNoAccessKeepsThem() async throws {
        let store = CampFileDownloads(directory: tempDirectory())
        _ = try await store.save(pdf, source: .handout(.roomList), campId: campA, campTitle: "A", title: "a")
        let host = newHost()
        serve(host, camps: [(campA, "aktiv")]) { _ in (403, Data("{}".utf8)) }
        let api = client(host: host, store: store)
        let _: CampListEntry? = try? await api.load("GET", "/api/v1/lager/\(campA.uuidString.lowercased())")
        #expect(await store.list().count == 1)
        serve(host, camps: [(campA, "aktiv")]) { _ in (404, Data("{}".utf8)) }
        let _: CampListEntry? = try? await api.load("GET", "/api/v1/lager/\(campA.uuidString.lowercased())")
        #expect(await store.list().isEmpty)
    }

    @Test func signOutDeletesAllDownloads() async throws {
        let store = CampFileDownloads(directory: tempDirectory())
        _ = try await store.save(pdf, source: .handout(.roomList), campId: campA, campTitle: "A", title: "a")
        await client(host: newHost(), store: store).clearCampCache()
        #expect(await store.list().isEmpty)
    }
}

@MainActor
struct CampDownloaderTests {
    private func setup(_ route: @escaping @Sendable (String) -> (Int, Data)) async throws -> (CampDownloader, CampFileDownloads, ActiveCamp) {
        let store = CampFileDownloads(directory: tempDirectory())
        let host = newHost()
        StubProtocol.register(host: host) { request in
            let (status, body) = route(request.url?.path ?? "")
            return (status, [:], body)
        }
        let entry = try JSONDecoder.api.decode(CampListEntry.self, from: Data(campJSON(campA).utf8))
        let active = ActiveCamp()
        active.open(entry, client: client(host: host, store: store))
        return (CampDownloader(active: active), store, active)
    }

    @Test func downloadingKeepsTheFileAndSaysSo() async throws {
        let (downloader, store, _) = try await setup { _ in (200, pdf) }
        await downloader.download(.handout(.roomList), title: "Zimmerliste")
        #expect(downloader.saved(.handout(.roomList))?.title == "Zimmerliste" && downloader.error == nil)
        #expect(downloader.notice?.contains("Zimmerliste") == true && downloader.busy.isEmpty)
        #expect(await downloader.url(.handout(.roomList)) != nil)
        await downloader.remove(.handout(.roomList))
        let gone = await store.list().isEmpty
        #expect(downloader.saved(.handout(.roomList)) == nil && gone)
    }

    @Test func aRefusedOrWrongAnswerKeepsNothingAndShowsAnError() async throws {
        let (refused, store, _) = try await setup { _ in (403, Data("{}".utf8)) }
        await refused.download(.handout(.roomList), title: "Zimmerliste")
        #expect(refused.error != nil && refused.saved(.handout(.roomList)) == nil)
        let (wrong, _, _) = try await setup { _ in (200, Data("<html></html>".utf8)) }
        await wrong.download(.handout(.roomList), title: "Zimmerliste")
        #expect(wrong.error == "Die Datei ist nicht gültig. Sie wurde nicht gespeichert.")
        #expect(await store.list().isEmpty)
    }

    @Test func theListShowsOnlyTheOpenCamp() async throws {
        let (downloader, store, _) = try await setup { _ in (200, pdf) }
        _ = try await store.save(pdf, source: .handout(.shiftPlan), campId: campB, campTitle: "B", title: "b")
        await downloader.download(.handout(.roomList), title: "Zimmerliste")
        #expect(downloader.downloads.map(\.campId) == [campA])
    }
}
