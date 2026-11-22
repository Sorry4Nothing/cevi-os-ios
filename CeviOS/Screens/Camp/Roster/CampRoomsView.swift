import SwiftUI

/// Root of L20 inside a navigation stack: creates the model for the open camp.
struct CampRoomsView: View {
    @Environment(ActiveCamp.self) private var active
    @State private var model: CampRoomsModel?

    var body: some View {
        Group { if let model { CampRoomsScreen(model: model) } else { Color.clear } }
            .task {
                guard model == nil else { return }
                let created = CampRoomsModel(active: active)
                model = created
                await created.load()
            }
    }
}

/// L20: «Zimmer und Zelte» with the occupancy and «Person zuweisen».
struct CampRoomsScreen: View {
    @Bindable var model: CampRoomsModel
    @Environment(\.dismiss) private var dismiss
    /// The room the picker is open for; `Optional.some(nil)` is the picker opened from «Nicht eingeteilt».
    @State private var assigning: UUID??
    @State private var targetRoom: UUID?

    var body: some View {
        CampPhaseView(phase: model.phase, loading: "Zimmer und Zelte wird geladen", back: .init(title: "Zurück") { dismiss() }, retry: { Task { await model.load() } }) {
            CampScroll(staleSince: model.staleSince, error: model.error, notice: model.noticeData(), refresh: { await model.load() }) { content }
        }
        .navigationTitle("Zimmer und Zelte")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: .init(get: { assigning != nil }, set: { if !$0 { assigning = nil } })) { picker }
    }

    @ViewBuilder private var content: some View {
        if model.rows.isEmpty {
            StateView(symbol: "bed.double", title: "Noch keine Zimmer", message: "Lege Zimmer und Zelte an und teile die Personen ein.").frame(minHeight: 320)
        } else {
            if model.rights.isLockedByRole { CampRoleHint(title: "Nur lesen.", message: "Die Einteilung macht die Lagerleitung.") }
            if model.rights.placesPeople, model.openCount > 0 { openBanner }
            ForEach(model.rows) { card($0) }
        }
    }

    private var openBanner: some View {
        Button { open(nil) } label: {
            HStack {
                Label("Nicht eingeteilt: \(model.openCount)", systemImage: "person.crop.circle.badge.questionmark").font(.headline)
                Spacer(minLength: Spacing.s2)
                Image(systemName: "chevron.right").font(.footnote.bold()).accessibilityHidden(true)
            }
            .foregroundStyle(Color.ceviOnWarningContainer)
            .frame(maxWidth: .infinity, minHeight: Size.touchTarget, alignment: .leading)
            .padding(.horizontal, Spacing.s4)
            .background(Color.ceviWarningContainer, in: Radius.shape(Radius.md))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(model.openCount == 1 ? "1 Person ist nicht eingeteilt" : "\(model.openCount) Personen sind nicht eingeteilt"))
        .accessibilityHint(Text("Öffnet die Auswahl"))
    }

    private func card(_ row: CampRoomsModel.Row) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.name).font(.title(.cardTitle)).foregroundStyle(Color.ceviOnSurface).accessibilityAddTraits(.isHeader)
                Spacer(minLength: Spacing.s2)
                chip(row)
            }
            if !row.detail.isEmpty { Text(row.detail).font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant) }
            CampPeopleLine(names: row.members.map(\.name))
            if model.rights.placesPeople {
                HStack(spacing: Spacing.s2) {
                    Button { open(row.id) } label: { Label("Person zuweisen", systemImage: "plus") }.buttonStyle(.ceviText)
                    if !row.members.isEmpty {
                        Menu {
                            ForEach(row.members.filter { $0.kind != .unknown }) { member in
                                Button("\(member.name) herausnehmen", systemImage: "minus.circle") { Task { await model.remove(member, from: row.id) } }
                            }
                        } label: { Label("Herausnehmen", systemImage: "minus.circle") }
                            .frame(minHeight: Size.touchTarget)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ceviCard()
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func chip(_ row: CampRoomsModel.Row) -> some View {
        if let places = row.places, let occupied = row.occupied {
            if row.overbooked {
                CampCountChip(text: String(localized: "Überbelegt \(CampRosterText.occupancy(occupied, of: places))"), symbol: "exclamationmark.triangle", tone: .warning)
                    .accessibilityLabel(Text("Überbelegt, \(CampRosterText.occupancySpoken(occupied, of: places))"))
            } else if row.isFull {
                CampCountChip(text: String(localized: "Voll"), symbol: "checkmark", tone: .good)
                    .accessibilityLabel(Text("Voll, \(CampRosterText.occupancySpoken(occupied, of: places))"))
            } else {
                CampCountChip(text: CampRosterText.occupancy(occupied, of: places))
                    .accessibilityLabel(Text(CampRosterText.occupancySpoken(occupied, of: places)))
            }
        }
    }

    private func open(_ roomId: UUID?) {
        targetRoom = roomId ?? model.rows.first?.id
        assigning = .some(roomId)
        Task { await model.loadOpenPeople() }
    }

    private var picker: some View {
        CampPersonPicker(title: "Person zuweisen", confirmTitle: "Zuweisen", model: model,
                         header: {
                             Picker("In", selection: $targetRoom) { ForEach(model.rows) { Text($0.name).tag(Optional($0.id)) } }
                                 .frame(minHeight: Size.touchTarget)
                         },
                         confirm: { people in
                             let room = targetRoom
                             assigning = nil
                             if let room { Task { await model.place(people, in: room) } }
                         },
                         close: { assigning = nil })
    }
}

#if DEBUG
#Preview("L20 Normal") { CampRosterPreview.rooms() }
#Preview("L20 Nacht") { CampRosterPreview.rooms().preferredColorScheme(.dark) }
#Preview("L20 Laden") { CampRosterPreview.rooms(phase: .loading) }
#Preview("L20 Leer") { CampRosterPreview.rooms(empty: true) }
#Preview("L20 Fehler") { CampRosterPreview.rooms(phase: .failed(state: nil, text: "x")) }
#Preview("L20 Ohne Netz") { CampRosterPreview.rooms(offline: true) }
#Preview("L20 Fehler beim Speichern") { CampRosterPreview.rooms(error: "Das hat nicht geklappt. Deine Eingabe ist noch da. Versuche es nochmals.") }
#Preview("L20 Nur lesen (Leitung)") { CampRosterPreview.rooms(role: .leader) }
#Preview("L20 Team (nur Namen)") { CampRosterPreview.rooms(role: .team) }
#Preview("L20 Lager abgeschlossen") { CampRosterPreview.rooms(status: "abgeschlossen") }
#Preview("L20 Textgrösse AX3") { CampRosterPreview.rooms().dynamicTypeSize(.accessibility3) }
#endif
