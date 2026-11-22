import SwiftUI

nonisolated enum CampMeetingRoute: Hashable {
    case agenda(UUID)
    case mode(UUID)
    case minutes(UUID)
}

/// Root of L11 inside a navigation stack: creates the model for the open camp.
struct CampMeetingsView: View {
    @Environment(ActiveCamp.self) private var active
    @State private var model: CampMeetingsModel?

    var body: some View {
        Group {
            if let model { CampMeetingsScreen(model: model) } else { Color.clear }
        }
        .task {
            guard model == nil else { return }
            let created = CampMeetingsModel(active: active)
            model = created
            await created.load()
        }
    }
}

/// L11: the meetings, coming and past. Opens the agenda (L12), from there the meeting mode (L14) and the protocol (L13).
struct CampMeetingsScreen: View {
    @Bindable var model: CampMeetingsModel
    @Environment(ActiveCamp.self) private var active
    @Environment(\.dismiss) private var dismiss
    @State private var showsForm = false
    @State private var draft = CampMeetingsModel.Draft()
    @State private var deleting: CampMeetingsModel.Row?

    var body: some View {
        CampPhaseView(phase: model.phase, loading: "Hoecks werden geladen", back: .init(title: "Zurück") { dismiss() }, retry: { Task { await model.load() } }) {
            CampScroll(staleSince: model.staleSince, error: model.error, refresh: { await model.load() }) { content }
                .safeAreaInset(edge: .bottom) { if model.rights.editsMeetings { CampMainAction(title: "Neuer Hoeck") { draft = .init(); showsForm = true } } }
        }
        .navigationTitle("Hoecks")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: CampMeetingRoute.self) { route in
            switch route {
            case .agenda(let id): CampAgendaView(active: active, meetingId: id)
            case .mode(let id): CampMeetingModeView(active: active, meetingId: id)
            case .minutes(let id): CampProtocolView(active: active, meetingId: id)
            }
        }
        .sheet(isPresented: $showsForm) {
            CampMeetingForm(model: model, draft: $draft, hasTemplate: model.latest != nil) { showsForm = false }
        }
        .confirmationDialog("Hoeck löschen?", isPresented: .init(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Löschen", role: .destructive) { if let deleting { Task { await model.delete(deleting) } } }
        } message: { Text("Der Hoeck verschwindet für alle.") }
    }

    @ViewBuilder private var content: some View {
        if model.rows.isEmpty {
            StateView(symbol: "calendar", title: "Noch kein Hoeck",
                      message: model.rights.editsMeetings ? "Plane den ersten Hoeck mit «Neuer Hoeck»." : "Hier erscheinen die Hoecks des Lagers.")
                .frame(minHeight: 320)
        } else {
            section("Kommend", model.upcoming)
            section("Vergangen", model.past)
        }
    }

    @ViewBuilder private func section(_ title: LocalizedStringKey, _ rows: [CampMeetingsModel.Row]) -> some View {
        if !rows.isEmpty {
            Text(title).font(.headline).foregroundStyle(Color.ceviOnSurfaceVariant).accessibilityAddTraits(.isHeader).padding(.top, Spacing.s2)
            ForEach(rows) { row in
                if model.rights.seesAllMeetings { NavigationLink(value: CampMeetingRoute.agenda(row.id)) { card(row) }.buttonStyle(.plain) } else { card(row) }
            }
        }
    }

    private func card(_ row: CampMeetingsModel.Row) -> some View {
        let when = CampCommsText.meetingDate(row.date, time: row.time)
        let detail = [row.place, row.agendaCount.map(CampCommsText.agendaCount)].compactMap { $0 }.joined(separator: ", ")
        return HStack(alignment: .top, spacing: Spacing.s2) {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(row.title).font(.headline).foregroundStyle(Color.ceviOnSurface)
                Text(when).font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
                if !detail.isEmpty { Text(detail).font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant) }
                if row.protocolId != nil { CampStatusChip(text: String(localized: "Protokoll"), symbol: "doc.text") }
            }
            Spacer(minLength: Spacing.s2)
            if model.rights.seesAllMeetings { Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(Color.ceviOnSurfaceVariant).accessibilityHidden(true) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ceviCard()
        .contextMenu { if model.rights.editsMeetings { Button("Löschen", systemImage: "trash", role: .destructive) { deleting = row } } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(row.title), \(when)\(detail.isEmpty ? "" : ", \(detail)")\(row.protocolId != nil ? ", mit Protokoll" : "")"))
        .accessibilityAddTraits(model.rights.seesAllMeetings ? .isButton : [])
        .accessibilityActions { if model.rights.editsMeetings { Button("Löschen") { deleting = row } } }
    }
}

/// «Neuer Hoeck», with «Wie der letzte» as a quiet button.
struct CampMeetingForm: View {
    let model: CampMeetingsModel
    @Binding var draft: CampMeetingsModel.Draft
    let hasTemplate: Bool
    let close: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                if let error = model.inputError { ErrorRow(text: error).listRowBackground(Color.clear) }
                if hasTemplate {
                    Button("Wie der letzte", systemImage: "doc.on.doc") { if let like = model.draftLikeLatest() { draft = like } }
                        .frame(minHeight: Size.touchTarget)
                }
                TextField("Titel", text: $draft.title)
                Picker("Art", selection: $draft.kind) {
                    Text("Lagerleitung").tag(CampMeetingKind.campLeadership)
                    Text("Team").tag(CampMeetingKind.team)
                }
                DatePicker("Datum", selection: $draft.date, displayedComponents: .date)
                    .environment(\.calendar, DateFormats.calendar).environment(\.timeZone, DateFormats.timeZone)
                TextField("Zeit, zum Beispiel 19:30", text: $draft.time).keyboardType(.numbersAndPunctuation)
                TextField("Ort", text: $draft.place)
            }
            .scrollContentBackground(.hidden)
            .ceviScreenBackground()
            .navigationTitle("Neuer Hoeck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Abbrechen", action: close) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Anlegen") { Task { if await model.create(draft) { close() } } }
                }
            }
        }
    }
}

#if DEBUG
#Preview("L11 Normal") { CampCommsPreview.meetings() }
#Preview("L11 Nacht") { CampCommsPreview.meetings().preferredColorScheme(.dark) }
#Preview("L11 Laden") { CampCommsPreview.meetings(phase: .loading) }
#Preview("L11 Leer") { CampCommsPreview.meetings(empty: true) }
#Preview("L11 Fehler") { CampCommsPreview.meetings(phase: .failed(state: nil, text: "x")) }
#Preview("L11 Ohne Netz") { CampCommsPreview.meetings(offline: true, waiting: 0) }
#Preview("L11 Lager abgeschlossen") { CampCommsPreview.meetings(status: "abgeschlossen") }
#Preview("L11 Team (nur Kurzform)") { CampCommsPreview.meetings(role: .team) }
#Preview("L11 Textgrösse AX3") { CampCommsPreview.meetings().dynamicTypeSize(.accessibility3) }
#endif
