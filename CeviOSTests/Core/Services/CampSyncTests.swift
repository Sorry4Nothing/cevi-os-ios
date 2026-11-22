import Foundation
import Synchronization
import Testing
@testable import CeviOS

private let camp = UUID()
private var campPath: String { "/api/v1/lager/\(camp.uuidString.lowercased())" }

private func makeClient(host: String) -> APIClient {
    let session = APIClient.makeSession(protocolClasses: [StubProtocol.self])
    return APIClient(
        baseURL: URL(string: "https://\(host)")!, appVersion: "1.0.0", cookieStore: InMemoryCookieStore(["s": "1"]),
        session: session, streamSession: APIClient.makeSession(protocolClasses: [StubProtocol.self], streaming: true)
    )
}

private func newHost() -> String { "a\(UUID().uuidString.prefix(8).lowercased()).test.example.org" }

private func events(_ text: String, chunk: Int = .max) -> [CampServerEvent] {
    var parser = CampEventParser()
    let bytes = Array(text.utf8)
    return stride(from: 0, to: bytes.count, by: chunk).flatMap { parser.consume(bytes[$0 ..< min($0 + chunk, bytes.count)]) }
}

struct CampEventParserTests {
    private let example = "retry: 5000\nid: 42\nevent: bereit\ndata: {\"bis\":42}\n\n: herzschlag\n\nid: 43\nevent: aenderung\ndata: {\"bis\":43,\"objekttypen\":[\"aufgabe\"]}\n\n"

    @Test func parsesTheExampleOfTheDescription() {
        let result = events(example)
        #expect(result == [
            CampServerEvent(id: 42, name: "bereit", data: #"{"bis":42}"#),
            CampServerEvent(id: 43, name: "aenderung", data: #"{"bis":43,"objekttypen":["aufgabe"]}"#),
        ])
    }

    @Test func chunkingDoesNotChangeTheResult() {
        for size in [1, 2, 3, 7] { #expect(events(example, chunk: size) == events(example)) }
    }

    @Test func joinsDataLinesAndAcceptsCRLF() {
        #expect(events("event: x\r\ndata: a\r\ndata: b\r\n\r\n") == [CampServerEvent(id: nil, name: "x", data: "a\nb")])
        #expect(events("data: a\rdata:b\r\r") == [CampServerEvent(id: nil, name: "message", data: "a\nb")])
    }

    @Test func messageWithoutDataAndOpenMessageAreNotDelivered() {
        #expect(events("event: x\n\n").isEmpty)
        #expect(events("event: x\ndata: a\n").isEmpty)
    }

    @Test func splitMultibyteCharacterSurvives() {
        #expect(events("data: Zürich\n\n", chunk: 1).first?.data == "Zürich")
    }

    @Test func liveEventsDecodeAndTolerateUnknown() throws {
        func live(_ name: String, _ data: String) -> CampLiveEvent? { CampLiveEvent(CampServerEvent(id: nil, name: name, data: data)) }
        #expect(live("bereit", #"{"bis":7}"#) == .ready(upTo: 7))
        #expect(live("aenderung", #"{"bis":8,"objekttypen":["aufgabe","pinnwand"]}"#) == .changed(upTo: 8, objectTypes: ["aufgabe", "pinnwand"]))
        #expect(live("neu-laden", #"{"bis":3}"#) == .reload(upTo: 3))
        #expect(live("ende", #"{"grund":"neu-verbinden"}"#) == .end)
        #expect(live("zukunft", "{}") == .unknown("zukunft"))
        #expect(live("aenderung", "kaputt") == nil)
        #expect(CampLiveEvent.changed(upTo: 8, objectTypes: []).upTo == 8 && CampLiveEvent.end.upTo == nil)
    }
}

struct CampSyncServiceTests {
    private let sampleResponse = #"{"ergebnisse":[{"clientOpId":"0190a000-0000-7000-8000-000000000001","status":"ok","ergebnis":{"id":"x","version":4}},{"clientOpId":"0190a000-0000-7000-8000-000000000002","status":"konflikt","code":"VERSION_KONFLIKT","message":"m","aktuell":{"version":5,"titel":"A"},"abweichend":["titel"]},{"clientOpId":"0190a000-0000-7000-8000-000000000003","status":"abgelehnt","code":"KEINE_BERECHTIGUNG","message":"m"}]}"#

    @Test func responseDecodesAllThreeStates() throws {
        let response = try JSONDecoder.api.decode(CampOperationResponse.self, from: Data(sampleResponse.utf8))
        #expect(response.results.map(\.status) == [.ok, .conflict, .rejected])
        #expect(response.results[0].result?["version"] == .int(4))
        #expect(response.results[1].current?["titel"] == .string("A") && response.results[1].differing == ["titel"] && response.results[1].code == CampRules.versionConflictCode)
        #expect(response.results[2].code == "KEINE_BERECHTIGUNG" && CampRules.rejectionCodes.contains("KEINE_BERECHTIGUNG"))
    }

    @Test func sendsTheBatchWithLowercaseOpIds() async throws {
        let host = newHost()
        StubProtocol.register(host: host) { _ in (200, [:], Data(#"{"ergebnisse":[]}"#.utf8)) }
        let op = CampOperation(type: "aufgabe.aendern", payload: ["version": .int(2), "titel": .string("Neu"), "frist": .null])
        _ = try await makeClient(host: host).sendCampOperations(campId: camp, [op])
        let request = try #require(StubProtocol.requests(host: host).first)
        #expect(request.httpMethod == "POST" && request.url?.path == campPath + "/aenderungen")
        let body = try #require(StubProtocol.body(of: request).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        let first = try #require((body["operationen"] as? [[String: Any]])?.first)
        #expect(first["clientOpId"] as? String == op.clientOpId.uuidString.lowercased() && first["typ"] as? String == "aufgabe.aendern")
        let payload = try #require(first["nutzlast"] as? [String: Any])
        #expect(payload["titel"] as? String == "Neu" && payload["version"] as? Int == 2 && payload["frist"] is NSNull)
    }

    @Test func conflictChoicesPrepareTheFollowUp() {
        let op = CampOperation(type: "aufgabe.aendern", payload: ["version": .int(2), "titel": .string("Meine")])
        let current: [String: CampJSON] = ["version": .int(5), "titel": .string("Andere")]
        let mine = op.resolved(.keepMine, current: current)
        #expect(mine?.payload["version"] == .int(5) && mine?.payload["titel"] == .string("Meine") && mine?.clientOpId != op.clientOpId && mine?.type == op.type)
        let merged = op.resolved(.merge(["titel": .string("Beide")]), current: current)
        #expect(merged?.payload == ["titel": .string("Beide"), "version": .int(5)])
        #expect(op.resolved(.keepCurrent, current: current) == nil)
        #expect(op.resolved(.keepMine, current: ["titel": .string("x")]) == nil)
    }

    @Test func streamSendsLastEventIdAndEndsAfterEnde() async throws {
        let host = newHost()
        let text = "id: 5\nevent: bereit\ndata: {\"bis\":5}\n\n: herzschlag\n\nid: 6\nevent: aenderung\ndata: {\"bis\":6,\"objekttypen\":[\"aufgabe\"]}\n\nevent: ende\ndata: {\"grund\":\"neu-verbinden\"}\n\nid: 9\nevent: aenderung\ndata: {\"bis\":9}\n\n"
        StubProtocol.register(host: host) { _ in (200, ["Content-Type": "text/event-stream"], Data(text.utf8)) }
        var received: [CampLiveEvent] = []
        for try await event in makeClient(host: host).campEvents(campId: camp, lastEventId: 4) { received.append(event) }
        #expect(received == [.ready(upTo: 5), .changed(upTo: 6, objectTypes: ["aufgabe"]), .end])
        let request = try #require(StubProtocol.requests(host: host).first)
        #expect(request.httpMethod == "GET" && request.url?.path == campPath + "/ereignisse")
        #expect(request.value(forHTTPHeaderField: "Last-Event-ID") == "4" && request.value(forHTTPHeaderField: "Accept") == "text/event-stream")
        #expect(request.value(forHTTPHeaderField: "Cookie") == "s=1" && request.value(forHTTPHeaderField: "X-App-Version") == "1.0.0")
    }

    @Test func streamWithoutLastEventIdSendsNoHeader() async throws {
        let host = newHost()
        StubProtocol.register(host: host) { _ in (200, [:], Data()) }
        for try await _ in makeClient(host: host).campEvents(campId: camp) {}
        #expect(StubProtocol.requests(host: host).first?.value(forHTTPHeaderField: "Last-Event-ID") == nil)
    }

    @Test func streamRefusalThrowsTheApiError() async throws {
        let host = newHost()
        StubProtocol.register(host: host) { _ in (429, ["Retry-After": "30"], Data(#"{"code":"ZU_VIELE_VERBINDUNGEN","message":"m"}"#.utf8)) }
        do {
            for try await _ in makeClient(host: host).campEvents(campId: camp) {}
            Issue.record("expected an error")
        } catch let error as APIError {
            #expect(error.kind == .rateLimited && error.code == CampRules.tooManyConnectionsCode && error.retryAfter == 30)
        }
    }

    @Test func streamSessionKeepsTheProtectionSettings() {
        let configuration = APIClient.makeSession(streaming: true).configuration
        #expect(configuration.httpCookieStorage == nil && configuration.urlCache == nil && configuration.httpShouldSetCookies == false)
        #expect(configuration.timeoutIntervalForRequest > 30)
    }
}

/// Server stub that answers each operation by the `mode` in its payload and records every request.
private final class OutboxServer: Sendable {
    let host = newHost()

    /// `failFirst`: this many requests answer 500 before the server works.
    init(failFirst: Int = 0, status: Int = 200) {
        let failures = Mutex(failFirst)
        StubProtocol.register(host: host) { request in
            if status != 200 { return (status, [:], Data(#"{"code":"X","message":"m"}"#.utf8)) }
            if failures.withLock({ let f = $0 > 0; if f { $0 -= 1 }; return f }) { return (500, [:], Data()) }
            let body = StubProtocol.body(of: request).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let operations = (body?["operationen"] as? [[String: Any]]) ?? []
            let results: [[String: Any]] = operations.map { op in
                let id = op["clientOpId"] as? String ?? ""
                switch (op["nutzlast"] as? [String: Any])?["mode"] as? String {
                case "conflict": return ["clientOpId": id, "status": "konflikt", "code": "VERSION_KONFLIKT", "aktuell": ["version": 7], "abweichend": ["titel"]]
                case "reject": return ["clientOpId": id, "status": "abgelehnt", "code": "KEINE_BERECHTIGUNG"]
                case "skip": return ["clientOpId": id, "status": "ok"]
                default: return ["clientOpId": id, "status": "ok", "ergebnis": ["version": 2]]
                }
            }
            return (200, [:], (try? JSONSerialization.data(withJSONObject: ["ergebnisse": results])) ?? Data())
        }
    }

    var sentIds: [[String]] {
        StubProtocol.requests(host: host).map { request in
            let body = StubProtocol.body(of: request).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            return ((body?["operationen"] as? [[String: Any]]) ?? []).compactMap { $0["clientOpId"] as? String }
        }
    }
}

struct CampOutboxTests {
    private func op(_ mode: String = "ok") -> CampOperation {
        CampOperation(type: "aufgabe.aendern", payload: ["mode": .string(mode), "version": .int(1)])
    }

    @Test func offlineKeepsEntriesWaiting() async throws {
        let host = newHost() // no stub registered: the connection fails
        let outbox = CampOutbox(campId: camp, client: makeClient(host: host))
        await outbox.enqueue(op())
        await outbox.enqueue(op())
        await #expect(throws: APIError.self) { try await outbox.flush() }
        #expect(await outbox.waitingCount == 2)
        #expect(await outbox.all.allSatisfy { $0.state == .waiting })
    }

    @Test func serverErrorKeepsEntriesAndRetryIsIdempotent() async throws {
        let server = OutboxServer(failFirst: 1)
        let outbox = CampOutbox(campId: camp, client: makeClient(host: server.host))
        let operation = op()
        await outbox.enqueue(operation)
        await #expect(throws: APIError.self) { try await outbox.flush() }
        #expect(await outbox.waitingCount == 1)
        try await outbox.flush()
        let state = await outbox.all.first?.state
        #expect(await outbox.waitingCount == 0 && state == .sent)
        let ids = server.sentIds
        #expect(ids.count == 2 && ids[0] == ids[1] && ids[0] == [operation.clientOpId.uuidString.lowercased()])
        try await outbox.flush() // nothing waiting: no third request
        #expect(server.sentIds.count == 2)
    }

    @Test func partialSuccessResendsOnlyTheOpenOnes() async throws {
        let server = OutboxServer()
        let outbox = CampOutbox(campId: camp, client: makeClient(host: server.host))
        let done = op(), open = op("skip")
        await outbox.enqueue(done)
        await outbox.enqueue(open)
        // The server answers only for the first: simulate by an answer that omits the second entry.
        StubProtocol.register(host: server.host) { request in
            let body = StubProtocol.body(of: request).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let first = ((body?["operationen"] as? [[String: Any]]) ?? []).first?["clientOpId"] as? String ?? ""
            return (200, [:], Data(#"{"ergebnisse":[{"clientOpId":"\#(first)","status":"ok"}]}"#.utf8))
        }
        try await outbox.flush()
        #expect(await outbox.waitingCount == 1)
        #expect(await outbox.all.map(\.state) == [.sent, .waiting])
        try await outbox.flush()
        let ids = StubProtocol.requests(host: server.host).count
        #expect(ids >= 2)
        let last = server.sentIds.last
        #expect(last?.count == 1)
    }

    @Test func conflictAndRejectionStayVisibleUntilTheDecision() async throws {
        let server = OutboxServer()
        let outbox = CampOutbox(campId: camp, client: makeClient(host: server.host))
        let conflicting = op("conflict"), rejected = op("reject"), fine = op()
        for operation in [conflicting, rejected, fine] { await outbox.enqueue(operation) }
        try await outbox.flush()
        let entries = await outbox.all
        #expect(entries.map(\.state) == [.conflict, .rejected, .sent])
        #expect(entries[0].code == CampRules.versionConflictCode && entries[0].current?["version"] == .int(7) && entries[0].differing == ["titel"])
        #expect(entries[1].code == "KEINE_BERECHTIGUNG")
        #expect(await outbox.waitingCount == 0)

        await outbox.confirmRejected(conflicting.id) // not rejected: stays
        #expect(await outbox.all.count == 3)
        await outbox.confirmRejected(rejected.id)
        #expect(await outbox.all.count == 2)

        #expect(await outbox.resolve(conflicting.id, .keepMine))
        let after = await outbox.all
        #expect(after.map(\.state) == [.waiting, .sent])
        #expect(after[0].operation.payload["version"] == .int(7) && after[0].id != conflicting.id)
        #expect(await outbox.resolve(fine.id, .keepMine) == false)
        await outbox.clearSent()
        #expect(await outbox.all.count == 1)
        await outbox.discard(after[0].id)
        #expect(await outbox.all.isEmpty)
    }

    @Test func keepCurrentDropsTheConflictEntry() async throws {
        let server = OutboxServer()
        let outbox = CampOutbox(campId: camp, client: makeClient(host: server.host))
        let conflicting = op("conflict")
        await outbox.enqueue(conflicting)
        try await outbox.flush()
        #expect(await outbox.resolve(conflicting.id, .keepCurrent))
        #expect(await outbox.all.isEmpty)
    }

    @Test func refusalOfTheWholeRequestMarksRejected() async throws {
        for status in [403, 404, 409] {
            let server = OutboxServer(status: status)
            let outbox = CampOutbox(campId: camp, client: makeClient(host: server.host))
            await outbox.enqueue(op())
            try await outbox.flush()
            let entry = await outbox.all.first
            #expect(entry?.state == .rejected && entry?.code == "X", "status \(status)")
            #expect(await outbox.waitingCount == 0)
        }
    }

    @Test func rateLimitKeepsWaiting() async throws {
        let server = OutboxServer(status: 429)
        let outbox = CampOutbox(campId: camp, client: makeClient(host: server.host))
        await outbox.enqueue(op())
        await #expect(throws: APIError.self) { try await outbox.flush() }
        #expect(await outbox.waitingCount == 1)
    }

    @Test func sendsMoreThanOneHundredInBatches() async throws {
        let server = OutboxServer()
        let outbox = CampOutbox(campId: camp, client: makeClient(host: server.host))
        for _ in 0..<150 { await outbox.enqueue(op()) }
        try await outbox.flush()
        let waiting = await outbox.waitingCount
        #expect(server.sentIds.map(\.count) == [100, 50] && waiting == 0)
    }

    @Test func storeIsUsedAndRemoveAllClearsIt() async throws {
        let store = CampOutboxMemoryStore()
        let outbox = CampOutbox(campId: camp, client: makeClient(host: newHost()), store: store)
        await outbox.enqueue(op())
        #expect(await store.load().count == 1)
        let restarted = CampOutbox(campId: camp, client: makeClient(host: newHost()), store: store)
        await restarted.load()
        #expect(await restarted.waitingCount == 1)
        await restarted.removeAll()
        let stored = await store.load(), left = await restarted.all
        #expect(stored.isEmpty && left.isEmpty)
    }
}
