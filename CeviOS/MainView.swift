import SwiftUI

/// Placeholder for the main navigation of the signed-in person. Programs, chat and profile follow in the next issues.
struct MainView: View {
    @Environment(AppState.self) private var state
    let profile: Profile

    var body: some View {
        VStack(spacing: 16) {
            Text("Hallo \(profile.ceviName ?? profile.name)")
                .font(.title.bold())
                .accessibilityAddTraits(.isHeader)
            Button("Abmelden", role: .destructive) {
                Task { await state.signOut() }
            }
            .frame(minHeight: 44)
        }
        .padding()
    }
}
