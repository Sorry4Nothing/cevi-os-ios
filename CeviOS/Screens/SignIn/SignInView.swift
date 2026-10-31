import SwiftUI

/// T01 Login.
struct SignInView: View {
    @Environment(AppState.self) private var state
    @Environment(\.appConfiguration) private var configuration
    @Environment(\.openURL) private var openURL
    @State private var username = ""
    @State private var password = ""
    @State private var action = ActionState()
    @FocusState private var usernameFocused: Bool
    @FocusState private var passwordFocused: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        FillingScrollView {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Spacer(minLength: Spacing.s8)
                    // App name as eyebrow: the screen names the app it belongs to.
                    Eyebrow("Cevi OS")
                    Text("Schön, bist du da.")
                        .font(.title(.display))
                        .foregroundStyle(Color.ceviOnSurface)
                        .accessibilityAddTraits(.isHeader)
                }
                .frame(maxWidth: Size.contentMax, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.horizontal, Spacing.s6)
                .padding(.bottom, Spacing.s6)
                panel
            }
        }
        // Surface above, panel color below: overscroll and the home indicator area match the part next to them.
        .background {
            VStack(spacing: 0) {
                Color.ceviSurface
                Color.ceviSurfaceContainerLow
            }
            .ignoresSafeArea()
        }
    }

    private var panel: some View {
        VStack(spacing: Spacing.s4) {
            CeviField(label: "Benutzername", isFocused: usernameFocused) {
                TextField("", text: $username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($usernameFocused)
                    .submitLabel(.next)
                    .onSubmit { passwordFocused = true }
                    .frame(minHeight: Size.touchTarget)
                    .accessibilityLabel(Text("Benutzername"))
            }
            CeviField(label: "Passwort", isFocused: passwordFocused) {
                PasswordField(label: "Passwort", text: $password, isFocused: $passwordFocused)
                    .submitLabel(.go)
                    .onSubmit(signIn)
            }
            if let error = action.error {
                ErrorRow(text: error)
            }
            Button(action: signIn) {
                ProgressLabel(title: "Anmelden", isRunning: action.isRunning)
            }
            .buttonStyle(.ceviPrimary)
            .disabled(action.isRunning)
            .padding(.top, Spacing.s1)
            if let url = ServerPage.support.url(base: configuration.apiBaseURL) {
                // Button instead of Link: the audit reports the Link text as clipped.
                Button("Passwort vergessen?") { openURL(url) }
                    .buttonStyle(.ceviText)
                    .accessibilityAddTraits(.isLink)
            }
        }
        .frame(maxWidth: Size.contentMax)
        .padding(.horizontal, Spacing.s5)
        .padding(.vertical, Spacing.s6)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                Color.ceviSurface
                UnevenRoundedRectangle(topLeadingRadius: Radius.xl, topTrailingRadius: Radius.xl, style: .continuous)
                    .fill(Color.ceviSurfaceContainerLow)
                    .stroke(contrast == .increased ? Color.ceviOutline : Color.ceviOutlineVariant, lineWidth: Size.border)
            }
        }
    }

    private func signIn() {
        guard !action.isRunning else { return }
        guard !username.isEmpty, !password.isEmpty else {
            action.error = String(localized: "Bitte Benutzername und Passwort eingeben.")
            return
        }
        Task {
            await action.perform { try await state.signIn(username: username, password: password) }
            if action.error != nil { password = "" }
        }
    }
}

#Preview("Login") {
    SignInView().environment(AppState())
}

#Preview("Login Nacht") {
    SignInView().environment(AppState()).preferredColorScheme(.dark)
}
