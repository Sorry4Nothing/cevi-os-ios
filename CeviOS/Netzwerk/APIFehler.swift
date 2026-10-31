import Foundation

/// Fehlerform des Servers: `{ "code": …, "message": … }`.
nonisolated struct FehlerKoerper: Decodable, Equatable, Sendable {
    let code: String
    let message: String
}

/// Fehler des API-Clients, aus Statuscode und Fehlerkörper abgebildet.
nonisolated struct APIFehler: Error, Equatable, Sendable {
    enum Art: Equatable, Sendable {
        case ungueltigeEingabe // 400
        case nichtAngemeldet // 401
        case keineBerechtigung // 403
        case nichtGefunden // 404
        case konflikt // 409
        case zuGross // 413
        case formatNichtUnterstuetzt // 415
        case appVeraltet // 426
        case zuVieleAnfragen // 429
        case server // 5xx und alles Übrige
        case netzwerk // keine Antwort
    }

    let art: Art
    let status: Int?
    /// Code des Servers, z. B. `NICHT_ANGEMELDET`. `nil` ohne lesbaren Fehlerkörper.
    let code: String?
    /// Text des Servers. Bei Codes von better-auth (englisch) nicht zur Anzeige gedacht.
    let meldung: String?

    static func aus(status: Int, daten: Data) -> APIFehler {
        let koerper = try? JSONDecoder().decode(FehlerKoerper.self, from: daten)
        let art: Art = switch status {
        case 400: .ungueltigeEingabe
        case 401: .nichtAngemeldet
        case 403: .keineBerechtigung
        case 404: .nichtGefunden
        case 409: .konflikt
        case 413: .zuGross
        case 415: .formatNichtUnterstuetzt
        case 426: .appVeraltet
        case 429: .zuVieleAnfragen
        default: .server
        }
        return APIFehler(art: art, status: status, code: koerper?.code, meldung: koerper?.message)
    }

    static let netzwerk = APIFehler(art: .netzwerk, status: nil, code: nil, meldung: nil)

    /// Text für die Anzeige. Bei 429 immer «Bitte kurz warten.», sonst der Text des Servers, falls vorhanden.
    var anzeigetext: String {
        switch art {
        case .zuVieleAnfragen:
            String(localized: "Bitte kurz warten.")
        case .netzwerk:
            String(localized: "Keine Verbindung zum Server. Bitte später nochmals versuchen.")
        case .appVeraltet:
            String(localized: "Bitte die App aktualisieren.")
        default:
            meldung ?? String(localized: "Etwas ist schiefgegangen. Bitte später nochmals versuchen.")
        }
    }
}
