import Foundation

/// Events the whole app has to react to.
nonisolated enum APIEvent: Sendable {
    /// 401 under `/api/v1`: The session has ended, the cookie is deleted.
    case sessionEnded
    /// 426: The app is older than the minimum version of the server.
    case appOutdated
}

/// Client for `/api/auth/*` and `/api/v1/*`. The session hangs only on the cookie in the store (Keychain); there is neither
/// cookie handling by URLSession nor a bearer token. Writes nothing to the log.
actor APIClient {
    static let origin = "cevi-os://"

    private let baseURL: URL
    private let appVersion: String
    private let cookieStore: any CookieStore
    private let session: URLSession
    private let onEvent: @Sendable (APIEvent) -> Void
    private var cookies: [String: String]

    init(
        baseURL: URL,
        appVersion: String,
        cookieStore: any CookieStore,
        session: URLSession = APIClient.makeSession(),
        onEvent: @escaping @Sendable (APIEvent) -> Void = { _ in }
    ) {
        self.baseURL = baseURL
        self.appVersion = appVersion
        self.cookieStore = cookieStore
        self.session = session
        self.onEvent = onEvent
        cookies = cookieStore.read()
    }

    /// Session without cookie handling and without caching: responses such as `no-store` contacts or children's data
    /// never end up on the device.
    nonisolated static func makeSession(protocolClasses: [AnyClass]? = nil) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        if let protocolClasses { configuration.protocolClasses = protocolClasses }
        return URLSession(configuration: configuration)
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
        body: (any Encodable & Sendable)? = nil
    ) async throws -> Data {
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
        if let header = CookieJar.header(cookies) {
            request.setValue(header, forHTTPHeaderField: "Cookie")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder.api.encode(body)
        }

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

        let updated = CookieJar.updated(cookies, from: response)
        if updated != cookies {
            cookies = updated
            cookieStore.write(updated)
        }

        guard !(200..<300).contains(response.statusCode) else { return data }
        let error = APIError.from(status: response.statusCode, data: data)
        switch error.kind {
        case .unauthorized where path.hasPrefix("/api/v1/"):
            // Under /api/auth, 401 is also a wrong code or a wrong password, not the end of the session.
            clearCookies()
            onEvent(.sessionEnded)
        case .appOutdated:
            onEvent(.appOutdated)
        default:
            break
        }
        throw error
    }

    /// Like `send`, with a decoded response.
    func load<T: Decodable & Sendable>(
        _ method: String = "GET",
        _ path: String,
        query: [URLQueryItem] = [],
        body: (any Encodable & Sendable)? = nil
    ) async throws -> T {
        let data = try await send(method, path, query: query, body: body)
        do {
            return try JSONDecoder.api.decode(T.self, from: data)
        } catch {
            throw APIError(kind: .server, status: nil, code: nil, message: nil)
        }
    }
}
