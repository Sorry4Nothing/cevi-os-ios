import SwiftUI

/// Platzhalter für die Wurzel der App. Anmeldung und Navigation folgen in den nächsten Issues.
struct WurzelAnsicht: View {
    @Environment(\.appKonfiguration) private var konfiguration

    var body: some View {
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
            }
        }
        .padding()
    }
}

#Preview {
    WurzelAnsicht()
}
