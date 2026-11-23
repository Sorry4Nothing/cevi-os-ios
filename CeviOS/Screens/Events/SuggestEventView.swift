import SwiftUI

/// K1 Termin vorschlagen. The department leadership decides; nothing appears in the calendar before.
struct SuggestEventView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var scrolledTo: String?
    @State private var model = SuggestEventModel()

    var body: some View {
        content
            .ceviScreenBackground()
            .navigationTitle("Termin vorschlagen")
            .navigationBarTitleDisplayMode(.large)
            .task { await model.load(client: appState.client) }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            LoadingView(label: "Wird geladen")
        case .failed(let text, let isOffline):
            LoadFailureView(error: text, isOffline: isOffline) { Task { await model.load(client: appState.client) } }
        case .noRight:
            StateView(symbol: "lock", title: "Kein Vorschlag möglich",
                      message: "Termine vorschlagen dürfen nur Personen mit einer Funktion. Frag die Abteilungsleitung.",
                      primary: .toPrograms { dismiss() })
        case .ready:
            if model.sent != nil { result } else { form }
        }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                Group {
                    if let error = model.saveError, model.errors.isEmpty {
                        saveError(error)
                    } else if !model.errors.isEmpty {
                        InfoBanner(tone: .error, title: String(localized: "Prüfe deine Eingaben."),
                                   message: String(localized: "Ein Feld braucht noch eine Angabe."))
                    } else {
                        InfoBanner(tone: .info, title: String(localized: "Die Abteilungsleitung prüft deinen Vorschlag."),
                                   message: String(localized: "Erst nach der Freigabe erscheint er im Kalender."))
                    }
                }
                .id("banner")
                EventTextField(label: "Titel", accessibility: String(localized: "Titel"), text: $model.title)
                if let text = model.errors.title { FieldError(text: text) }
                DateTimeFields(date: $model.date, start: $model.start, end: $model.end)
                if let text = model.errors.time { FieldError(text: text) }
                EventTextField(label: "Ort", accessibility: String(localized: "Ort"), text: $model.place)
                groups
                EventTextField(label: "Beschreibung (optional)", accessibility: String(localized: "Beschreibung"), text: $model.details, multiline: true)
            }
            .scrollTargetLayout()
            .padding(.horizontal, Spacing.s4)
            .padding(.bottom, Spacing.s6)
            .frame(maxWidth: Size.contentMax)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollPosition(id: $scrolledTo, anchor: .top)
        // Sending fails at the bottom of a long form: bring the banner with the reason into view.
        .onChange(of: [model.saveError ?? "", model.errors.isEmpty ? "" : "x"]) { scrolledTo = nil; Task { scrolledTo = "banner" } }
        .formBar("Vorschlag senden", isEnabled: !model.action.isRunning) {
            Task { await model.send(client: appState.client) }
        }
    }

    private func saveError(_ text: String) -> some View {
        InfoBanner(tone: .error, title: String(localized: "Das hat nicht geklappt"),
                   message: "\(text) \(String(localized: "Deine Eingabe ist noch da. Versuche es nochmals."))") {
            Button("Nochmals versuchen") { Task { await model.send(client: appState.client) } }
                .buttonStyle(.ceviText)
        }
    }

    private var groups: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            FieldLabel("Gruppen").accessibilityAddTraits(.isHeader)
            FlowLayout(spacing: Spacing.s2) {
                ForEach(model.tags) { tag in
                    SelectableChip(title: tag.name, isSelected: model.selectedTags.contains(tag.id)) { model.toggle(tag) }
                }
            }
            if let text = model.errors.tags { FieldError(text: text) }
        }
    }

    private var result: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                InfoBanner(tone: .success, title: String(localized: "Gesendet."),
                           message: String(localized: "Du erfährst es, sobald die Leitung entschieden hat.")) {
                    Button("Rückgängig") { Task { await model.undo(client: appState.client) } }
                        .buttonStyle(.ceviText)
                        .disabled(model.action.isRunning)
                }
                if let error = model.action.error { ErrorRow(text: error) }
                if let sent = model.sent { summary(sent) }
            }
            .padding(.horizontal, Spacing.s4)
            .frame(maxWidth: Size.contentMax)
            .frame(maxWidth: .infinity)
        }
        .resultBar("Zu den Programmen") { dismiss() }
    }

    private func summary(_ sent: SuggestEventModel.Sent) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text(sent.title).font(.title(.cardTitle)).foregroundStyle(Color.ceviOnSurface)
                Spacer(minLength: Spacing.s2)
                RequestStatusChip(kind: .open)
            }
            Text(EventFormat.range(start: sent.start, end: sent.end)).foregroundStyle(Color.ceviOnSurfaceVariant)
            if let place = sent.place { Text(place).foregroundStyle(Color.ceviOnSurfaceVariant) }
            Text("Für \(sent.groups.formatted(.list(type: .and)))").foregroundStyle(Color.ceviOnSurfaceVariant)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ceviCard()
        .accessibilityElement(children: .combine)
    }
}
