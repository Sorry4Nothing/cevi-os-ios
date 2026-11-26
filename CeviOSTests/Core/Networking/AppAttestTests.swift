import Foundation
import Synchronization
import Testing
@testable import CeviOS

struct AppAttestTests {
    nonisolated static let nonce = "mMn3wC0Rk9fVZ1Qp0eB8yq5H1b5d2xWw6tq3T8aJm0A"
    nonisolated static let ticket = "Zm9vYmFyLWJhei1xdXV4LWVpbi10aWNrZXQtMTIzNDU"

    /// Stub server for the proof routes and sign-in. `proofStatuses` are used one by one, the last one repeats.
    final class Server: Sendable {
        let host = "a\(UUID().uuidString.prefix(8).lowercased()).test.example.org"
        init(challengeStatus: Int = 200, proofStatuses: [Int] = [200], signInStatus: Int = 200) {
            let challenges = Mutex(0), proofs = Mutex(0)
            StubProtocol.register(host: host) { request in
                let error = { (code: String) in Data(#"{"code":"\#(code)","message":"Servertext."}"#.utf8) }
                switch request.url?.path ?? "" {
                case "/api/v1/app/nachweis/challenge":
                    guard challengeStatus == 200 else { return (challengeStatus, [:], error("NICHT_GEFUNDEN")) }
                    let n = challenges.withLock { $0 += 1; return $0 }
                    let nonce = String(AppAttestTests.nonce.dropLast()) + String(n)
                    return (200, [:], Data(#"{"nonce":"\#(nonce)","laeuftAb":"2026-11-25T12:05:00.000Z","plattform":"ios","appId":"ABCDE12345.ch.example.cevios","umgebung":"production"}"#.utf8))
                case "/api/v1/app/nachweis":
                    let n = proofs.withLock { $0 += 1; return $0 }
                    let status = proofStatuses[min(n, proofStatuses.count) - 1]
                    return status == 200
                        ? (200, [:], Data(#"{"ticket":"\#(AppAttestTests.ticket)","laeuftAb":"2026-11-25T12:02:00.000Z"}"#.utf8))
                        : (status, [:], error("APP_NACHWEIS_UNGUELTIG"))
                default:
                    return (signInStatus, [:], signInStatus == 200 ? Data("{}".utf8) : error("APP_NACHWEIS_UNGUELTIG"))
                }
            }
        }
        var paths: [String] { StubProtocol.requests(host: host).map { $0.url?.path ?? "" } }
        func requests(_ path: String) -> [URLRequest] { StubProtocol.requests(host: host).filter { $0.url?.path == path } }
    }

    private func client(_ server: Server, _ fake: FakeAppAttest, store: InMemoryAppAttestKeyStore = InMemoryAppAttestKeyStore()) -> APIClient {
        APIClient(
            baseURL: URL(string: "https://\(server.host)")!, appVersion: "1.0.0", cookieStore: InMemoryCookieStore(),
            session: APIClient.makeSession(protocolClasses: [StubProtocol.self]),
            appAttest: AppAttestSetup(provider: fake, keyStore: store)
        )
    }

    private func body(_ request: URLRequest) -> [String: Any] {
        // URLSession hands the body to the protocol as a stream.
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                data.append(buffer, count: n)
            }
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    @Test func bindingFollowsTheFormula() {
        // SHA-256 of "<nonce>\nanna"; the user name counts in lowercase.
        let expected = "f2517e823b1f74898f7c0138b980bd06f224198b0f6d445fc9c763afd9e431d0"
        for name in ["anna", "Anna", "ANNA"] {
            let hash = AppAttestBinding.hash(nonce: Self.nonce, username: name)
            #expect(hash.count == 32)
            #expect(hash.map { String(format: "%02x", $0) }.joined() == expected)
        }
    }

    @Test func decodesChallengeAndTicket() throws {
        let challenge = try JSONDecoder.api.decode(AppAttestChallenge.self, from: Data(#"{"nonce":"\#(Self.nonce)","laeuftAb":"2026-11-25T12:05:00.000Z","plattform":"ios","appId":"X.y","umgebung":"production"}"#.utf8))
        #expect(challenge.nonce == Self.nonce)
        let ticket = try JSONDecoder.api.decode(AppAttestTicket.self, from: Data(#"{"ticket":"\#(Self.ticket)","laeuftAb":"2026-11-25T12:02:00.000Z"}"#.utf8))
        #expect(ticket.ticket == Self.ticket)
    }

    @Test func firstSignInAttestsAndSendsTheTicket() async throws {
        let server = Server()
        let fake = FakeAppAttest()
        let store = InMemoryAppAttestKeyStore()
        _ = try await client(server, fake, store: store).signIn(username: "Anna", password: "pw")

        #expect(server.paths == ["/api/v1/app/nachweis/challenge", "/api/v1/app/nachweis", "/api/auth/sign-in/username"])
        #expect(body(server.requests("/api/v1/app/nachweis/challenge")[0])["plattform"] as? String == "ios")
        let proof = body(server.requests("/api/v1/app/nachweis")[0])
        #expect(proof["benutzername"] as? String == "Anna")
        #expect(proof["schluesselId"] as? String == "key-id-1")
        #expect(proof["attestation"] as? String == Data("attestation-of-key-id-1".utf8).base64EncodedString())
        #expect(proof["assertion"] == nil)
        #expect(fake.clientDataHashes == [AppAttestBinding.hash(nonce: proof["nonce"] as? String ?? "", username: "anna")])
        #expect(server.requests("/api/auth/sign-in/username")[0].value(forHTTPHeaderField: "X-Cevi-Nachweis") == Self.ticket)
        #expect(store.read() == "key-id-1")
    }

    @Test func laterSignInsAssertAndEveryAttemptGetsANewChallenge() async throws {
        let server = Server()
        let fake = FakeAppAttest()
        let c = client(server, fake, store: InMemoryAppAttestKeyStore("key-id-1"))
        _ = try await c.signIn(username: "anna", password: "pw")
        _ = try await c.signIn(username: "anna", password: "pw")

        #expect(fake.calls == ["assert", "assert"])
        let proofs = server.requests("/api/v1/app/nachweis").map(body)
        #expect(proofs.count == 2)
        #expect(proofs[0]["assertion"] != nil && proofs[0]["attestation"] == nil)
        #expect(proofs[0]["nonce"] as? String != proofs[1]["nonce"] as? String)
        #expect(server.requests("/api/v1/app/nachweis/challenge").count == 2)
    }

    @Test func challengeNotFoundSignsInWithoutTicket() async throws {
        let server = Server(challengeStatus: 404)
        let fake = FakeAppAttest()
        _ = try await client(server, fake).signIn(username: "anna", password: "pw")
        #expect(server.paths == ["/api/v1/app/nachweis/challenge", "/api/auth/sign-in/username"])
        #expect(server.requests("/api/auth/sign-in/username")[0].value(forHTTPHeaderField: "X-Cevi-Nachweis") == nil)
        #expect(fake.calls.isEmpty)
    }

    @Test func unsupportedDeviceDoesNotCallTheServerForAProof() async throws {
        let server = Server()
        _ = try await client(server, FakeAppAttest(isSupported: false)).signIn(username: "anna", password: "pw")
        #expect(server.paths == ["/api/auth/sign-in/username"])
        let plain = APIClient(
            baseURL: URL(string: "https://\(server.host)")!, appVersion: "1.0.0", cookieStore: InMemoryCookieStore(),
            session: APIClient.makeSession(protocolClasses: [StubProtocol.self])
        )
        _ = try await plain.signIn(username: "anna", password: "pw")
        #expect(server.requests("/api/v1/app/nachweis/challenge").isEmpty)
    }

    @Test func appleErrorSignsInWithoutTicketAndKeepsNoKey() async throws {
        let server = Server()
        let store = InMemoryAppAttestKeyStore()
        let result = try await client(server, FakeAppAttest(failing: true), store: store).signIn(username: "anna", password: "pw")
        #expect(result == .signedIn)
        #expect(server.requests("/api/v1/app/nachweis").isEmpty)
        #expect(server.requests("/api/auth/sign-in/username")[0].value(forHTTPHeaderField: "X-Cevi-Nachweis") == nil)
        #expect(store.read() == nil)
    }

    @Test func serverErrorOnTheProofSignsInWithoutTicket() async throws {
        let server = Server(proofStatuses: [503])
        let store = InMemoryAppAttestKeyStore("key-id-1")
        _ = try await client(server, FakeAppAttest(), store: store).signIn(username: "anna", password: "pw")
        #expect(server.requests("/api/auth/sign-in/username")[0].value(forHTTPHeaderField: "X-Cevi-Nachweis") == nil)
        #expect(store.read() == "key-id-1") // a 503 says nothing about the key
    }

    @Test func rejectedAssertionReplacesTheKeyWithAFreshAttestation() async throws {
        let server = Server(proofStatuses: [401, 200])
        let fake = FakeAppAttest()
        let store = InMemoryAppAttestKeyStore("old-key")
        _ = try await client(server, fake, store: store).signIn(username: "anna", password: "pw")

        #expect(fake.calls == ["assert", "key", "attest"])
        #expect(server.requests("/api/v1/app/nachweis/challenge").count == 2)
        #expect(server.requests("/api/auth/sign-in/username")[0].value(forHTTPHeaderField: "X-Cevi-Nachweis") == Self.ticket)
        #expect(store.read() == "key-id-1")
    }

    @Test func keyIsNotStoredWhenTheServerRejectsTheAttestation() async throws {
        let server = Server(proofStatuses: [401])
        let fake = FakeAppAttest()
        let store = InMemoryAppAttestKeyStore()
        _ = try await client(server, fake, store: store).signIn(username: "anna", password: "pw")
        #expect(store.read() == nil)
        #expect(fake.calls == ["key", "attest", "key", "attest"]) // one retry with a new key, then give up
        #expect(server.requests("/api/auth/sign-in/username")[0].value(forHTTPHeaderField: "X-Cevi-Nachweis") == nil)
    }

    @Test func proofErrorDoesNotEndTheSession() async throws {
        // A 401 of the proof route must not trigger the app-wide «session ended» event.
        let events = EventCollector()
        let server = Server(proofStatuses: [401])
        let c = APIClient(
            baseURL: URL(string: "https://\(server.host)")!, appVersion: "1.0.0", cookieStore: InMemoryCookieStore(),
            session: APIClient.makeSession(protocolClasses: [StubProtocol.self]),
            appAttest: AppAttestSetup(provider: FakeAppAttest(), keyStore: InMemoryAppAttestKeyStore()),
            onEvent: { events.add($0) }
        )
        _ = try await c.signIn(username: "anna", password: "pw")
        #expect(events.all.isEmpty)
    }

    @Test func rejectedTicketShowsTheServerTextAndLeaksNothing() async throws {
        let server = Server(signInStatus: 401)
        let fake = FakeAppAttest()
        do {
            _ = try await client(server, fake).signIn(username: "anna", password: "pw")
            Issue.record("expected an error")
        } catch let error as APIError {
            #expect(error.displayText == "Servertext.")
            for text in [error.displayText, String(describing: error), String(reflecting: error)] {
                #expect(!text.contains(Self.ticket))
                #expect(!text.contains("attestation-of"))
                #expect(!text.contains("key-id-1"))
                #expect(!text.contains(Self.nonce.dropLast()))
            }
        }
    }
}
