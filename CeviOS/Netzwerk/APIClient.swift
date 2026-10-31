import Foundation

/// Ereignisse, auf die die ganze App reagieren muss.
nonisolated enum APIEreignis: Sendable {
    /// 401 unter `/api/v1`: Die Sitzung ist beendet, das Cookie ist gelöscht.
    case sitzungBeendet
    /// 426: Die App ist älter als der Mindeststand des Servers.
    case appVeraltet
}

/// Client für `/api/auth/*` und `/api/v1/*`. Die Sitzung hängt nur am Cookie im Speicher (Keychain); es gibt weder
/// Cookie-Verwaltung durch URLSession noch Bearer-Token. Schreibt nichts ins Log.
actor APIClient {
    static let herkunft = "cevi-os://"

    private let basisURL: URL
    private let appVersion: String
    private let speicher: any CookieSpeicher
    private let session: URLSession
    private let beiEreignis: @Sendable (APIEreignis) -> Void
    private var cookies: [String: String]

    init(
        basisURL: URL,
        appVersion: String,
        speicher: any CookieSpeicher,
        session: URLSession = APIClient.neueSession(),
        beiEreignis: @escaping @Sendable (APIEreignis) -> Void = { _ in }
    ) {
        self.basisURL = basisURL
        self.appVersion = appVersion
        self.speicher = speicher
        self.session = session
        self.beiEreignis = beiEreignis
        cookies = speicher.lesen()
    }

    /// Session ohne Cookie-Verwaltung und ohne Zwischenspeicher: Antworten wie `no-store`-Kontakte oder Kinderdaten
    /// landen nie auf dem Gerät.
    nonisolated static func neueSession(protokolle: [AnyClass]? = nil) -> URLSession {
        let konfiguration = URLSessionConfiguration.ephemeral
        konfiguration.httpShouldSetCookies = false
        konfiguration.httpCookieStorage = nil
        konfiguration.httpCookieAcceptPolicy = .never
        konfiguration.urlCache = nil
        konfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        konfiguration.timeoutIntervalForRequest = 30
        if let protokolle { konfiguration.protocolClasses = protokolle }
        return URLSession(configuration: konfiguration)
    }

    /// Wert für `X-App-Version`. Eine Version, die nicht `x.y.z` ist, gilt für den Server als zu alt; dann `0.0.0`.
    nonisolated static func appVersion(aus info: [String: Any]) -> String {
        let version = info["CFBundleShortVersionString"] as? String ?? ""
        return version.wholeMatch(of: /\d+\.\d+\.\d+/) != nil ? version : "0.0.0"
    }

    var hatCookies: Bool { !cookies.isEmpty }

    /// Verwirft die lokale Sitzung (nach Abmelden oder 401).
    func cookiesLoeschen() {
        cookies = [:]
        speicher.loeschen()
    }

    /// Sendet eine Anfrage und liefert den Körper der 2xx-Antwort. Andere Antworten werfen einen `APIFehler`.
    @discardableResult
    func senden(
        _ methode: String,
        _ pfad: String,
        query: [URLQueryItem] = [],
        koerper: (any Encodable & Sendable)? = nil
    ) async throws -> Data {
        var komponenten = URLComponents(url: basisURL, resolvingAgainstBaseURL: false)
        komponenten?.path = pfad
        komponenten?.queryItems = query.isEmpty ? nil : query
        guard let url = komponenten?.url else { throw APIFehler.netzwerk }

        var anfrage = URLRequest(url: url)
        anfrage.httpMethod = methode
        anfrage.httpShouldHandleCookies = false
        anfrage.setValue(appVersion, forHTTPHeaderField: "X-App-Version")
        if methode == "POST", pfad.hasPrefix("/api/auth/") {
            anfrage.setValue(Self.herkunft, forHTTPHeaderField: "Origin")
        }
        if let kopfzeile = Cookies.kopfzeile(cookies) {
            anfrage.setValue(kopfzeile, forHTTPHeaderField: "Cookie")
        }
        if let koerper {
            anfrage.setValue("application/json", forHTTPHeaderField: "Content-Type")
            anfrage.httpBody = try JSONEncoder.api.encode(koerper)
        }

        let daten: Data
        let antwort: HTTPURLResponse
        do {
            let (d, a) = try await session.data(for: anfrage)
            guard let http = a as? HTTPURLResponse else { throw APIFehler.netzwerk }
            (daten, antwort) = (d, http)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw APIFehler.netzwerk
        }

        let neu = Cookies.aktualisiert(cookies, aus: antwort)
        if neu != cookies {
            cookies = neu
            speicher.schreiben(neu)
        }

        guard !(200..<300).contains(antwort.statusCode) else { return daten }
        let fehler = APIFehler.aus(status: antwort.statusCode, daten: daten)
        switch fehler.art {
        case .nichtAngemeldet where pfad.hasPrefix("/api/v1/"):
            // Unter /api/auth ist 401 auch ein falscher Code oder ein falsches Passwort, nicht das Ende der Sitzung.
            cookiesLoeschen()
            beiEreignis(.sitzungBeendet)
        case .appVeraltet:
            beiEreignis(.appVeraltet)
        default:
            break
        }
        throw fehler
    }

    /// Wie `senden`, mit dekodierter Antwort.
    func laden<T: Decodable & Sendable>(
        _ methode: String = "GET",
        _ pfad: String,
        query: [URLQueryItem] = [],
        koerper: (any Encodable & Sendable)? = nil
    ) async throws -> T {
        let daten = try await senden(methode, pfad, query: query, koerper: koerper)
        do {
            return try JSONDecoder.api.decode(T.self, from: daten)
        } catch {
            throw APIFehler(art: .server, status: nil, code: nil, meldung: nil)
        }
    }
}
