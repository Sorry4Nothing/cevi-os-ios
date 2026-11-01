import SwiftUI

/// Second factor after the password. No template; styled like T02.
struct SecondFactorView: View {
    @Environment(AppState.self) private var state
    @State private var code = ""
    @State private var isBackupCode = false
    @State private var action = ActionState()
    @FocusState private var codeFocused: Bool

    private var canSubmit: Bool {
        !action.isRunning && (isBackupCode ? code.count == 11 : code.count == 6)
    }

    var body: some View {
        StepScreen(title: "Zweiter Faktor", subtitle: "Anmelden") {
            Text(isBackupCode
                ? "Gib einen deiner Ersatzcodes ein (Format xxxxx-xxxxx). Jeder Code gilt nur einmal."
                : "Gib den 6-stelligen Code aus deiner Authenticator-App ein.")
                .font(.body)
                .foregroundStyle(Color.ceviOnSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            CeviField(label: isBackupCode ? "Ersatzcode" : "Code", focus: $codeFocused) {
                TextField("", text: $code)
                    .keyboardType(isBackupCode ? .asciiCapable : .numberPad)
                    .textContentType(.oneTimeCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($codeFocused)
                    .frame(minHeight: Size.touchTarget)
                    .accessibilityLabel(isBackupCode ? Text("Ersatzcode") : Text("Code"))
                    .onChange(of: code) { _, new in
                        code = String(new.prefix(isBackupCode ? 11 : 6))
                    }
            }
            Toggle("Ersatzcode verwenden", isOn: $isBackupCode)
                .tint(Color.ceviSwitchOn)
                .foregroundStyle(Color.ceviOnSurface)
                .frame(minHeight: Size.touchTarget)
                .onChange(of: isBackupCode) { code = "" }
            if let error = action.error {
                ErrorRow(text: error)
            }
        } actions: {
            Button(action: submit) {
                ProgressLabel(title: "Bestätigen", isRunning: action.isRunning)
            }
            .buttonStyle(.ceviPrimary)
            .disabled(!canSubmit)
            Button("Abbrechen", role: .cancel) {
                Task { await state.restartSignIn() }
            }
            .buttonStyle(.ceviText)
        }
    }

    private func submit() {
        Task {
            var restartSignIn = false
            await action.perform(message: { error in
                let message = AuthMessages.secondFactor(error)
                restartSignIn = message.restartSignIn
                return message.text
            }) {
                try await state.confirmSecondFactor(code: code, isBackupCode: isBackupCode)
            }
            if restartSignIn { await state.restartSignIn() }
            if action.error != nil { code = "" }
        }
    }
}

#Preview("Zweiter Faktor") {
    SecondFactorView().environment(AppState())
}
