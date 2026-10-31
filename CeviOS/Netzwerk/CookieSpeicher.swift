import Foundation
import Security

/// Ablage der Cookies (`name=wert`, ohne Attribute). Produktiv der Keychain, in Tests der Arbeitsspeicher.
nonisolated protocol CookieSpeicher: Sendable {
    func lesen() -> [String: String]
    func schreiben(_ cookies: [String: String])
    func loeschen()
}

/// Reine Logik zu Cookies: aus `Set-Cookie` übernehmen und als `Cookie`-Kopfzeile ausgeben.
nonisolated enum Cookies {
    /// Übernimmt alle `Set-Cookie`-Header der Antwort. Ein neues Cookie ersetzt das alte, `Max-Age=0` (oder ein
    /// Ablauf in der Vergangenheit) löscht es.
    static func aktualisiert(_ bestehend: [String: String], aus antwort: HTTPURLResponse, jetzt: Date = .now) -> [String: String] {
        guard let url = antwort.url else { return bestehend }
        let felder = antwort.allHeaderFields.reduce(into: [String: String]()) { ergebnis, paar in
            if let name = paar.key as? String, let wert = paar.value as? String {
                ergebnis[name] = wert
            }
        }
        var ergebnis = bestehend
        for cookie in HTTPCookie.cookies(withResponseHeaderFields: felder, for: url) {
            let maxAlter = cookie.properties?[.maximumAge] as? String
            let abgelaufen = maxAlter.flatMap(Int.init).map { $0 <= 0 } ?? false
                || (cookie.expiresDate.map { $0 <= jetzt } ?? false)
            if abgelaufen {
                ergebnis[cookie.name] = nil
            } else {
                ergebnis[cookie.name] = cookie.value
            }
        }
        return ergebnis
    }

    /// Wert für den `Cookie`-Header, Paare mit `; ` getrennt. `nil` ohne Cookies.
    static func kopfzeile(_ cookies: [String: String]) -> String? {
        guard !cookies.isEmpty else { return nil }
        return cookies.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
    }
}

/// Speichert die Cookies als ein Eintrag im Keychain: nur nach Entsperren, nur dieses Gerät, ohne biometrischen Zwang.
nonisolated struct KeychainCookieSpeicher: CookieSpeicher {
    private let dienst: String
    private let konto = "cookies"

    init(dienst: String = (Bundle.main.bundleIdentifier ?? "ch.cevios") + ".sitzung") {
        self.dienst = dienst
    }

    private var abfrage: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: dienst,
            kSecAttrAccount as String: konto,
        ]
    }

    func lesen() -> [String: String] {
        var anfrage = abfrage
        anfrage[kSecReturnData as String] = true
        anfrage[kSecMatchLimit as String] = kSecMatchLimitOne
        var ergebnis: CFTypeRef?
        guard
            SecItemCopyMatching(anfrage as CFDictionary, &ergebnis) == errSecSuccess,
            let daten = ergebnis as? Data,
            let cookies = try? JSONDecoder().decode([String: String].self, from: daten)
        else {
            return [:]
        }
        return cookies
    }

    func schreiben(_ cookies: [String: String]) {
        guard !cookies.isEmpty else {
            loeschen()
            return
        }
        guard let daten = try? JSONEncoder().encode(cookies) else { return }
        let status = SecItemUpdate(abfrage as CFDictionary, [kSecValueData as String: daten] as CFDictionary)
        if status == errSecItemNotFound {
            var neu = abfrage
            neu[kSecValueData as String] = daten
            neu[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            SecItemAdd(neu as CFDictionary, nil)
        }
    }

    func loeschen() {
        SecItemDelete(abfrage as CFDictionary)
    }
}

/// iOS behält Keychain-Einträge nach einer Deinstallation. Beim ersten Start nach einer Installation löschen wir sie.
nonisolated enum ErststartBereinigung {
    static let schluessel = "installationBereinigt"

    static func ausfuehren(speicher: some CookieSpeicher, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: schluessel) else { return }
        speicher.loeschen()
        defaults.set(true, forKey: schluessel)
    }
}
