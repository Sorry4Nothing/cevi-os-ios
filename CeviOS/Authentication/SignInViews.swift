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
            .accessibilityLabel(Text("Fehler: \(text)"))
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

struct SignInView: View {
    @Environment(AppState.self) private var state
    @Environment(\.appConfiguration) private var configuration
    @State private var username = ""
    @State private var password = ""
    @State private var action = ActionState()
    @FocusState private var focus: Field?

    private enum Field { case username, password }

    var body: some View {
        Form {
            Section {
                Text("Cevi OS")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                    .listRowBackground(Color.clear)
            }
            Section {
                // Label above the field instead of a placeholder: placeholder text has too little contrast.
                VStack(alignment: .leading, spacing: 4) {
                    Text("Benutzername").font(.subheadline)
                    TextField("", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .username)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                        .accessibilityLabel(Text("Benutzername"))
                }
                .frame(minHeight: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Passwort").font(.subheadline)
                    SecureField("", text: $password)
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit(signIn)
                        .accessibilityLabel(Text("Passwort"))
                }
                .frame(minHeight: 44)
            }
            if let error = action.error {
                Section { ErrorRow(text: error) }
            }
            Section {
                Button(action: signIn) {
                    HStack {
                        Text("Anmelden")
                        if action.isRunning { ProgressView() }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(action.isRunning)
            }
            Section {
                if let url = ServerPage.support.url(base: configuration.apiBaseURL) {
                    Link("Hilfe und Kontakt", destination: url).frame(minHeight: 44)
                }
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

struct SecondFactorView: View {
    @Environment(AppState.self) private var state
    @State private var code = ""
    @State private var isBackupCode = false
    @State private var action = ActionState()

    private var canSubmit: Bool {
        !action.isRunning && (isBackupCode ? code.count == 11 : code.count == 6)
    }

    var body: some View {
        Form {
            Section {
                Text(isBackupCode
                    ? "Gib einen deiner Ersatzcodes ein (Format xxxxx-xxxxx). Jeder Code gilt nur einmal."
                    : "Gib den 6-stelligen Code aus deiner Authenticator-App ein.")
            } header: {
                Text("Zweiter Faktor").accessibilityAddTraits(.isHeader)
            }
            Section {
                TextField(isBackupCode ? "Ersatzcode" : "Code", text: $code)
                    .keyboardType(isBackupCode ? .asciiCapable : .numberPad)
                    .textContentType(.oneTimeCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .frame(minHeight: 44)
                    .onChange(of: code) { _, new in
                        code = String(new.prefix(isBackupCode ? 11 : 6))
                    }
                Toggle("Ersatzcode verwenden", isOn: $isBackupCode)
                    .frame(minHeight: 44)
                    .onChange(of: isBackupCode) { code = "" }
            }
            if let error = action.error {
                Section { ErrorRow(text: error) }
            }
            Section {
                Button {
                    submit()
                } label: {
                    HStack {
                        Text("Bestätigen")
                        if action.isRunning { ProgressView() }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(!canSubmit)
                Button("Abbrechen", role: .cancel) {
                    Task { await state.restartSignIn() }
                }
                .frame(minHeight: 44)
            }
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

struct ChangePasswordView: View {
    @Environment(AppState.self) private var state
    @State private var current = ""
    @State private var new = ""
    @State private var repeated = ""
    @State private var action = ActionState()

    private var tooShort: Bool { !new.isEmpty && new.count < 12 }
    private var mismatch: Bool { !repeated.isEmpty && repeated != new }
    private var canSubmit: Bool { !current.isEmpty && new.count >= 12 && new == repeated && !action.isRunning }

    var body: some View {
        Form {
            Section {
                Text("Bitte wähle ein neues Passwort. Es braucht mindestens 12 Zeichen, Regeln für Zeichen gibt es nicht.")
            } header: {
                Text("Neues Passwort").accessibilityAddTraits(.isHeader)
            }
            Section {
                SecureField("Aktuelles Passwort", text: $current)
                    .textContentType(.password)
                    .frame(minHeight: 44)
                SecureField("Neues Passwort", text: $new)
                    .textContentType(.newPassword)
                    .frame(minHeight: 44)
                SecureField("Neues Passwort wiederholen", text: $repeated)
                    .textContentType(.newPassword)
                    .frame(minHeight: 44)
            }
            if tooShort { Section { ErrorRow(text: String(localized: "Das neue Passwort muss mindestens 12 Zeichen haben.")) } }
            if mismatch { Section { ErrorRow(text: String(localized: "Die beiden neuen Passwörter sind nicht gleich.")) } }
            if let error = action.error {
                Section { ErrorRow(text: error) }
            }
            Section {
                Button {
                    Task {
                        await action.perform(message: AuthMessages.changePassword) {
                            try await state.passwordChanged(current: current, new: new)
                        }
                    }
                } label: {
                    HStack {
                        Text("Passwort ändern")
                        if action.isRunning { ProgressView() }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(!canSubmit)
                Button("Abmelden", role: .destructive) {
                    Task { await state.signOut() }
                }
                .frame(minHeight: 44)
            }
        }
    }
}

struct PrivacyView: View {
    @Environment(AppState.self) private var state
    @Environment(\.appConfiguration) private var configuration
    @State private var action = ActionState()
    @State private var isPageOpen = false

    var body: some View {
        let url = ServerPage.privacy.url(base: configuration.apiBaseURL)
        Form {
            Section {
                Text("Bevor es losgeht, lies bitte die Datenschutzerklärung. Sie sagt, welche Daten die App verwendet und wer sie sieht.")
            } header: {
                Text("Datenschutz").accessibilityAddTraits(.isHeader)
            }
            Section {
                Button("Datenschutzerklärung lesen") { isPageOpen = true }
                    .frame(minHeight: 44)
                    .disabled(url == nil)
            }
            if let error = action.error {
                Section { ErrorRow(text: error) }
            }
            Section {
                Button {
                    Task { await action.perform { try await state.privacyAcknowledged() } }
                } label: {
                    HStack {
                        Text("Ich habe die Datenschutzerklärung gelesen")
                        if action.isRunning { ProgressView() }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(action.isRunning)
                Button("Abmelden", role: .destructive) {
                    Task { await state.signOut() }
                }
                .frame(minHeight: 44)
            }
        }
        .fullScreenCover(isPresented: $isPageOpen) {
            if let url { SafariView(url: url).ignoresSafeArea() }
        }
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
        VStack(spacing: 24) {
            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .accessibilityHidden(true)
            Text("Cevi OS ist gesperrt")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            if lock.failed {
                ErrorRow(text: String(localized: "Das Entsperren hat nicht geklappt."))
            }
            Button("Entsperren") { Task { await lock.unlock() } }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
        }
        .padding()
        .task { await lock.unlock() }
    }
}

/// Leaders and unit leaders see no data without a device code.
struct DeviceCodeMissingView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Geräte-Code einrichten")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("Als Leitung siehst du Daten von Kindern. Dafür braucht dein iPhone einen Geräte-Code. Ohne ihn zeigt Cevi OS nichts an.")
                Text("So richtest du ihn ein: Öffne die Einstellungen, tippe auf «Face ID & Code» (oder «Touch ID & Code») und dann auf «Code aktivieren». Danach öffnest du Cevi OS wieder.")
            }
            .padding()
        }
    }
}

/// No connection at launch.
struct OfflineView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 16) {
            Text("Keine Verbindung zum Server. Bitte später nochmals versuchen.")
                .multilineTextAlignment(.center)
            Button("Nochmals versuchen") { Task { await state.start() } }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
        }
        .padding()
    }
}
