import SwiftUI

/// Root of L21 inside a navigation stack: creates the model for the open camp.
struct CampTripsView: View {
    @Environment(ActiveCamp.self) private var active
    @State private var model: CampTripsModel?

    var body: some View {
        Group { if let model { CampTripsScreen(model: model) } else { Color.clear } }
            .task {
                guard model == nil else { return }
                let created = CampTripsModel(active: active)
                model = created
                await created.load()
            }
    }
}

/// L21: «Fahrten», Hinfahrt and Rückfahrt.
struct CampTripsScreen: View {
    @Bindable var model: CampTripsModel
    @Environment(\.dismiss) private var dismiss
    @State private var assigning: UUID?

    var body: some View {
        CampPhaseView(phase: model.phase, loading: "Fahrten werden geladen", back: .init(title: "Zurück") { dismiss() }, retry: { Task { await model.load() } }) {
            CampScroll(staleSince: model.staleSince, error: model.error, notice: model.noticeData(), refresh: { await model.load() }) { content }
        }
        .navigationTitle("Fahrten")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: .init(get: { assigning != nil }, set: { if !$0 { assigning = nil } })) {
            CampPersonPicker(title: "Person zuweisen", confirmTitle: "Zuweisen", model: model, confirm: { people in
                if let trip = assigning { Task { await model.board(people, on: trip) } }
                assigning = nil
            }, close: { assigning = nil })
        }
    }

    @ViewBuilder private var content: some View {
        if model.trips.isEmpty {
            StateView(symbol: "car", title: "Noch keine Fahrten", message: "Lege Hin- und Rückfahrt an.").frame(minHeight: 320)
        } else {
            Picker("Richtung", selection: $model.direction) {
                Text("Hinfahrt").tag(CampTripDirection.outbound)
                Text("Rückfahrt").tag(CampTripDirection.inbound)
            }
            .pickerStyle(.segmented)
            if model.rights.isLockedByRole { CampRoleHint(title: "Nur lesen.", message: "Die Fahrten teilt die Lagerleitung ein.") }
            ForEach(model.visible) { card($0) }
        }
    }

    private func card(_ trip: CampTrip) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text(CampTripText.title(trip)).font(.title(.cardTitle)).foregroundStyle(Color.ceviOnSurface).accessibilityAddTraits(.isHeader)
                Spacer(minLength: Spacing.s2)
                if trip.overbooked {
                    CampCountChip(text: String(localized: "Überbelegt \(CampTripText.count(trip))"), symbol: "exclamationmark.triangle", tone: .warning)
                } else {
                    CampCountChip(text: CampTripText.count(trip))
                }
            }
            Group {
                if let departure = CampTripText.departure(trip) { Text(departure) }
                if let point = CampRosterText.trimmed(trip.meetingPoint) { Text("Treffpunkt \(point)") }
            }
            .font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
            if let url = CampTripText.link(trip) {
                Link(destination: url) { Label("Fahrplan öffnen", systemImage: "tram").underline() }.frame(minHeight: Size.touchTarget)
            }
            CampPeopleLine(names: trip.passengers.map(\.name))
            if model.rights.placesPeople {
                HStack(spacing: Spacing.s2) {
                    Button { assigning = trip.id; Task { await model.loadPeopleWithoutTrip() } } label: { Label("Person zuweisen", systemImage: "plus") }
                        .buttonStyle(.ceviText)
                    if !trip.passengers.isEmpty {
                        Menu {
                            ForEach(trip.passengers) { passenger in
                                Button("\(passenger.name) herausnehmen", systemImage: "minus.circle") { Task { await model.remove(passenger, from: trip.id) } }
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
}

#if DEBUG
#Preview("L21 Normal") { CampRosterPreview.trips() }
#Preview("L21 Nacht") { CampRosterPreview.trips().preferredColorScheme(.dark) }
#Preview("L21 Laden") { CampRosterPreview.trips(phase: .loading) }
#Preview("L21 Leer") { CampRosterPreview.trips(empty: true) }
#Preview("L21 Fehler") { CampRosterPreview.trips(phase: .failed(state: nil, text: "x")) }
#Preview("L21 Ohne Netz") { CampRosterPreview.trips(offline: true) }
#Preview("L21 Fehler beim Speichern") { CampRosterPreview.trips(error: "Das hat nicht geklappt. Deine Eingabe ist noch da. Versuche es nochmals.") }
#Preview("L21 Nur lesen (Team)") { CampRosterPreview.trips(role: .team) }
#Preview("L21 Lager abgeschlossen") { CampRosterPreview.trips(status: "abgeschlossen") }
#Preview("L21 Textgrösse AX3") { CampRosterPreview.trips().dynamicTypeSize(.accessibility3) }
#endif
