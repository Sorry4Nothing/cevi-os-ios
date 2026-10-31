import Foundation
import SwiftUI

/// Konfiguration der laufenden Umgebung. Die Werte stammen aus der Build-Konfiguration (`Config/*.xcconfig`), nie aus dem Code.
struct AppKonfiguration: Equatable, Sendable {
    enum Umgebung: String, Sendable {
        case dev = "Dev"
        case int = "Int"
        case prod = "Prod"
    }

    /// Schlüssel in der Info.plist, gefüllt aus `API_BASE_URL` der xcconfig.
    static let basisURLSchluessel = "APIBaseURL"

    let umgebung: Umgebung
    /// Basis-URL der API. `nil`, wenn sie fehlt oder ungültig ist (nur `https` ist erlaubt).
    let apiBasisURL: URL?

    init(umgebung: Umgebung, infoDictionary: [String: Any]) {
        self.umgebung = umgebung
        apiBasisURL = Self.gueltigeBasisURL(infoDictionary[Self.basisURLSchluessel] as? String)
    }

    var istVollstaendig: Bool {
        apiBasisURL != nil
    }

    static func gueltigeBasisURL(_ text: String?) -> URL? {
        guard
            let text = text?.trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty,
            let url = URL(string: text),
            url.scheme == "https",
            url.host() != nil
        else {
            return nil
        }
        return url
    }

    /// Konfiguration der laufenden App. Die Umgebung bestimmt das Compiler-Flag des Schemes (`DEV`, `INT`, sonst `PROD`).
    static let aktuell = AppKonfiguration(
        umgebung: laufendeUmgebung,
        infoDictionary: Bundle.main.infoDictionary ?? [:]
    )

    private static var laufendeUmgebung: Umgebung {
        #if DEV
        return .dev
        #elseif INT
        return .int
        #else
        return .prod
        #endif
    }
}

extension EnvironmentValues {
    @Entry var appKonfiguration = AppKonfiguration.aktuell
}
