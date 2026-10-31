import SwiftUI

/// Short explanation before the system asks for permission.
struct PushExplanationView: View {
    @Environment(PushManager.self) private var push

    var body: some View {
        // Scrolls and may grow to full height, so large text sizes are never cut off.
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                Text("Benachrichtigungen")
                    .font(.title(.title2))
                    .foregroundStyle(Color.ceviOnSurface)
                    .accessibilityAddTraits(.isHeader)
                Text("Cevi OS kann dir melden, wenn es neue Chat-Nachrichten oder Änderungen bei Programmen gibt. Die Mitteilung nennt nie den Text einer Nachricht oder Namen von Kindern. Du kannst das jederzeit in den Einstellungen ändern.")
                    .foregroundStyle(Color.ceviOnSurfaceVariant)
                Button("Weiter") { Task { await push.requestPermission() } }
                    .buttonStyle(.ceviPrimary)
                Button("Nicht jetzt") { push.needsExplanation = false }
                    .buttonStyle(.ceviText)
                    .frame(maxWidth: .infinity)
            }
            .padding(Spacing.s4)
        }
        .ceviScreenBackground()
        .presentationDetents([.medium, .large])
    }
}
