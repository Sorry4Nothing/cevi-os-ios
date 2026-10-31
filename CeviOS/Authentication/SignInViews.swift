import SafariServices
import SwiftUI

/// Public pages of the server (no sign-in needed).
nonisolated enum ServerPage: String {
    case privacy = "/datenschutz"
    case support = "/support"
    case deleteAccount = "/konto-loeschen"

    func url(base: URL?) -> URL? {
        base.flatMap { URL(string: $0.absoluteString + rawValue) }
    }
}

/// Error row with symbol and text, not color alone.
struct ErrorRow: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(Color.ceviOnErrorContainer)
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(Text("Fehler: \(text)"))
    }
}

/// Fulfilled or open rule, with symbol and word (not color alone).
struct RuleRow: View {
    let text: LocalizedStringKey
    let isMet: Bool

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
        }
        .font(.subheadline)
        .foregroundStyle(isMet ? Color.ceviOnSuccessContainer : Color.ceviOnSurfaceVariant)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(text))
        .accessibilityValue(isMet ? Text("erfüllt") : Text("nicht erfüllt"))
    }
}

/// Runs an action and shows its error. Prevents double taps.
@MainActor @Observable
final class ActionState {
    var isRunning = false
    var error: String?

    func perform(message: (APIError) -> String = { $0.displayText }, _ action: () async throws -> Void) async {
        guard !isRunning else { return }
        isRunning = true
        error = nil
        defer { isRunning = false }
        do {
            try await action()
        } catch let error as APIError {
            self.error = message(error)
        } catch is CancellationError {
        } catch {
            self.error = APIError.network.displayText
        }
    }
}

/// Label of a main button with a spinner while the action runs.
private struct ProgressLabel: View {
    let title: LocalizedStringKey
    let isRunning: Bool

    var body: some View {
        HStack(spacing: Spacing.s2) {
            Text(title)
            if isRunning { ProgressView().tint(Color.ceviOnSurfaceVariant) }
        }
    }
}

/// Layout of the sign-in steps after the password (T02): title, content, main action at the bottom.
/// At accessibility text sizes the actions scroll with the content so they never cover it.
private struct StepScreen<Content: View, Actions: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s5) {
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text(title)
                        .font(.title(.title1))
                        .foregroundStyle(Color.ceviOnSurface)
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.ceviOnSurfaceVariant)
                    }
                }
                content
                if typeSize.isAccessibilitySize { actionStack }
            }
            .padding(.horizontal, Spacing.s4)
            .padding(.top, Spacing.s8)
            .padding(.bottom, Spacing.s4)
            .frame(maxWidth: Size.contentMax)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            if !typeSize.isAccessibilitySize {
                actionStack
                    .padding(.horizontal, Spacing.s4)
                    .padding(.vertical, Spacing.s3)
                    .frame(maxWidth: Size.contentMax)
                    .frame(maxWidth: .infinity)
                    .background(Color.ceviSurface)
            }
        }
        .ceviScreenBackground()
    }

    private var actionStack: some View {
        VStack(spacing: Spacing.s1) { actions }
    }
}

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
                    .stroke(Color.ceviOutlineVariant, lineWidth: Size.border)
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
            CeviField(label: isBackupCode ? "Ersatzcode" : "Code", isFocused: codeFocused) {
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
            CeviField(label: "Startpasswort", isFocused: currentFocused) {
                PasswordField(label: "Startpasswort", text: $current, isFocused: $currentFocused)
            }
            VStack(alignment: .leading, spacing: Spacing.s2) {
                CeviField(label: "Neues Passwort", isFocused: newFocused) {
                    PasswordField(label: "Neues Passwort", text: $new, contentType: .newPassword, isFocused: $newFocused)
                }
                RuleRow(text: "Mindestens 12 Zeichen", isMet: new.count >= 12)
            }
            VStack(alignment: .leading, spacing: Spacing.s2) {
                CeviField(label: "Passwort wiederholen", isFocused: repeatedFocused) {
                    PasswordField(label: "Passwort wiederholen", text: $repeated, contentType: .newPassword,
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

/// T03 Willkommen: confirm the privacy statement before the app opens.
struct PrivacyView: View {
    @Environment(AppState.self) private var state
    @Environment(\.appConfiguration) private var configuration
    /// Name in the greeting.
    let name: String
    /// First names of the children (parents); empty for leaders.
    let childNames: [String]
    @State private var action = ActionState()
    @State private var isPageOpen = false
    @State private var accepted = false

    var body: some View {
        let url = ServerPage.privacy.url(base: configuration.apiBaseURL)
        FillingScrollView {
            VStack(alignment: .leading, spacing: Spacing.s5) {
                Spacer(minLength: Spacing.s8)
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Eyebrow("Cevi Stäfa-Hombrechtikon")
                    Text("Willkommen, \(name)!")
                        .font(.title(.display))
                        .foregroundStyle(Color.ceviOnSurface)
                        .accessibilityAddTraits(.isHeader)
                }
                VStack(alignment: .leading, spacing: Spacing.s4) {
                    feature("Programme", text: programsText, symbol: "calendar")
                    feature("Zusagen", text: "Mit einem Tipp Ja oder Nein sagen.", symbol: "checkmark")
                    feature("Chat", text: "Nachrichten an die Stufenleitung und in der Gruppe.",
                            symbol: "bubble.left.and.bubble.right")
                }
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Toggle("Ich habe die Datenschutzerklärung gelesen und bin einverstanden.", isOn: $accepted)
                        .toggleStyle(CheckboxToggleStyle())
                    Button("Datenschutzerklärung lesen") { isPageOpen = true }
                        .buttonStyle(.ceviText)
                        .disabled(url == nil)
                    if let error = action.error {
                        ErrorRow(text: error)
                    }
                    Button {
                        Task { await action.perform { try await state.privacyAcknowledged() } }
                    } label: {
                        ProgressLabel(title: "Los geht’s", isRunning: action.isRunning)
                    }
                    .buttonStyle(.ceviPrimary)
                    .disabled(!accepted || action.isRunning)
                    SignOutButton()
                        .buttonStyle(CeviTextButtonStyle(color: .ceviPrimaryText))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: Size.contentMax, alignment: .leading)
            .padding(.horizontal, Spacing.s6)
            .padding(.bottom, Spacing.s4)
        }
        .ceviScreenBackground()
        .fullScreenCover(isPresented: $isPageOpen) {
            if let url { SafariView(url: url).ignoresSafeArea() }
        }
    }

    private var programsText: LocalizedStringKey {
        childNames.isEmpty
            ? "Alle Anlässe deiner Stufe auf einen Blick."
            : "Alle Anlässe von \(childNames.formatted(.list(type: .and))) auf einen Blick."
    }

    private func feature(_ title: LocalizedStringKey, text: LocalizedStringKey, symbol: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.s4) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundStyle(Color.ceviOnSecondaryContainer)
                .frame(width: Size.avatar, height: Size.avatar)
                .background(Color.ceviSecondaryContainer, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.headline).foregroundStyle(Color.ceviOnSurface)
                Text(text).font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

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

/// T11 Datenschutz: short version of the privacy statement inside the app.
struct PrivacyPolicyView: View {
    var body: some View {
        List {
            section("Was wir speichern", bullets: [
                "Deinen Namen, Benutzernamen und deine Rolle",
                "Bei Eltern: die Namen eurer Kinder und ihre Stufe",
                "Deine Zusagen zu Programmen",
                "Deine Chat-Nachrichten und dein Profilbild",
            ])
            section("Wer was sieht", text: "Programme sehen alle aus der Stufe. Zusagen sieht die Leitung. Nachrichten an die Stufenleitung lesen alle Stufenleitenden dieser Stufe.")
            section("Was wir nicht machen", bullets: [
                "Keine Werbung und keine Tracker",
                "Keine Weitergabe an andere",
                "Keine Nachrichten oder Namen in Mitteilungen",
            ])
            Section {
                card("Löschen") {
                    paragraph("Dein Konto löscht die Abteilung. Schreib dafür an die Abteilungsleitung.")
                }
            } footer: {
                Text("Stand: 1. November 2026 · Cevi Stäfa-Hombrechtikon")
                    .font(.footnote)
                    .foregroundStyle(Color.ceviOnSurfaceVariant)
            }
        }
        .listSectionSpacing(Spacing.s3)
        .scrollContentBackground(.hidden)
        .ceviScreenBackground()
        .navigationTitle("Datenschutz")
        .navigationSubtitle("Cevi Stäfa-Hombrechtikon")
    }

    private func section(_ title: LocalizedStringKey, text: LocalizedStringKey) -> some View {
        Section { card(title) { paragraph(text) } }
    }

    private func section(_ title: LocalizedStringKey, bullets: [LocalizedStringKey]) -> some View {
        Section {
            card(title) {
                ForEach(bullets.indices, id: \.self) { index in
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.s2) {
                        Text(verbatim: "•").accessibilityHidden(true)
                        Text(bullets[index])
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.ceviOnSurfaceVariant)
                }
            }
        }
    }

    private func card(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.ceviOnSurface)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(.vertical, Spacing.s1)
        .listRowBackground(Color.ceviSurfaceContainerLow)
    }

    private func paragraph(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

/// Locked: unlock with Face ID, Touch ID or device code.
struct LockView: View {
    @Environment(AppLock.self) private var lock

    var body: some View {
        StateView(
            symbol: lock.failed ? "lock.trianglebadge.exclamationmark" : "lock.fill",
            title: "Cevi OS ist gesperrt",
            message: lock.failed ? "Das Entsperren hat nicht geklappt." : nil,
            tone: lock.failed ? .error : .neutral,
            primary: StateView.Action(title: "Entsperren", symbol: "faceid") { Task { await lock.unlock() } }
        )
        .task { await lock.unlock() }
    }
}

/// Leaders and unit leaders see no data without a device code.
struct DeviceCodeMissingView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                Text("Geräte-Code einrichten")
                    .font(.title(.title1))
                    .foregroundStyle(Color.ceviOnSurface)
                    .accessibilityAddTraits(.isHeader)
                Text("Als Leitung siehst du Daten von Kindern. Dafür braucht dein iPhone einen Geräte-Code. Ohne ihn zeigt Cevi OS nichts an.")
                Text("So richtest du ihn ein: Öffne die Einstellungen, tippe auf «Face ID & Code» (oder «Touch ID & Code») und dann auf «Code aktivieren». Danach öffnest du Cevi OS wieder.")
            }
            .foregroundStyle(Color.ceviOnSurfaceVariant)
            .padding(.horizontal, Spacing.s4)
            .padding(.top, Spacing.s8)
            .frame(maxWidth: Size.contentMax, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .ceviScreenBackground()
    }
}

/// ZT4: no connection at launch.
struct OfflineView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        StateView.offline { Task { await state.start() } }
    }
}

#Preview("Login") {
    SignInView().environment(AppState())
}

#Preview("Login Nacht") {
    SignInView().environment(AppState()).preferredColorScheme(.dark)
}

#Preview("Zweiter Faktor") {
    SecondFactorView().environment(AppState())
}

#Preview("Passwort") {
    ChangePasswordView().environment(AppState())
}

#Preview("Passwort Nacht") {
    ChangePasswordView().environment(AppState()).preferredColorScheme(.dark)
}

#Preview("Willkommen") {
    PrivacyView(name: "Marion", childNames: ["Lena", "Noah"]).environment(AppState())
}

#Preview("Willkommen Nacht") {
    PrivacyView(name: "Marion", childNames: []).environment(AppState()).preferredColorScheme(.dark)
}

#Preview("Datenschutz") {
    NavigationStack { PrivacyPolicyView() }
}

#Preview("Abmelden") {
    List { SignOutButton().foregroundStyle(Color.ceviPrimaryText) }.environment(AppState())
}

#Preview("Gesperrt") {
    LockView().environment(AppLock())
}
