import SwiftUI

/// Wurzel der App. Ist die App veraltet, sperrt der Hinweis alles andere. Anmeldung und Navigation folgen in den nächsten Issues.
struct WurzelAnsicht: View {
    @Environment(\.appKonfiguration) private var konfiguration
    @Environment(AppZustand.self) private var zustand

    var body: some View {
        if zustand.appVeraltet {
            AppVeraltetAnsicht(appStoreURL: konfiguration.appStoreURL)
        } else {
            platzhalter
        }
    }

    private var platzhalter: some View {
        VStack(spacing: 16) {
            Text("Cevi OS")
                .font(.largeTitle.bold())
            if konfiguration.umgebung != .prod {
                Text("Umgebung: \(konfiguration.umgebung.rawValue)")
                    .font(.subheadline)
            }
            if !konfiguration.istVollstaendig {
                Text("Die Verbindung zum Server ist nicht eingerichtet.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
            } else if !zustand.hatSitzung {
                Text("Anmeldung")
                    .font(.headline)
            }
        }
        .padding()
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

#Preview {
    WurzelAnsicht()
        .environment(AppZustand())
}

#Preview("App veraltet") {
    AppVeraltetAnsicht(appStoreURL: URL(string: "https://apps.apple.com/app/example"))
}
