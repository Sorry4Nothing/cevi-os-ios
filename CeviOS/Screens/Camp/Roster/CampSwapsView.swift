import SwiftUI

/// Root of L24 inside a navigation stack: creates the model for the open camp.
struct CampSwapsView: View {
    let personId: UUID
    @Environment(ActiveCamp.self) private var active
    @State private var model: CampSwapsModel?

    var body: some View {
        Group { if let model { CampSwapsScreen(model: model) } else { Color.clear } }
            .task {
                guard model == nil else { return }
                let created = CampSwapsModel(active: active, personId: personId)
                model = created
                await created.load()
            }
    }
}

/// L24: «Diensttausch».
struct CampSwapsScreen: View {
    @Bindable var model: CampSwapsModel
    @Environment(\.dismiss) private var dismiss
    @State private var showsRequest = false

    var body: some View {
        CampPhaseView(phase: model.phase, loading: "Diensttausch wird geladen", back: .init(title: "Zurück") { dismiss() }, retry: { Task { await model.load() } }) {
            CampScroll(staleSince: model.staleSince, error: model.error, notice: model.noticeData(), refresh: { await model.load() }) { content }
        }
        .navigationTitle("Diensttausch")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if model.rights.requestsSwaps, !model.requestable.isEmpty, model.phase == .loaded {
                ToolbarItem(placement: .topBarTrailing) { Button("Tausch anfragen", systemImage: "arrow.left.arrow.right") { showsRequest = true } }
            }
        }
        .sheet(isPresented: $showsRequest) { CampSwapRequestSheet(model: model) { showsRequest = false } }
    }

    @ViewBuilder private var content: some View {
        if model.rights.isLockedByRole {
            CampRoleHint(title: "Die Lagerleitung entscheidet.", message: "Du siehst hier deine Anfragen und ihren Stand.")
        }
        if model.rows.isEmpty {
            StateView(symbol: "arrow.left.arrow.right", title: "Keine Anfragen", message: "Diensttausch-Anfragen erscheinen hier.").frame(minHeight: 320)
        }
        ForEach(model.rows) { card($0) }
    }

    private func card(_ row: CampSwapsModel.Row) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.title).font(.title(.cardTitle)).foregroundStyle(Color.ceviOnSurface).accessibilityAddTraits(.isHeader)
                Spacer(minLength: Spacing.s2)
                statusChip(row.status)
            }
            Text(row.text).foregroundStyle(Color.ceviOnSurface)
            if let second = row.second { Text(second).font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant) }
            if let stamp = row.stamp { Text(stamp).font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant) }
            if row.canDecide || model.canReject(row) || row.canWithdraw {
                FlowLayout(spacing: Spacing.s2) {
                    if row.canDecide {
                        Button { Task { await model.decide(row, .accepted) } } label: { Label("Annehmen", systemImage: "checkmark") }
                            .buttonStyle(CeviPrimaryButtonStyle(expands: false))
                    }
                    if model.canReject(row) {
                        Button { Task { await model.decide(row, .rejected) } } label: { Label("Ablehnen", systemImage: "xmark") }.buttonStyle(.ceviText)
                    }
                    if row.canWithdraw {
                        Button { Task { await model.withdraw(row) } } label: { Label("Zurückziehen", systemImage: "arrow.uturn.backward") }.buttonStyle(.ceviText)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ceviCard()
        .accessibilityElement(children: .contain)
    }

    private func statusChip(_ status: CampSwapStatus) -> some View {
        switch status {
        case .open: CampCountChip(text: String(localized: "Offen"), symbol: "questionmark.circle")
        case .accepted: CampCountChip(text: String(localized: "Angenommen"), symbol: "checkmark", tone: .good)
        case .rejected: CampCountChip(text: String(localized: "Abgelehnt"), symbol: "xmark", tone: .warning)
        case .withdrawn: CampCountChip(text: String(localized: "Zurückgezogen"), symbol: "arrow.uturn.backward")
        }
    }
}

/// «Tausch anfragen»: pick an own shift and say why. The camp leadership decides who takes it.
struct CampSwapRequestSheet: View {
    @Bindable var model: CampSwapsModel
    let close: () -> Void
    @State private var selected: UUID?
    @State private var note = ""

    var body: some View {
        NavigationStack {
            List {
                if let error = model.error { ErrorRow(text: error).listRowBackground(Color.clear) }
                Section("Welchen Dienst willst du tauschen?") {
                    ForEach(model.requestable) { shift in
                        let title = model.context?.title(shift) ?? CampRosterText.weekday(shift.date)
                        Button { selected = shift.id } label: {
                            HStack {
                                Image(systemName: selected == shift.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected == shift.id ? Color.ceviAccent : Color.ceviOnSurfaceVariant).accessibilityHidden(true)
                                Text(title).foregroundStyle(Color.ceviOnSurface)
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: Size.touchTarget).contentShape(.rect)
                        }
                        .accessibilityAddTraits(selected == shift.id ? .isSelected : [])
                    }
                }
                Section { TextField("Notiz (freiwillig)", text: $note, axis: .vertical) }
            }
            .scrollContentBackground(.hidden)
            .ceviScreenBackground()
            .navigationTitle("Tausch anfragen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Abbrechen", action: close) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Anfragen") {
                        guard let shift = model.requestable.first(where: { $0.id == selected }) else { return }
                        Task { if await model.request(shift, note: note) { close() } }
                    }
                    .disabled(selected == nil)
                }
            }
        }
    }
}

#if DEBUG
#Preview("L24 Normal") { CampRosterPreview.swaps() }
#Preview("L24 Nacht") { CampRosterPreview.swaps().preferredColorScheme(.dark) }
#Preview("L24 Laden") { CampRosterPreview.swaps(phase: .loading) }
#Preview("L24 Leer") { CampRosterPreview.swaps(empty: true) }
#Preview("L24 Fehler") { CampRosterPreview.swaps(phase: .failed(state: nil, text: "x")) }
#Preview("L24 Fehler beim Speichern") { CampRosterPreview.swaps(error: "Das hat nicht geklappt. Deine Eingabe ist noch da. Versuche es nochmals.") }
#Preview("L24 Erfolg") { CampRosterPreview.swaps(notice: .init(title: "Tausch angenommen.", message: "Lea macht jetzt Küche Montag Frühstück.")) }
#Preview("L24 Nur eigene (Team)") { CampRosterPreview.swaps(role: .team) }
#Preview("L24 Textgrösse AX3") { CampRosterPreview.swaps().dynamicTypeSize(.accessibility3) }
#endif
