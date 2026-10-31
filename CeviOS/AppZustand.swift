import Foundation
import Observation

/// Zustand der ganzen App: Verbindung zum Server und ob eine Sitzung besteht.
@MainActor @Observable
final class AppZustand {
    /// `nil`, solange die Basis-URL der Umgebung fehlt oder ungültig ist.
    let client: APIClient?
    /// Eine Sitzung (Cookie) liegt im Keychain. Ohne sie startet die App in der Anmeldung.
    var hatSitzung: Bool
    /// Der Server verlangt eine neuere App-Version; alles andere ist gesperrt.
    var appVeraltet = false

    init(konfiguration: AppKonfiguration = .aktuell, speicher: some CookieSpeicher = KeychainCookieSpeicher()) {
        ErststartBereinigung.ausfuehren(speicher: speicher)
        hatSitzung = !speicher.lesen().isEmpty

        guard let basisURL = konfiguration.apiBasisURL else {
            client = nil
            return
        }
        let version = APIClient.appVersion(aus: Bundle.main.infoDictionary ?? [:])
        // Der Client ruft zurück, bevor `self` fertig ist; deshalb über eine Box, die erst danach gefüllt wird.
        let weiche = EreignisWeiche()
        client = APIClient(basisURL: basisURL, appVersion: version, speicher: speicher) { weiche.melden($0) }
        weiche.ziel = { [weak self] ereignis in
            Task { @MainActor in self?.verarbeiten(ereignis) }
        }
    }

    func verarbeiten(_ ereignis: APIEreignis) {
        switch ereignis {
        case .sitzungBeendet: hatSitzung = false
        case .appVeraltet: appVeraltet = true
        }
    }
}

/// Reicht Ereignisse des Clients weiter, sobald der `AppZustand` bereit ist.
private nonisolated final class EreignisWeiche: @unchecked Sendable {
    // shortcut: ungeschützter Zugriff, ziel wird nur einmal direkt nach dem Init gesetzt; bei mehr Schreibern absichern.
    var ziel: (@Sendable (APIEreignis) -> Void)?
    func melden(_ ereignis: APIEreignis) { ziel?(ereignis) }
}
