import Foundation

nonisolated enum AnmeldeErgebnis: Equatable, Sendable {
    case angemeldet
    /// Zweiter Faktor verlangt; das Zwischen-Cookie ist gespeichert.
    case zweiterFaktor
}

extension APIClient {
    /// `POST /api/auth/sign-in/username`. Alte Cookies werden vorher verworfen.
    func anmelden(benutzername: String, passwort: String) async throws -> AnmeldeErgebnis {
        cookiesLoeschen()
        let daten = try await senden(
            "POST", "/api/auth/sign-in/username",
            koerper: ["username": benutzername, "password": passwort]
        )
        return Self.anmeldeErgebnis(aus: daten)
    }

    nonisolated static func anmeldeErgebnis(aus daten: Data) -> AnmeldeErgebnis {
        struct Probe: Decodable { let twoFactorRedirect: Bool? }
        let probe = try? JSONDecoder().decode(Probe.self, from: daten)
        return probe?.twoFactorRedirect == true ? .zweiterFaktor : .angemeldet
    }

    /// `verify-totp` (6 Ziffern) oder `verify-backup-code` (`xxxxx-xxxxx`).
    func zweitenFaktorBestaetigen(code: String, ersatzcode: Bool) async throws {
        let pfad = ersatzcode ? "/api/auth/two-factor/verify-backup-code" : "/api/auth/two-factor/verify-totp"
        try await senden("POST", pfad, koerper: ["code": code])
    }

    /// `GET /api/auth/get-session`: verlängert die Sitzung. `false`, wenn der Server keine Sitzung kennt.
    func sitzungPruefen() async throws -> Bool {
        let daten = try await senden("GET", "/api/auth/get-session")
        return Self.sitzungVorhanden(in: daten)
    }

    nonisolated static func sitzungVorhanden(in daten: Data) -> Bool {
        let text = String(decoding: daten, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.isEmpty && text != "null"
    }

    func profilLaden() async throws -> Profil {
        try await laden("GET", "/api/v1/ich")
    }

    func passwortAendern(aktuell: String, neu: String) async throws {
        try await senden("POST", "/api/auth/change-password", koerper: ["currentPassword": aktuell, "newPassword": neu])
    }

    func datenschutzBestaetigen() async throws {
        try await senden("POST", "/api/v1/ich/datenschutz")
    }

    /// Beendet die Sitzung auf dem Server (Fehler sind egal, z. B. offline) und verwirft das Cookie.
    func abmelden(ueberall: Bool = false) async {
        _ = try? await senden("POST", ueberall ? "/api/auth/revoke-sessions" : "/api/auth/sign-out", koerper: [String: String]())
        cookiesLoeschen()
    }
}

/// Texte für Fehler der Anmeldung. Codes von better-auth (englische Grossbuchstaben) sind nicht zur Anzeige gedacht;
/// dafür steht hier ein deutscher Text. Alles andere zeigt den Text des Servers.
nonisolated enum AuthMeldungen {
    static func passwortAendern(_ fehler: APIFehler) -> String {
        switch fehler.code {
        case "PASSWORD_TOO_SHORT": String(localized: "Das neue Passwort muss mindestens 12 Zeichen haben.")
        case "PASSWORD_TOO_LONG": String(localized: "Das neue Passwort darf höchstens 128 Zeichen haben.")
        case "INVALID_PASSWORD": String(localized: "Das aktuelle Passwort stimmt nicht.")
        case "PASSWORD_COMPROMISED": String(localized: "Dieses Passwort stammt aus einem bekannten Datenleck. Bitte ein anderes wählen.")
        default: fehler.anzeigetext
        }
    }

    /// `neuAnmelden` ist wahr, wenn der Zwischenschritt ungültig ist und die Person von vorn beginnen muss.
    static func zweiterFaktor(_ fehler: APIFehler) -> (text: String, neuAnmelden: Bool) {
        switch fehler.code {
        case "INVALID_CODE", "INVALID_BACKUP_CODE":
            (String(localized: "Der Code stimmt nicht."), false)
        case "TOO_MANY_ATTEMPTS_REQUEST_NEW_CODE", "INVALID_TWO_FACTOR_COOKIE", "TOTP_NOT_ENABLED", "BACKUP_CODES_NOT_ENABLED":
            (String(localized: "Bitte noch einmal anmelden."), true)
        default:
            (fehler.anzeigetext, false)
        }
    }
}
