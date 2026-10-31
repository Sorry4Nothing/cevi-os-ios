import Foundation
import Testing
@testable import CeviOS

struct AppKonfigurationTests {
    @Test func gueltigeHttpsAdresseWirdUebernommen() {
        let konfiguration = AppKonfiguration(
            umgebung: .dev,
            infoDictionary: [AppKonfiguration.basisURLSchluessel: "https://api.example.org"]
        )
        #expect(konfiguration.apiBasisURL == URL(string: "https://api.example.org"))
        #expect(konfiguration.istVollstaendig)
    }

    @Test func umgebendeLeerzeichenWerdenEntfernt() {
        #expect(AppKonfiguration.gueltigeBasisURL("  https://api.example.org \n") == URL(string: "https://api.example.org"))
    }

    @Test(arguments: [nil, "", "   ", "http://api.example.org", "api.example.org", "https://"] as [String?])
    func ungueltigeAdresseErgibtKeineURL(text: String?) {
        #expect(AppKonfiguration.gueltigeBasisURL(text) == nil)
    }

    @Test func fehlenderSchluesselErgibtUnvollstaendigeKonfiguration() {
        let konfiguration = AppKonfiguration(umgebung: .prod, infoDictionary: [:])
        #expect(konfiguration.apiBasisURL == nil)
        #expect(!konfiguration.istVollstaendig)
    }

    @Test func umgebungEntsprichtDemScheme() {
        #if DEV
        #expect(AppKonfiguration.aktuell.umgebung == .dev)
        #elseif INT
        #expect(AppKonfiguration.aktuell.umgebung == .int)
        #else
        #expect(AppKonfiguration.aktuell.umgebung == .prod)
        #endif
    }
}
