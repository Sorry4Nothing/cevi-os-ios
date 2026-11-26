import Foundation
import Synchronization

/// Events the whole app has to react to.
nonisolated enum APIEvent: Sendable {
    /// 401 under `/api/v1`: The session has ended, the cookie is deleted.
    case sessionEnded
    /// 426: The app is older than the minimum version of the server.
    case appOutdated
    /// 403 under `/api/v1` (not `GET /ich`): possibly a pending password change.
    case mayNeedPasswordChange
}

/// Client for `/api/auth/*` and `/api/v1/*`. The session hangs only on the cookie in the store (Keychain); there is neither
/// cookie handling by URLSession nor a bearer token. Writes nothing to the log.
actor APIClient {
    static let origin = "cevi-os://"

    private let baseURL: URL
    private let appVersion: String
    private let cookieStore: any CookieStore
    private let session: URLSession
    private let streamSession: URLSession
    private let onEvent: @Sendable (APIEvent) -> Void
    let appAttest: AppAttestSetup?
    private var cookies: [String: String]
    /// Cache of the last loaded camp data (`APIClient+Cache.swift`); `nil` caches nothing.
    let campCache: (any CampCache)?
    /// Camps the server lists as open; only their data is written to the cache. `nil` until the list is loaded.
    var openCampIds: Set<UUID>?
    /// Files the person downloaded on purpose; they go with the camp (`APIClient+Cache.swift`).
    let campDownloads: (any CampDownloadStore)?
    /// Told after every camp read: when the answer came from the cache the date it was stored, else `nil`.
    nonisolated let cacheObserver = Mutex<(@MainActor @Sendable (Date?) -> Void)?>(nil)

    init(
        baseURL: URL,
        appVersion: String,
        cookieStore: any CookieStore,
        session: URLSession = APIClient.makeSession(),
        streamSession: URLSession = APIClient.makeSession(streaming: true),
        appAttest: AppAttestSetup? = nil,
        campCache: (any CampCache)? = nil,
        campDownloads: (any CampDownloadStore)? = nil,
        onEvent: @escaping @Sendable (APIEvent) -> Void = { _ in }
    ) {
        self.baseURL = baseURL
        self.appVersion = appVersion
        self.cookieStore = cookieStore
        self.session = session
        self.streamSession = streamSession
        self.onEvent = onEvent
        self.appAttest = appAttest
        self.campCache = campCache
        self.campDownloads = campDownloads
        cookies = cookieStore.read()
    }

    /// Session without cookie handling and without caching: responses such as `no-store` contacts or children's data
    /// never end up on the device.
    /// `streaming`: for the event stream. The idle limit is three heartbeats of the server (25 s) instead of 30 s for a whole
    /// request; everything else (no cookies, no cache, same-origin redirects) stays the same.
    nonisolated static func makeSession(protocolClasses: [AnyClass]? = nil, streaming: Bool = false) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = streaming ? 75 : 30
        if let protocolClasses { configuration.protocolClasses = protocolClasses }
        return URLSession(configuration: configuration, delegate: SameOriginRedirects(), delegateQueue: nil)
    }

    /// Value for `X-App-Version`. A version that is not `x.y.z` counts as too old for the server; then `0.0.0`.
    nonisolated static func appVersion(from info: [String: Any]) -> String {
        let version = info["CFBundleShortVersionString"] as? String ?? ""
        return version.wholeMatch(of: /\d+\.\d+\.\d+/) != nil ? version : "0.0.0"
    }

    var hasCookies: Bool { !cookies.isEmpty }

    /// Discards the local session (after sign-out or 401).
    func clearCookies() {
        cookies = [:]
        cookieStore.delete()
    }

    /// Sends a request and returns the body of the 2xx response. Other responses throw an `APIError`.
    @discardableResult
    func send(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        body: (any Encodable & Sendable)? = nil,
        rawBody: Data? = nil,
        headers: [String: String] = [:]
    ) async throws -> Data {
        let request = try makeRequest(method, path, query: query, body: body, rawBody: rawBody, headers: headers)

        let data: Data
        let response: HTTPURLResponse
        do {
            let (d, r) = try await session.data(for: request)
            guard let http = r as? HTTPURLResponse else { throw APIError.network }
            (data, response) = (d, http)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw APIError.network
        }

        absorbCookies(from: response)
        guard !(200..<300).contains(response.statusCode) else { return data }
        throw failure(response, data: data, path: path)
    }

    /// The request with the headers every call carries: version, session cookie, and for sign-in the origin.
    func makeRequest(
        _ method: String, _ path: String, query: [URLQueryItem] = [], body: (any Encodable & Sendable)? = nil, rawBody: Data? = nil,
        headers: [String: String] = [:]
    ) throws -> URLRequest {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = path
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else { throw APIError.network }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpShouldHandleCookies = false
        request.setValue(appVersion, forHTTPHeaderField: "X-App-Version")
        if method == "POST", path.hasPrefix("/api/auth/") {
            request.setValue(Self.origin, forHTTPHeaderField: "Origin")
        }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if let header = CookieJar.header(cookies) {
            request.setValue(header, forHTTPHeaderField: "Cookie")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder.api.encode(body)
        }
        if let rawBody {
            // The server derives the image type from the bytes, never from this header.
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            request.httpBody = rawBody
        }
        return request
    }

    /// Takes over a changed session cookie of a response.
    func absorbCookies(from response: HTTPURLResponse) {
        let updated = CookieJar.updated(cookies, from: response)
        if updated != cookies {
            cookies = updated
            cookieStore.write(updated)
        }
    }

    /// Maps a non-2xx response to an `APIError` and reports the app-wide events (401, 426, 403).
    func failure(_ response: HTTPURLResponse, data: Data, path: String) -> APIError {
        let retryAfter = (response.value(forHTTPHeaderField: "Retry-After") ?? response.value(forHTTPHeaderField: "X-Retry-After")).flatMap { Int($0) }
        let error = APIError.from(status: response.statusCode, data: data, retryAfter: retryAfter)
        switch error.kind {
        case .unauthorized where path.hasPrefix("/api/v1/") && !path.hasPrefix("/api/v1/app/"):
            // Under /api/auth, 401 is also a wrong code or a wrong password, not the end of the session. The same holds for
            // the app proof (`/api/v1/app/*`), which runs before there is a session.
            clearCookies()
            onEvent(.sessionEnded)
        case .appOutdated:
            onEvent(.appOutdated)
        case .forbidden where path.hasPrefix("/api/v1/") && path != "/api/v1/ich":
            // 403 can mean "password change still open": the app asks `GET /ich` and leads to the password page.
            onEvent(.mayNeedPasswordChange)
        default:
            break
        }
        return error
    }

    /// Opens a GET that stays open (`text/event-stream`) on the stream session. Throws the `APIError` of a non-2xx answer.
    func openStream(_ path: String, query: [URLQueryItem] = [], headers: [String: String] = [:]) async throws -> URLSession.AsyncBytes {
        var request = try makeRequest("GET", path, query: query)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let bytes: URLSession.AsyncBytes
        let response: HTTPURLResponse
        do {
            let (b, r) = try await streamSession.bytes(for: request)
            guard let http = r as? HTTPURLResponse else { throw APIError.network }
            (bytes, response) = (b, http)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw APIError.network
        }
        absorbCookies(from: response)
        guard !(200..<300).contains(response.statusCode) else { return bytes }
        var data = Data()
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count >= 65_536 { break }
            }
        } catch {}
        throw failure(response, data: data, path: path)
    }

    /// GET of a server-provided image path (`bildUrl`, `logoUrl`). Only `ImagePath` addresses on the own base URL,
    /// at most `ImagePath.maxBytes`.
    func image(path: String) async throws -> Data {
        guard ImagePath.isValid(path), let components = URLComponents(string: path) else { throw APIError.network }
        let data = try await send("GET", components.path, query: components.queryItems ?? [])
        guard data.count <= ImagePath.maxBytes else { throw APIError.network }
        return data
    }

    /// Like `send`, with a decoded response.
    func load<T: Decodable & Sendable>(
        _ method: String = "GET",
        _ path: String,
        query: [URLQueryItem] = [],
        body: (any Encodable & Sendable)? = nil
    ) async throws -> T {
        let data = method == "GET" ? try await sendCaching(path, query: query) : try await send(method, path, query: query, body: body)
        do {
            return try JSONDecoder.api.decode(T.self, from: data)
        } catch {
            throw APIError(kind: .server, status: nil, code: nil, message: nil)
        }
    }
}

/// Follows a redirect only within the same origin. The session cookie is set by hand as a header, so a redirect to another
/// host or to `http` must never carry it along (SR-40).
final class SameOriginRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        let from = task.originalRequest?.url
        let to = request.url
        let same = from?.scheme == to?.scheme && from?.host == to?.host && from?.port == to?.port
        completionHandler(same ? request : nil)
    }
}
