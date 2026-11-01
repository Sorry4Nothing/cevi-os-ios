import SwiftUI

/// T02 Passwort: own password after the first sign-in. The start password of the sign-in stays in memory, so it is not asked
/// again. Only when the app lost it (restart during the change) a field «Bisheriges Passwort» appears.
struct ChangePasswordView: View {
    @Environment(AppState.self) private var state
    @State private var current = ""
    @State private var new = ""
    @State private var action = ActionState()
    @FocusState private var currentFocused: Bool
    @FocusState private var newFocused: Bool

    private var needsCurrent: Bool { state.loginPassword == nil }
    private var canSubmit: Bool { (!needsCurrent || !current.isEmpty) && new.count >= 12 && !action.isRunning }

    var body: some View {
        StepScreen(title: "Eigenes Passwort wählen", subtitle: "Erster Login") {
            Text("Du hast ein Startpasswort von der Abteilung bekommen. Wähle jetzt ein eigenes, das nur du kennst.")
                .font(.body)
                .foregroundStyle(Color.ceviOnSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
            if needsCurrent {
                CeviField(label: "Bisheriges Passwort", focus: $currentFocused) {
                    PasswordField(label: "Bisheriges Passwort", text: $current, isFocused: $currentFocused)
                        .submitLabel(.next)
                        .onSubmit { newFocused = true }
                }
            }
            VStack(alignment: .leading, spacing: Spacing.s2) {
                // One eye per field replaces a «repeat» field.
                CeviField(label: "Neues Passwort", focus: $newFocused) {
                    PasswordField(label: "Neues Passwort", text: $new, kind: .new, isFocused: $newFocused)
                        .submitLabel(.done)
                        .onSubmit { newFocused = false }
                }
                RuleRow(text: "Mindestens 12 Zeichen", isMet: new.count >= 12)
            }
            if let error = action.error {
                ErrorRow(text: error)
            }
        } actions: {
            Button {
                Task {
                    await action.perform(message: AuthMessages.changePassword) {
                        try await state.passwordChanged(current: needsCurrent ? current : nil, new: new)
                    }
                }
            } label: {
                ProgressLabel(title: "Passwort speichern", isRunning: action.isRunning)
            }
            .buttonStyle(.ceviPrimary)
            .disabled(!canSubmit)
            SignOutButton()
                .buttonStyle(CeviTextButtonStyle(color: .ceviPrimaryText))
        }
    }
}

#Preview("Passwort") {
    ChangePasswordView().environment(AppState())
}

#Preview("Passwort Nacht") {
    ChangePasswordView().environment(AppState()).preferredColorScheme(.dark)
}
