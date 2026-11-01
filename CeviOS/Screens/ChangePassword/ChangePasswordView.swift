import SwiftUI

/// T02 Passwort: own password after the first sign-in.
struct ChangePasswordView: View {
    @Environment(AppState.self) private var state
    @State private var current = ""
    @State private var new = ""
    @State private var repeated = ""
    @State private var action = ActionState()
    @FocusState private var currentFocused: Bool
    @FocusState private var newFocused: Bool
    @FocusState private var repeatedFocused: Bool

    private var mismatch: Bool { !repeated.isEmpty && repeated != new }
    private var canSubmit: Bool { !current.isEmpty && new.count >= 12 && new == repeated && !action.isRunning }

    var body: some View {
        StepScreen(title: "Eigenes Passwort wählen", subtitle: "Erster Login") {
            Text("Du hast ein Startpasswort von der Abteilung bekommen. Wähle jetzt ein eigenes, das nur du kennst.")
                .font(.body)
                .foregroundStyle(Color.ceviOnSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
            CeviField(label: "Startpasswort", focus: $currentFocused) {
                PasswordField(label: "Startpasswort", text: $current, isFocused: $currentFocused)
                    .submitLabel(.next)
                    .onSubmit { newFocused = true }
            }
            VStack(alignment: .leading, spacing: Spacing.s2) {
                CeviField(label: "Neues Passwort", focus: $newFocused) {
                    PasswordField(label: "Neues Passwort", text: $new, kind: .new, isFocused: $newFocused)
                        // The return key moves on: with the keyboard up, the action bar covers the last field.
                        .submitLabel(.next)
                        .onSubmit { repeatedFocused = true }
                }
                RuleRow(text: "Mindestens 12 Zeichen", isMet: new.count >= 12)
            }
            VStack(alignment: .leading, spacing: Spacing.s2) {
                CeviField(label: "Passwort wiederholen", focus: $repeatedFocused) {
                    PasswordField(label: "Passwort wiederholen", text: $repeated, kind: .new,
                                  isFocused: $repeatedFocused)
                }
                if mismatch {
                    ErrorRow(text: String(localized: "Die beiden neuen Passwörter sind nicht gleich."))
                } else if !repeated.isEmpty {
                    RuleRow(text: "Stimmt überein", isMet: true)
                }
            }
            if let error = action.error {
                ErrorRow(text: error)
            }
        } actions: {
            Button {
                Task {
                    await action.perform(message: AuthMessages.changePassword) {
                        try await state.passwordChanged(current: current, new: new)
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
