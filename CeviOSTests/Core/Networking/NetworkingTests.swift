import Foundation
import Synchronization
import Testing
@testable import CeviOS

struct CookieTests {
    private func response(_ setCookie: String) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.example.org/api/auth/get-session")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Set-Cookie": setCookie]
        )!
    }

    @Test func storesNameAndValueWithoutAttributes() {
        let result = CookieJar.updated([:], from: response("__Secure-better-auth.session_token=abc.def%3D; Max-Age=7776000; Path=/; HttpOnly; Secure; SameSite=Lax"))
        #expect(result == ["__Secure-better-auth.session_token": "abc.def%3D"])
    }

    @Test func storesMultipleCookies() {
        let result = CookieJar.updated([:], from: response("a=1; Path=/, b=2; Path=/"))
        #expect(result == ["a": "1", "b": "2"])
    }

    @Test func newCookieReplacesTheOldOne() {
        let result = CookieJar.updated(["a": "old", "b": "2"], from: response("a=new; Path=/"))
        #expect(result == ["a": "new", "b": "2"])
    }

    @Test func maxAgeZeroDeletes() {
        let result = CookieJar.updated(["a": "1", "b": "2"], from: response("a=; Max-Age=0; Path=/"))
        #expect(result == ["b": "2"])
    }

    @Test func expiredCookieDeletes() {
        let result = CookieJar.updated(["a": "1"], from: response("a=x; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Path=/"))
        #expect(result.isEmpty)
    }

    @Test func responseWithoutSetCookieLeavesEverythingUnchanged() {
        let response = HTTPURLResponse(url: URL(string: "https://api.example.org/")!, statusCode: 200, httpVersion: nil, headerFields: [:])!
        #expect(CookieJar.updated(["a": "1"], from: response) == ["a": "1"])
    }

    @Test func headerSeparatesPairsWithSemicolonAndSpace() {
        #expect(CookieJar.header(["b": "2", "a": "1"]) == "a=1; b=2")
        #expect(CookieJar.header([:]) == nil)
    }

    @Test func firstLaunchDeletesOldEntriesOnlyOnce() throws {
        let defaults = try #require(UserDefaults(suiteName: "test.\(UUID().uuidString)"))
        let cookieStore = InMemoryCookieStore(["a": "1"])
        FirstLaunchCleanup.run(cookieStore: cookieStore, defaults: defaults)
        #expect(cookieStore.read().isEmpty)

        cookieStore.write(["a": "2"])
        FirstLaunchCleanup.run(cookieStore: cookieStore, defaults: defaults)
        #expect(cookieStore.read() == ["a": "2"])
    }
}

struct APIErrorTests {
    private func body(_ code: String, _ message: String) -> Data {
        Data(#"{"code":"\#(code)","message":"\#(message)"}"#.utf8)
    }

    @Test(arguments: [
        (400, APIError.Kind.invalidInput), (401, .unauthorized), (403, .forbidden), (404, .notFound),
        (409, .conflict), (413, .payloadTooLarge), (415, .unsupportedMediaType), (426, .appOutdated), (429, .rateLimited),
        (500, .server), (503, .server),
    ])
    func statusMapsToKind(status: Int, kind: APIError.Kind) {
        #expect(APIError.from(status: status, data: Data()).kind == kind)
    }

    @Test func errorBodyIsRead() {
        let error = APIError.from(status: 401, data: body("ANMELDUNG_FEHLGESCHLAGEN", "Anmeldung nicht möglich."))
        #expect(error.code == "ANMELDUNG_FEHLGESCHLAGEN")
        #expect(error.displayText == "Anmeldung nicht möglich.")
    }

    @Test func unreadableBodyYieldsGenericText() {
        let error = APIError.from(status: 500, data: Data("<html>".utf8))
        #expect(error.code == nil)
        #expect(!error.displayText.isEmpty)
    }

    @Test func rateLimitedAlwaysShowsPleaseWait() {
        let error = APIError.from(status: 429, data: body("ZU_VIELE_ANFRAGEN", "Too many requests"))
        #expect(error.displayText == "Bitte kurz warten.")
    }
}

struct DateFormatsTests {
    @Test func timestampWithAndWithoutFractionalSeconds() {
        let without = DateFormats.timestamp("2026-11-07T14:00:00Z")
        let with = DateFormats.timestamp("2026-11-07T14:00:00.000Z")
        #expect(without == Date(timeIntervalSince1970: 1_794_060_000))
        #expect(with == without)
    }

    @Test func calendarDayIsMidnightInZurich() throws {
        let day = try #require(DateFormats.calendarDay("2026-07-01"))
        // Daylight saving time: midnight in Zurich is 22:00 UTC the day before.
        #expect(day == DateFormats.timestamp("2026-06-30T22:00:00Z"))
        #expect(DateFormats.calendarDayText(day) == "2026-07-01")
    }

    @Test(arguments: ["2026-02-30", "2026-13-01", "26-01-01", "heute", ""])
    func invalidCalendarDaysYieldNil(text: String) {
        #expect(DateFormats.calendarDay(text) == nil)
    }

    @Test func decoderReadsTimestampAndCalendarDay() throws {
        struct Entry: Decodable { let start: Date; let day: Date }
        let json = Data(#"{"start":"2026-11-07T14:00:00.000Z","day":"2026-11-07"}"#.utf8)
        let entry = try JSONDecoder.api.decode(Entry.self, from: json)
        #expect(DateFormats.calendarDayText(entry.day) == "2026-11-07")
        #expect(entry.start == DateFormats.timestamp("2026-11-07T14:00:00Z"))
    }
}

struct PageSequenceTests {
    @Test func olderPagesAreAppendedUntilTheEnd() {
        var sequence = PageSequence<Int>()
        #expect(!sequence.isAtEnd)
        sequence.append([5, 4, 3], next: "id-3")
        #expect(sequence.items == [5, 4, 3])
        #expect(sequence.next == "id-3")
        #expect(!sequence.isAtEnd)

        sequence.append([2, 1], next: nil)
        #expect(sequence.items == [5, 4, 3, 2, 1])
        #expect(sequence.next == nil)
        #expect(sequence.isAtEnd)
    }
}

struct APIClientTests {
    private nonisolated struct Payload: Decodable, Sendable { let value: Int }

    private func client(
        host: String,
        cookies: [String: String] = [:],
        events: EventCollector? = nil,
        reply: @escaping StubProtocol.Reply
    ) -> (APIClient, InMemoryCookieStore) {
        StubProtocol.register(host: host, reply: reply)
        let cookieStore = InMemoryCookieStore(cookies)
        let client = APIClient(
            baseURL: URL(string: "https://\(host)")!,
            appVersion: "1.2.3",
            cookieStore: cookieStore,
            session: APIClient.makeSession(protocolClasses: [StubProtocol.self])
        ) { event in events?.add(event) }
        return (client, cookieStore)
    }

    private func host() -> String { "a\(UUID().uuidString.prefix(8).lowercased()).test.example.org" }

    @Test func sendsVersionAndCookieButNoOriginOnGet() async throws {
        let host = host()
        let (client, _) = client(host: host, cookies: ["s": "1", "t": "2"]) { _ in (200, [:], Data(#"{"value":7}"#.utf8)) }
        let response: Payload = try await client.load("GET", "/api/v1/ich")
        #expect(response.value == 7)

        let request = try #require(StubProtocol.requests(host: host).first)
        #expect(request.value(forHTTPHeaderField: "X-App-Version") == "1.2.3")
        #expect(request.value(forHTTPHeaderField: "Cookie") == "s=1; t=2")
        #expect(request.value(forHTTPHeaderField: "Origin") == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func postToAuthSendsOrigin() async throws {
        let host = host()
        let (client, _) = client(host: host) { _ in (200, [:], Data("{}".utf8)) }
        try await client.send("POST", "/api/auth/sign-out", body: [String: String]())
        let request = try #require(StubProtocol.requests(host: host).first)
        #expect(request.value(forHTTPHeaderField: "Origin") == "cevi-os://")
    }

    @Test func setCookieIsStoredAndReplacesTheOldOne() async throws {
        let host = host()
        let (client, cookieStore) = client(host: host, cookies: ["s": "old"]) { _ in
            (200, ["Set-Cookie": "s=new; Path=/; Max-Age=7776000"], Data("{}".utf8))
        }
        try await client.send("GET", "/api/auth/get-session")
        #expect(cookieStore.read() == ["s": "new"])
    }

    @Test func unauthorizedUnderV1DeletesCookiesAndReportsEvent() async throws {
        let host = host()
        let events = EventCollector()
        let (client, cookieStore) = client(host: host, cookies: ["s": "1"], events: events) { _ in
            (401, [:], Data(#"{"code":"NICHT_ANGEMELDET","message":"Nicht angemeldet"}"#.utf8))
        }
        await #expect(throws: APIError.self) { try await client.send("GET", "/api/v1/ich") }
        #expect(cookieStore.read().isEmpty)
        #expect(await !client.hasCookies)
        #expect(events.all.count == 1)
    }

    @Test func unauthorizedUnderAuthKeepsTheIntermediateCookie() async throws {
        let host = host()
        let (client, cookieStore) = client(host: host, cookies: ["two_factor": "x"]) { _ in
            (401, [:], Data(#"{"code":"INVALID_CODE","message":"Invalid code"}"#.utf8))
        }
        await #expect(throws: APIError.self) { try await client.send("POST", "/api/auth/two-factor/verify-totp", body: ["code": "000000"]) }
        #expect(cookieStore.read() == ["two_factor": "x"])
    }

    @Test func status426ReportsAppOutdated() async throws {
        let host = host()
        let events = EventCollector()
        let (client, _) = client(host: host, events: events) { _ in
            (426, [:], Data(#"{"code":"APP_VERALTET","message":"Bitte aktualisieren"}"#.utf8))
        }
        do {
            try await client.send("GET", "/api/v1/ich")
            Issue.record("Expected error")
        } catch let error as APIError {
            #expect(error.kind == .appOutdated)
        }
        let reported = events.all
        #expect(reported.count == 1)
        guard case .appOutdated = reported.first else { Issue.record("Expected appOutdated event"); return }
    }

    @Test func rateLimitedIsNotRetried() async throws {
        let host = host()
        let (client, _) = client(host: host) { _ in (429, ["X-Retry-After": "30"], Data(#"{"code":"ZU_VIELE_ANFRAGEN","message":"x"}"#.utf8)) }
        do {
            try await client.send("GET", "/api/v1/chats")
            Issue.record("Expected error")
        } catch let error as APIError {
            #expect(error.kind == .rateLimited)
        }
        #expect(StubProtocol.requests(host: host).count == 1)
    }

    @Test func missingConnectionBecomesNetworkError() async throws {
        // A host without a registered reply fails in the stub.
        let other = APIClient(
            baseURL: URL(string: "https://\(host())")!, appVersion: "1.0.0", cookieStore: InMemoryCookieStore(),
            session: APIClient.makeSession(protocolClasses: [StubProtocol.self])
        )
        do {
            try await other.send("GET", "/api/v1/ich")
            Issue.record("Expected error")
        } catch let error as APIError {
            #expect(error.kind == .network)
        }
    }

    @Test func versionWithoutThreeNumbersBecomesZeroZeroZero() {
        #expect(APIClient.appVersion(from: ["CFBundleShortVersionString": "1.2.3"]) == "1.2.3")
        #expect(APIClient.appVersion(from: ["CFBundleShortVersionString": "1.2"]) == "0.0.0")
        #expect(APIClient.appVersion(from: [:]) == "0.0.0")
    }
}

struct RedirectTests {
    /// Asks the delegate about a redirect from `https://api.example.org/…` to `target`; the returned request, if it is followed.
    private func followed(_ target: String) -> URLRequest? {
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: URLRequest(url: URL(string: "https://api.example.org/api/v1/ich")!))
        let response = HTTPURLResponse(url: task.originalRequest!.url!, statusCode: 302, httpVersion: nil, headerFields: nil)!
        var result: URLRequest?
        SameOriginRedirects().urlSession(session, task: task, willPerformHTTPRedirection: response,
                                         newRequest: URLRequest(url: URL(string: target)!)) { result = $0 }
        return result
    }

    @Test func sameOriginIsFollowed() {
        #expect(followed("https://api.example.org/api/v1/ich/") != nil)
    }

    @Test(arguments: ["https://evil.example/x", "http://api.example.org/x", "https://api.example.org:8443/x"])
    func otherOriginsAreRefused(_ target: String) {
        #expect(followed(target) == nil)
    }
}
