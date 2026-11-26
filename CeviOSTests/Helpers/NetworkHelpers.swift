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

nonisolated extension StubProtocol {
    /// Body of a recorded request (URLSession hands it over as a stream).
    static func body(of request: URLRequest) -> Data? {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

/// In-memory key store for the App Attest key ID.
nonisolated final class InMemoryAppAttestKeyStore: AppAttestKeyStore {
    private let contents: Mutex<String?>
    init(_ initial: String? = nil) { contents = Mutex(initial) }
    func read() -> String? { contents.withLock { $0 } }
    func write(_ keyId: String) { contents.withLock { $0 = keyId } }
    func delete() { contents.withLock { $0 = nil } }
}

/// App Attest stand-in: records what was asked and can fail on demand.
nonisolated final class FakeAppAttest: AppAttestProviding {
    struct Failure: Error {}
    let isSupported: Bool
    let failing: Bool
    private let keys = Mutex(0)
    private let hashes = Mutex<[Data]>([])
    private let kinds = Mutex<[String]>([])
    init(isSupported: Bool = true, failing: Bool = false) { self.isSupported = isSupported; self.failing = failing }
    var clientDataHashes: [Data] { hashes.withLock { $0 } }
    /// "key", "attest" or "assert" per call, in order.
    var calls: [String] { kinds.withLock { $0 } }

    func generateKey() async throws -> String {
        kinds.withLock { $0.append("key") }
        if failing { throw Failure() }
        return keys.withLock { $0 += 1; return "key-id-\($0)" }
    }
    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data {
        kinds.withLock { $0.append("attest") }
        hashes.withLock { $0.append(clientDataHash) }
        if failing { throw Failure() }
        return Data("attestation-of-\(keyId)".utf8)
    }
    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data {
        kinds.withLock { $0.append("assert") }
        hashes.withLock { $0.append(clientDataHash) }
        if failing { throw Failure() }
        return Data("assertion-of-\(keyId)".utf8)
    }
}
