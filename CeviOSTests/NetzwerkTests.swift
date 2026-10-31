import Foundation
import Synchronization
import Testing
@testable import CeviOS

struct CookieTests {
    private func antwort(_ setCookie: String) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.example.org/api/auth/get-session")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Set-Cookie": setCookie]
        )!
    }

    @Test func speichertNameUndWertOhneAttribute() {
        let ergebnis = Cookies.aktualisiert([:], aus: antwort("__Secure-better-auth.session_token=abc.def%3D; Max-Age=7776000; Path=/; HttpOnly; Secure; SameSite=Lax"))
        #expect(ergebnis == ["__Secure-better-auth.session_token": "abc.def%3D"])
    }

    @Test func mehrereCookiesWerdenAllegespeichert() {
        let ergebnis = Cookies.aktualisiert([:], aus: antwort("a=1; Path=/, b=2; Path=/"))
        #expect(ergebnis == ["a": "1", "b": "2"])
    }

    @Test func neuesCookieErsetztDasAlte() {
        let ergebnis = Cookies.aktualisiert(["a": "alt", "b": "2"], aus: antwort("a=neu; Path=/"))
        #expect(ergebnis == ["a": "neu", "b": "2"])
    }

    @Test func maxAgeNullLoescht() {
        let ergebnis = Cookies.aktualisiert(["a": "1", "b": "2"], aus: antwort("a=; Max-Age=0; Path=/"))
        #expect(ergebnis == ["b": "2"])
    }

    @Test func abgelaufenesCookieLoescht() {
        let ergebnis = Cookies.aktualisiert(["a": "1"], aus: antwort("a=x; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Path=/"))
        #expect(ergebnis.isEmpty)
    }

    @Test func antwortOhneSetCookieLaesstAllesUnveraendert() {
        let antwort = HTTPURLResponse(url: URL(string: "https://api.example.org/")!, statusCode: 200, httpVersion: nil, headerFields: [:])!
        #expect(Cookies.aktualisiert(["a": "1"], aus: antwort) == ["a": "1"])
    }

    @Test func kopfzeileTrenntPaareMitStrichpunktUndLeerzeichen() {
        #expect(Cookies.kopfzeile(["b": "2", "a": "1"]) == "a=1; b=2")
        #expect(Cookies.kopfzeile([:]) == nil)
    }

    @Test func ersterStartLoeschtAlteEintraegeNurEinmal() throws {
        let defaults = try #require(UserDefaults(suiteName: "test.\(UUID().uuidString)"))
        let speicher = ArbeitsspeicherCookies(["a": "1"])
        ErststartBereinigung.ausfuehren(speicher: speicher, defaults: defaults)
        #expect(speicher.lesen().isEmpty)

        speicher.schreiben(["a": "2"])
        ErststartBereinigung.ausfuehren(speicher: speicher, defaults: defaults)
        #expect(speicher.lesen() == ["a": "2"])
    }
}

struct APIFehlerTests {
    private func koerper(_ code: String, _ message: String) -> Data {
        Data(#"{"code":"\#(code)","message":"\#(message)"}"#.utf8)
    }

    @Test(arguments: [
        (400, APIFehler.Art.ungueltigeEingabe), (401, .nichtAngemeldet), (403, .keineBerechtigung), (404, .nichtGefunden),
        (409, .konflikt), (413, .zuGross), (415, .formatNichtUnterstuetzt), (426, .appVeraltet), (429, .zuVieleAnfragen),
        (500, .server), (503, .server),
    ])
    func statusWirdAufArtAbgebildet(status: Int, art: APIFehler.Art) {
        #expect(APIFehler.aus(status: status, daten: Data()).art == art)
    }

    @Test func fehlerkoerperWirdGelesen() {
        let fehler = APIFehler.aus(status: 401, daten: koerper("ANMELDUNG_FEHLGESCHLAGEN", "Anmeldung nicht möglich."))
        #expect(fehler.code == "ANMELDUNG_FEHLGESCHLAGEN")
        #expect(fehler.anzeigetext == "Anmeldung nicht möglich.")
    }

    @Test func unlesbarerKoerperErgibtAllgemeinenText() {
        let fehler = APIFehler.aus(status: 500, daten: Data("<html>".utf8))
        #expect(fehler.code == nil)
        #expect(!fehler.anzeigetext.isEmpty)
    }

    @Test func zuVieleAnfragenZeigtImmerBitteKurzWarten() {
        let fehler = APIFehler.aus(status: 429, daten: koerper("ZU_VIELE_ANFRAGEN", "Too many requests"))
        #expect(fehler.anzeigetext == "Bitte kurz warten.")
    }
}

struct DatumsformateTests {
    @Test func zeitpunktMitUndOhneSekundenbruchteile() {
        let ohne = Datumsformate.zeitpunkt("2026-11-07T14:00:00Z")
        let mit = Datumsformate.zeitpunkt("2026-11-07T14:00:00.000Z")
        #expect(ohne == Date(timeIntervalSince1970: 1_794_060_000))
        #expect(mit == ohne)
    }

    @Test func kalendertagIstMitternachtInZuerich() throws {
        let tag = try #require(Datumsformate.kalendertag("2026-07-01"))
        // Sommerzeit: Mitternacht in Zürich ist 22:00 UTC am Vortag.
        #expect(tag == Datumsformate.zeitpunkt("2026-06-30T22:00:00Z"))
        #expect(Datumsformate.kalendertagText(tag) == "2026-07-01")
    }

    @Test(arguments: ["2026-02-30", "2026-13-01", "26-01-01", "heute", ""])
    func ungueltigeKalendertageErgebenNil(text: String) {
        #expect(Datumsformate.kalendertag(text) == nil)
    }

    @Test func decoderLiestZeitpunktUndKalendertag() throws {
        struct Eintrag: Decodable { let beginn: Date; let tag: Date }
        let json = Data(#"{"beginn":"2026-11-07T14:00:00.000Z","tag":"2026-11-07"}"#.utf8)
        let eintrag = try JSONDecoder.api.decode(Eintrag.self, from: json)
        #expect(Datumsformate.kalendertagText(eintrag.tag) == "2026-11-07")
        #expect(eintrag.beginn == Datumsformate.zeitpunkt("2026-11-07T14:00:00Z"))
    }
}

struct SeitenfolgeTests {
    @Test func aeltereSeitenWerdenAngehaengtBisZumEnde() {
        var folge = Seitenfolge<Int>()
        #expect(!folge.istAmEnde)
        folge.anhaengen([5, 4, 3], naechster: "id-3")
        #expect(folge.eintraege == [5, 4, 3])
        #expect(folge.naechster == "id-3")
        #expect(!folge.istAmEnde)

        folge.anhaengen([2, 1], naechster: nil)
        #expect(folge.eintraege == [5, 4, 3, 2, 1])
        #expect(folge.naechster == nil)
        #expect(folge.istAmEnde)
    }
}

struct APIClientTests {
    private nonisolated struct Antwort: Decodable, Sendable { let wert: Int }

    private func client(
        host: String,
        cookies: [String: String] = [:],
        ereignisse: EreignisSammler? = nil,
        antwort: @escaping StubProtokoll.Antwort
    ) -> (APIClient, ArbeitsspeicherCookies) {
        StubProtokoll.registrieren(host: host, antwort: antwort)
        let speicher = ArbeitsspeicherCookies(cookies)
        let client = APIClient(
            basisURL: URL(string: "https://\(host)")!,
            appVersion: "1.2.3",
            speicher: speicher,
            session: APIClient.neueSession(protokolle: [StubProtokoll.self])
        ) { ereignis in ereignisse?.hinzufuegen(ereignis) }
        return (client, speicher)
    }

    private func host() -> String { "a\(UUID().uuidString.prefix(8).lowercased()).test.example.org" }

    @Test func schicktVersionUndCookieAberKeineHerkunftBeiGet() async throws {
        let host = host()
        let (client, _) = client(host: host, cookies: ["s": "1", "t": "2"]) { _ in (200, [:], Data(#"{"wert":7}"#.utf8)) }
        let antwort: Antwort = try await client.laden("GET", "/api/v1/ich")
        #expect(antwort.wert == 7)

        let anfrage = try #require(StubProtokoll.anfragen(host: host).first)
        #expect(anfrage.value(forHTTPHeaderField: "X-App-Version") == "1.2.3")
        #expect(anfrage.value(forHTTPHeaderField: "Cookie") == "s=1; t=2")
        #expect(anfrage.value(forHTTPHeaderField: "Origin") == nil)
        #expect(anfrage.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func postAnAuthSchicktHerkunft() async throws {
        let host = host()
        let (client, _) = client(host: host) { _ in (200, [:], Data("{}".utf8)) }
        try await client.senden("POST", "/api/auth/sign-out", koerper: [String: String]())
        let anfrage = try #require(StubProtokoll.anfragen(host: host).first)
        #expect(anfrage.value(forHTTPHeaderField: "Origin") == "cevi-os://")
    }

    @Test func setCookieWirdGespeichertUndErsetztDasAlte() async throws {
        let host = host()
        let (client, speicher) = client(host: host, cookies: ["s": "alt"]) { _ in
            (200, ["Set-Cookie": "s=neu; Path=/; Max-Age=7776000"], Data("{}".utf8))
        }
        try await client.senden("GET", "/api/auth/get-session")
        #expect(speicher.lesen() == ["s": "neu"])
    }

    @Test func nichtAngemeldetUnterV1LoeschtCookiesUndMeldetEreignis() async throws {
        let host = host()
        let ereignisse = EreignisSammler()
        let (client, speicher) = client(host: host, cookies: ["s": "1"], ereignisse: ereignisse) { _ in
            (401, [:], Data(#"{"code":"NICHT_ANGEMELDET","message":"Nicht angemeldet"}"#.utf8))
        }
        await #expect(throws: APIFehler.self) { try await client.senden("GET", "/api/v1/ich") }
        #expect(speicher.lesen().isEmpty)
        #expect(await !client.hatCookies)
        #expect(ereignisse.alle.count == 1)
    }

    @Test func nichtAngemeldetUnterAuthBehaeltDasZwischenCookie() async throws {
        let host = host()
        let (client, speicher) = client(host: host, cookies: ["two_factor": "x"]) { _ in
            (401, [:], Data(#"{"code":"INVALID_CODE","message":"Invalid code"}"#.utf8))
        }
        await #expect(throws: APIFehler.self) { try await client.senden("POST", "/api/auth/two-factor/verify-totp", koerper: ["code": "000000"]) }
        #expect(speicher.lesen() == ["two_factor": "x"])
    }

    @Test func version426MeldetAppVeraltet() async throws {
        let host = host()
        let ereignisse = EreignisSammler()
        let (client, _) = client(host: host, ereignisse: ereignisse) { _ in
            (426, [:], Data(#"{"code":"APP_VERALTET","message":"Bitte aktualisieren"}"#.utf8))
        }
        do {
            try await client.senden("GET", "/api/v1/ich")
            Issue.record("Fehler erwartet")
        } catch let fehler as APIFehler {
            #expect(fehler.art == .appVeraltet)
        }
        let gemeldet = ereignisse.alle
        #expect(gemeldet.count == 1)
        guard case .appVeraltet = gemeldet.first else { Issue.record("Ereignis appVeraltet erwartet"); return }
    }

    @Test func zuVieleAnfragenWirdNichtWiederholt() async throws {
        let host = host()
        let (client, _) = client(host: host) { _ in (429, ["X-Retry-After": "30"], Data(#"{"code":"ZU_VIELE_ANFRAGEN","message":"x"}"#.utf8)) }
        do {
            try await client.senden("GET", "/api/v1/chats")
            Issue.record("Fehler erwartet")
        } catch let fehler as APIFehler {
            #expect(fehler.art == .zuVieleAnfragen)
        }
        #expect(StubProtokoll.anfragen(host: host).count == 1)
    }

    @Test func fehlendeVerbindungWirdZuNetzwerkfehler() async throws {
        // Ein Host ohne registrierte Antwort scheitert im Stub.
        let anderer = APIClient(
            basisURL: URL(string: "https://\(host())")!, appVersion: "1.0.0", speicher: ArbeitsspeicherCookies(),
            session: APIClient.neueSession(protokolle: [StubProtokoll.self])
        )
        do {
            try await anderer.senden("GET", "/api/v1/ich")
            Issue.record("Fehler erwartet")
        } catch let fehler as APIFehler {
            #expect(fehler.art == .netzwerk)
        }
    }

    @Test func versionOhneDreiZahlenWirdZuNullNullNull() {
        #expect(APIClient.appVersion(aus: ["CFBundleShortVersionString": "1.2.3"]) == "1.2.3")
        #expect(APIClient.appVersion(aus: ["CFBundleShortVersionString": "1.2"]) == "0.0.0")
        #expect(APIClient.appVersion(aus: [:]) == "0.0.0")
    }
}
