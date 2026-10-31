import Foundation
import Observation

/// Zustand der ganzen App: Verbindung zum Server, Anmeldestand und Profil.
@MainActor @Observable
final class AppZustand {
    /// Wo die App steht. Daraus folgt der Bildschirm.
    enum Phase: Equatable {
        case laden
        case konfigurationFehlt
        case offline
        case anmelden
        case zweiterFaktor
        case passwortAendern(Profil)
        case datenschutz(Profil)
        case bereit(Profil)
    }

    /// `nil`, solange die Basis-URL der Umgebung fehlt oder ungültig ist.
    let client: APIClient?
    private(set) var phase: Phase = .laden
    /// Der Server verlangt eine neuere App-Version; alles andere ist gesperrt.
    var appVeraltet = false
    /// Hier hängen Push-Token und Caches ein, die beim Abmelden fallen müssen.
    var beimAbmelden: [@MainActor () async -> Void] = []

    init(konfiguration: AppKonfiguration = .aktuell, speicher: some CookieSpeicher = KeychainCookieSpeicher()) {
        ErststartBereinigung.ausfuehren(speicher: speicher)
        let hatCookies = !speicher.lesen().isEmpty

        guard let basisURL = konfiguration.apiBasisURL else {
            client = nil
            phase = .konfigurationFehlt
            return
        }
        let version = APIClient.appVersion(aus: Bundle.main.infoDictionary ?? [:])
        // Der Client ruft zurück, bevor `self` fertig ist; deshalb über eine Weiche, die erst danach gefüllt wird.
        let weiche = EreignisWeiche()
        client = APIClient(basisURL: basisURL, appVersion: version, speicher: speicher) { weiche.melden($0) }
        weiche.ziel = { [weak self] ereignis in
            Task { @MainActor in self?.verarbeiten(ereignis) }
        }
        phase = hatCookies ? .laden : .anmelden
    }

    func verarbeiten(_ ereignis: APIEreignis) {
        switch ereignis {
        case .sitzungBeendet: sitzungWurdeBeendet()
        case .appVeraltet: appVeraltet = true
        }
    }

    var profil: Profil? {
        switch phase {
        case .passwortAendern(let p), .datenschutz(let p), .bereit(let p): p
        default: nil
        }
    }

    /// Kaltstart mit Cookie: Sitzung verlängern, dann Profil laden.
    func starten() async {
        guard let client, phase == .laden || phase == .offline else { return }
        phase = .laden
        do {
            guard try await client.sitzungPruefen() else {
                phase = .anmelden
                return
            }
            weiter(mit: try await client.profilLaden())
        } catch let fehler as APIFehler where fehler.art == .nichtAngemeldet {
            phase = .anmelden
        } catch {
            if !appVeraltet { phase = .offline }
        }
    }

    func anmelden(benutzername: String, passwort: String) async throws {
        guard let client else { return }
        switch try await client.anmelden(benutzername: benutzername, passwort: passwort) {
        case .zweiterFaktor: phase = .zweiterFaktor
        case .angemeldet: try await profilNachAnmeldung()
        }
    }

    func zweitenFaktorBestaetigen(code: String, ersatzcode: Bool) async throws {
        guard let client else { return }
        try await client.zweitenFaktorBestaetigen(code: code, ersatzcode: ersatzcode)
        try await profilNachAnmeldung()
    }

    /// Zurück zur Anmeldung, wenn der Zwischenschritt des zweiten Faktors nicht mehr gilt.
    func neuAnmelden() async {
        await client?.cookiesLoeschen()
        phase = .anmelden
    }

    func passwortGeaendert(aktuell: String, neu: String) async throws {
        guard let client else { return }
        try await client.passwortAendern(aktuell: aktuell, neu: neu)
        try await profilNachAnmeldung()
    }

    func datenschutzBestaetigt() async throws {
        guard let client else { return }
        try await client.datenschutzBestaetigen()
        try await profilNachAnmeldung()
    }

    func abmelden(ueberall: Bool = false) async {
        await client?.abmelden(ueberall: ueberall)
        for aufgabe in beimAbmelden { await aufgabe() }
        phase = .anmelden
    }

    private func profilNachAnmeldung() async throws {
        guard let client else { return }
        weiter(mit: try await client.profilLaden())
    }

    private func sitzungWurdeBeendet() {
        phase = .anmelden
        Task { for aufgabe in beimAbmelden { await aufgabe() } }
    }

    private func weiter(mit profil: Profil) {
        phase = Self.phase(fuer: profil)
    }

    /// Reihenfolge nach dem Backend: erst Passwortwechsel, dann Datenschutz, dann die App.
    nonisolated static func phase(fuer profil: Profil) -> Phase {
        if profil.mussPasswortAendern { return .passwortAendern(profil) }
        if profil.datenschutzGelesenAm == nil { return .datenschutz(profil) }
        return .bereit(profil)
    }
}

/// Reicht Ereignisse des Clients weiter, sobald der `AppZustand` bereit ist.
private nonisolated final class EreignisWeiche: @unchecked Sendable {
    // shortcut: ungeschützter Zugriff, ziel wird nur einmal direkt nach dem Init gesetzt; bei mehr Schreibern absichern.
    var ziel: (@Sendable (APIEreignis) -> Void)?
    func melden(_ ereignis: APIEreignis) { ziel?(ereignis) }
}
