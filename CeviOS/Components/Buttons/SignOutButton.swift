import SwiftUI

/// T12: sign-out with confirmation. The caller picks the button style.
struct SignOutButton: View {
    @Environment(AppState.self) private var state
    @State private var isConfirming = false

    var body: some View {
        Button("Abmelden", role: .destructive) { isConfirming = true }
            .alert("Abmelden?", isPresented: $isConfirming) {
                Button("Abbrechen", role: .cancel) {}
                Button("Abmelden", role: .destructive) {
                    Task { await state.signOut() }
                }
            } message: {
                Text("Danach brauchst du wieder Benutzername und Passwort.")
            }
    }
}

#Preview("Abmelden") {
    List { SignOutButton().foregroundStyle(Color.ceviPrimaryText) }.environment(AppState())
}
