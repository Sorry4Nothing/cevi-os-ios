import SafariServices
import SwiftUI

/// Öffentliche Seiten des Servers (ohne Anmeldung).
nonisolated enum ServerSeite: String {
    case datenschutz = "/datenschutz"
    case support = "/support"
    case kontoLoeschen = "/konto-loeschen"

    func url(basis: URL?) -> URL? {
        basis.flatMap { URL(string: $0.absoluteString + rawValue) }
    }
}

/// Fehlerzeile mit Symbol und Text, nicht nur Farbe.
struct FehlerZeile: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(Color.fehler)
            .font(.callout)
            .accessibilityLabel(Text("Fehler: \(text)"))
    }
}

/// Führt eine Aktion aus und zeigt deren Fehler. Verhindert Doppeltipps.
@MainActor @Observable
final class AktionsZustand {
    var laeuft = false
    var fehler: String?

    func ausfuehren(meldung: (APIFehler) -> String = { $0.anzeigetext }, _ aktion: () async throws -> Void) async {
        guard !laeuft else { return }
        laeuft = true
        fehler = nil
        defer { laeuft = false }
        do {
            try await aktion()
        } catch let fehler as APIFehler {
            self.fehler = meldung(fehler)
        } catch is CancellationError {
        } catch {
            fehler = APIFehler.netzwerk.anzeigetext
        }
    }
}

struct AnmeldungAnsicht: View {
    @Environment(AppZustand.self) private var zustand
    @Environment(\.appKonfiguration) private var konfiguration
    @State private var benutzername = ""
    @State private var passwort = ""
    @State private var aktion = AktionsZustand()
    @FocusState private var fokus: Feld?

    private enum Feld { case benutzername, passwort }

    var body: some View {
        Form {
            Section {
                Text("Cevi OS")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                    .listRowBackground(Color.clear)
            }
            Section {
                // Beschriftung über dem Feld statt Platzhalter: Platzhaltertext hat zu wenig Kontrast.
                VStack(alignment: .leading, spacing: 4) {
                    Text("Benutzername").font(.subheadline)
                    TextField("", text: $benutzername)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($fokus, equals: .benutzername)
                        .submitLabel(.next)
                        .onSubmit { fokus = .passwort }
                        .accessibilityLabel(Text("Benutzername"))
                }
                .frame(minHeight: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Passwort").font(.subheadline)
                    SecureField("", text: $passwort)
                        .textContentType(.password)
                        .focused($fokus, equals: .passwort)
                        .submitLabel(.go)
                        .onSubmit(anmelden)
                        .accessibilityLabel(Text("Passwort"))
                }
                .frame(minHeight: 44)
            }
            if let fehler = aktion.fehler {
                Section { FehlerZeile(text: fehler) }
            }
            Section {
                Button(action: anmelden) {
                    HStack {
                        Text("Anmelden")
                        if aktion.laeuft { ProgressView() }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(aktion.laeuft)
            }
            Section {
                if let url = ServerSeite.support.url(basis: konfiguration.apiBasisURL) {
                    Link("Hilfe und Kontakt", destination: url).frame(minHeight: 44)
                }
            }
        }
    }

    private func anmelden() {
        guard !aktion.laeuft else { return }
        guard !benutzername.isEmpty, !passwort.isEmpty else {
            aktion.fehler = String(localized: "Bitte Benutzername und Passwort eingeben.")
            return
        }
        Task {
            await aktion.ausfuehren { try await zustand.anmelden(benutzername: benutzername, passwort: passwort) }
            if aktion.fehler != nil { passwort = "" }
        }
    }
}

struct ZweiterFaktorAnsicht: View {
    @Environment(AppZustand.self) private var zustand
    @State private var code = ""
    @State private var ersatzcode = false
    @State private var aktion = AktionsZustand()

    private var kannSenden: Bool {
        !aktion.laeuft && (ersatzcode ? code.count == 11 : code.count == 6)
    }

    var body: some View {
        Form {
            Section {
                Text(ersatzcode
                    ? "Gib einen deiner Ersatzcodes ein (Format xxxxx-xxxxx). Jeder Code gilt nur einmal."
                    : "Gib den 6-stelligen Code aus deiner Authenticator-App ein.")
            } header: {
                Text("Zweiter Faktor").accessibilityAddTraits(.isHeader)
            }
            Section {
                TextField(ersatzcode ? "Ersatzcode" : "Code", text: $code)
                    .keyboardType(ersatzcode ? .asciiCapable : .numberPad)
                    .textContentType(.oneTimeCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .frame(minHeight: 44)
                    .onChange(of: code) { _, neu in
                        code = String(neu.prefix(ersatzcode ? 11 : 6))
                    }
                Toggle("Ersatzcode verwenden", isOn: $ersatzcode)
                    .frame(minHeight: 44)
                    .onChange(of: ersatzcode) { code = "" }
            }
            if let fehler = aktion.fehler {
                Section { FehlerZeile(text: fehler) }
            }
            Section {
                Button {
                    senden()
                } label: {
                    HStack {
                        Text("Bestätigen")
                        if aktion.laeuft { ProgressView() }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(!kannSenden)
                Button("Abbrechen", role: .cancel) {
                    Task { await zustand.neuAnmelden() }
                }
                .frame(minHeight: 44)
            }
        }
    }

    private func senden() {
        Task {
            var neuAnmelden = false
            await aktion.ausfuehren(meldung: { fehler in
                let meldung = AuthMeldungen.zweiterFaktor(fehler)
                neuAnmelden = meldung.neuAnmelden
                return meldung.text
            }) {
                try await zustand.zweitenFaktorBestaetigen(code: code, ersatzcode: ersatzcode)
            }
            if neuAnmelden { await zustand.neuAnmelden() }
            if aktion.fehler != nil { code = "" }
        }
    }
}

struct PasswortAendernAnsicht: View {
    @Environment(AppZustand.self) private var zustand
    @State private var aktuell = ""
    @State private var neu = ""
    @State private var wiederholt = ""
    @State private var aktion = AktionsZustand()

    private var zuKurz: Bool { !neu.isEmpty && neu.count < 12 }
    private var ungleich: Bool { !wiederholt.isEmpty && wiederholt != neu }
    private var kannSenden: Bool { !aktuell.isEmpty && neu.count >= 12 && neu == wiederholt && !aktion.laeuft }

    var body: some View {
        Form {
            Section {
                Text("Bitte wähle ein neues Passwort. Es braucht mindestens 12 Zeichen, Regeln für Zeichen gibt es nicht.")
            } header: {
                Text("Neues Passwort").accessibilityAddTraits(.isHeader)
            }
            Section {
                SecureField("Aktuelles Passwort", text: $aktuell)
                    .textContentType(.password)
                    .frame(minHeight: 44)
                SecureField("Neues Passwort", text: $neu)
                    .textContentType(.newPassword)
                    .frame(minHeight: 44)
                SecureField("Neues Passwort wiederholen", text: $wiederholt)
                    .textContentType(.newPassword)
                    .frame(minHeight: 44)
            }
            if zuKurz { Section { FehlerZeile(text: String(localized: "Das neue Passwort muss mindestens 12 Zeichen haben.")) } }
            if ungleich { Section { FehlerZeile(text: String(localized: "Die beiden neuen Passwörter sind nicht gleich.")) } }
            if let fehler = aktion.fehler {
                Section { FehlerZeile(text: fehler) }
            }
            Section {
                Button {
                    Task {
                        await aktion.ausfuehren(meldung: AuthMeldungen.passwortAendern) {
                            try await zustand.passwortGeaendert(aktuell: aktuell, neu: neu)
                        }
                    }
                } label: {
                    HStack {
                        Text("Passwort ändern")
                        if aktion.laeuft { ProgressView() }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(!kannSenden)
                Button("Abmelden", role: .destructive) {
                    Task { await zustand.abmelden() }
                }
                .frame(minHeight: 44)
            }
        }
    }
}

struct DatenschutzAnsicht: View {
    @Environment(AppZustand.self) private var zustand
    @Environment(\.appKonfiguration) private var konfiguration
    @State private var aktion = AktionsZustand()
    @State private var seiteOffen = false

    var body: some View {
        let url = ServerSeite.datenschutz.url(basis: konfiguration.apiBasisURL)
        Form {
            Section {
                Text("Bevor es losgeht, lies bitte die Datenschutzerklärung. Sie sagt, welche Daten die App verwendet und wer sie sieht.")
            } header: {
                Text("Datenschutz").accessibilityAddTraits(.isHeader)
            }
            Section {
                Button("Datenschutzerklärung lesen") { seiteOffen = true }
                    .frame(minHeight: 44)
                    .disabled(url == nil)
            }
            if let fehler = aktion.fehler {
                Section { FehlerZeile(text: fehler) }
            }
            Section {
                Button {
                    Task { await aktion.ausfuehren { try await zustand.datenschutzBestaetigt() } }
                } label: {
                    HStack {
                        Text("Ich habe die Datenschutzerklärung gelesen")
                        if aktion.laeuft { ProgressView() }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(aktion.laeuft)
                Button("Abmelden", role: .destructive) {
                    Task { await zustand.abmelden() }
                }
                .frame(minHeight: 44)
            }
        }
        .fullScreenCover(isPresented: $seiteOffen) {
            if let url { SafariAnsicht(url: url).ignoresSafeArea() }
        }
    }
}

struct SafariAnsicht: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

/// Gesperrt: Entsperren mit Face ID, Touch ID oder Geräte-Code.
struct SperreAnsicht: View {
    @Environment(AppSperre.self) private var sperre

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .accessibilityHidden(true)
            Text("Cevi OS ist gesperrt")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            if sperre.fehlgeschlagen {
                FehlerZeile(text: String(localized: "Das Entsperren hat nicht geklappt."))
            }
            Button("Entsperren") { Task { await sperre.entsperren() } }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
        }
        .padding()
        .task { await sperre.entsperren() }
    }
}

/// Leitende und Stufenleitung sehen ohne Geräte-Code keine Daten.
struct GeraeteCodeFehltAnsicht: View {
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

/// Keine Verbindung beim Start.
struct OfflineAnsicht: View {
    @Environment(AppZustand.self) private var zustand

    var body: some View {
        VStack(spacing: 16) {
            Text("Keine Verbindung zum Server. Bitte später nochmals versuchen.")
                .multilineTextAlignment(.center)
            Button("Nochmals versuchen") { Task { await zustand.starten() } }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
        }
        .padding()
    }
}
