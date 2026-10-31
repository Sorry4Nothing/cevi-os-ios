import SwiftUI

/// Platzhalter für die Hauptnavigation der angemeldeten Person. Programme, Chat und Profil folgen in den nächsten Issues.
struct HauptAnsicht: View {
    @Environment(AppZustand.self) private var zustand
    let profil: Profil

    var body: some View {
        VStack(spacing: 16) {
            Text("Hallo \(profil.ceviName ?? profil.name)")
                .font(.title.bold())
                .accessibilityAddTraits(.isHeader)
            Button("Abmelden", role: .destructive) {
                Task { await zustand.abmelden() }
            }
            .frame(minHeight: 44)
        }
        .padding()
    }
}
