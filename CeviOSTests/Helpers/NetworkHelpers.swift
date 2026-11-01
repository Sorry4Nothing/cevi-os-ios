import Foundation
import Synchronization
@testable import CeviOS

/// In-memory cookie store for tests.
nonisolated final class InMemoryCookieStore: CookieStore {
    private let contents: Mutex<[String: String]>
    init(_ initial: [String: String] = [:]) { contents = Mutex(initial) }
    func read() -> [String: String] { contents.withLock { $0 } }
    func write(_ cookies: [String: String]) { contents.withLock { $0 = cookies } }
    func delete() { contents.withLock { $0 = [:] } }
}

/// Answers requests to `*.test.example.org` without a network. Every test uses its own host, so tests run in parallel.
nonisolated final class StubProtocol: URLProtocol {
    typealias Reply = @Sendable (URLRequest) -> (status: Int, headers: [String: String], body: Data)

    private static let replies = Mutex<[String: Reply]>([:])
    private static let recordedRequests = Mutex<[String: [URLRequest]]>([:])

    static func register(host: String, reply: @escaping Reply) {
        replies.withLock { $0[host] = reply }
    }

    static func requests(host: String) -> [URLRequest] {
        recordedRequests.withLock { $0[host] ?? [] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host() ?? ""
        Self.recordedRequests.withLock { $0[host, default: []].append(request) }
        guard let reply = Self.replies.withLock({ $0[host] }), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let result = reply(request)
        let http = HTTPURLResponse(url: url, statusCode: result.status, httpVersion: "HTTP/1.1", headerFields: result.headers)!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: result.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Collects the events of a client.
nonisolated final class EventCollector: Sendable {
    private let list = Mutex<[APIEvent]>([])
    func add(_ e: APIEvent) { list.withLock { $0.append(e) } }
    var all: [APIEvent] { list.withLock { $0 } }
}
