import Foundation
import Synchronization
@testable import CeviOS

/// Cookie-Speicher im Arbeitsspeicher für Tests.
nonisolated final class ArbeitsspeicherCookies: CookieSpeicher {
    private let inhalt: Mutex<[String: String]>
    init(_ start: [String: String] = [:]) { inhalt = Mutex(start) }
    func lesen() -> [String: String] { inhalt.withLock { $0 } }
    func schreiben(_ cookies: [String: String]) { inhalt.withLock { $0 = cookies } }
    func loeschen() { inhalt.withLock { $0 = [:] } }
}

/// Antwortet auf Anfragen an `*.test.example.org`, ohne Netz. Jeder Test nutzt einen eigenen Host, so laufen Tests parallel.
nonisolated final class StubProtokoll: URLProtocol {
    typealias Antwort = @Sendable (URLRequest) -> (status: Int, kopfzeilen: [String: String], body: Data)

    private static let antworten = Mutex<[String: Antwort]>([:])
    private static let anfragen = Mutex<[String: [URLRequest]]>([:])

    static func registrieren(host: String, antwort: @escaping Antwort) {
        antworten.withLock { $0[host] = antwort }
    }

    static func anfragen(host: String) -> [URLRequest] {
        anfragen.withLock { $0[host] ?? [] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host() ?? ""
        Self.anfragen.withLock { $0[host, default: []].append(request) }
        guard let antwort = Self.antworten.withLock({ $0[host] }), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let ergebnis = antwort(request)
        let http = HTTPURLResponse(url: url, statusCode: ergebnis.status, httpVersion: "HTTP/1.1", headerFields: ergebnis.kopfzeilen)!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: ergebnis.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Sammelt die Ereignisse eines Clients.
nonisolated final class EreignisSammler: Sendable {
    private let liste = Mutex<[APIEreignis]>([])
    func hinzufuegen(_ e: APIEreignis) { liste.withLock { $0.append(e) } }
    var alle: [APIEreignis] { liste.withLock { $0 } }
}
