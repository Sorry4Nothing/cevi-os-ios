import Foundation
import LocalAuthentication
import Observation
import SwiftUI

/// App-Sperre: Face ID bzw. Touch ID mit Geräte-Code als Rückfall. Eine Hürde in der App, keine Verschlüsselung.
/// Sie greift beim Kaltstart und nach 5 Minuten im Hintergrund.
@MainActor @Observable
final class AppSperre {
    nonisolated static let wartezeit: TimeInterval = 5 * 60
    private static let elternSchluessel = "sperreFuerElternAktiv"

    private(set) var istGesperrt = true
    private(set) var fehlgeschlagen = false
    private var hintergrundSeit: Date?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Eltern können die Sperre abschalten; vorgeschlagen (an) ist sie trotzdem. Leitende und Stufenleitung nicht.
    var elternSperreAktiv: Bool {
        get { defaults.object(forKey: Self.elternSchluessel) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Self.elternSchluessel) }
    }

    func istErforderlich(fuer profil: Profil) -> Bool {
        profil.istLeitung || elternSperreAktiv
    }

    /// Ist ein Geräte-Code gesetzt? Ohne ihn lässt sich nichts sperren.
    static var geraeteCodeVorhanden: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    nonisolated static func sperreFaellig(hintergrundSeit: Date?, jetzt: Date) -> Bool {
        guard let hintergrundSeit else { return false }
        return jetzt.timeIntervalSince(hintergrundSeit) >= wartezeit
    }

    func szenenphase(_ phase: ScenePhase, jetzt: Date = .now) {
        switch phase {
        case .background:
            hintergrundSeit = hintergrundSeit ?? jetzt
        case .active:
            if Self.sperreFaellig(hintergrundSeit: hintergrundSeit, jetzt: jetzt) { istGesperrt = true }
            hintergrundSeit = nil
        default:
            break
        }
    }

    /// Fragt Face ID, Touch ID oder den Geräte-Code ab.
    func entsperren() async {
        fehlgeschlagen = false
        let kontext = LAContext()
        do {
            let ok = try await kontext.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: String(localized: "Cevi OS entsperren")
            )
            istGesperrt = !ok
            fehlgeschlagen = !ok
        } catch {
            fehlgeschlagen = true
        }
    }

    /// Nach dem Abmelden beginnt die nächste Person wieder gesperrt.
    func zuruecksetzen() {
        istGesperrt = true
        fehlgeschlagen = false
        hintergrundSeit = nil
    }
}
