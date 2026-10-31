import SwiftUI

/// Short explanation before the system asks for permission.
struct PushExplanationView: View {
    @Environment(PushManager.self) private var push

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Benachrichtigungen")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Cevi OS kann dir melden, wenn es neue Chat-Nachrichten oder Änderungen bei Programmen gibt. Die Mitteilung nennt nie den Text einer Nachricht oder Namen von Kindern. Du kannst das jederzeit in den Einstellungen ändern.")
            Button {
                Task { await push.requestPermission() }
            } label: {
                Text("Weiter").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            Button {
                push.needsExplanation = false
            } label: {
                Text("Nicht jetzt").frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .padding()
        .presentationDetents([.medium])
    }
}
