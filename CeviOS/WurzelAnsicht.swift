import SwiftUI

/// Wurzel der App. Ist die App veraltet, sperrt der Hinweis alles andere. Sonst folgt der Bildschirm der Phase des `AppZustand`.
struct WurzelAnsicht: View {
    @Environment(\.appKonfiguration) private var konfiguration
    @Environment(AppZustand.self) private var zustand
    @Environment(AppSperre.self) private var sperre

    var body: some View {
        if zustand.appVeraltet {
            AppVeraltetAnsicht(appStoreURL: konfiguration.appStoreURL)
        } else {
            inhalt
                .task { await zustand.starten() }
        }
    }

    @ViewBuilder
    private var inhalt: some View {
        switch zustand.phase {
        case .laden:
            ProgressView().accessibilityLabel(Text("Lädt"))
        case .konfigurationFehlt:
            Text("Die Verbindung zum Server ist nicht eingerichtet.")
                .multilineTextAlignment(.center)
                .padding()
        case .offline:
            OfflineAnsicht()
        case .anmelden:
            AnmeldungAnsicht()
        case .zweiterFaktor:
            ZweiterFaktorAnsicht()
        case .passwortAendern:
            PasswortAendernAnsicht()
        case .datenschutz:
            DatenschutzAnsicht()
        case .bereit(let profil):
            geschuetzt(profil)
        }
    }

    @ViewBuilder
    private func geschuetzt(_ profil: Profil) -> some View {
        if !sperre.istErforderlich(fuer: profil) || !sperre.istGesperrt {
            HauptAnsicht(profil: profil)
        } else if AppSperre.geraeteCodeVorhanden {
            SperreAnsicht()
        } else if profil.istLeitung {
            GeraeteCodeFehltAnsicht()
        } else {
            // Ohne Geräte-Code lässt sich für Eltern nichts sperren.
            HauptAnsicht(profil: profil)
        }
    }
}

/// Vollbild-Hinweis bei 426 `APP_VERALTET`.
struct AppVeraltetAnsicht: View {
    let appStoreURL: URL?

    var body: some View {
        VStack(spacing: 24) {
            Text("Bitte die App aktualisieren")
                .font(.title.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text("Diese Version von Cevi OS wird nicht mehr unterstützt.")
                .font(.body)
                .multilineTextAlignment(.center)
            if let appStoreURL {
                Link("Im App Store öffnen", destination: appStoreURL)
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 44)
            }
        }
        .padding()
    }
}

#Preview("App veraltet") {
    AppVeraltetAnsicht(appStoreURL: URL(string: "https://apps.apple.com/app/example"))
}
