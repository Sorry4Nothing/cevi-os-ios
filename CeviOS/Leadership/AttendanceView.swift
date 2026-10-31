import SwiftUI

@MainActor @Observable
final class AttendanceModel {
    private(set) var overview: AttendanceOverview?
    private(set) var error: String?
    private(set) var saving: Set<UUID> = []
    var actionError: String?

    func load(unitId: UUID, client: APIClient?) async {
        guard let client else { return }
        do {
            overview = try await client.attendance(unitId: unitId)
            error = nil
        } catch is CancellationError {
        } catch let apiError as APIError {
            error = LeadershipMessages.message(for: apiError).text
        } catch {
            self.error = APIError.network.displayText
        }
    }

    /// `present == nil` takes the entry back. Reloads afterwards, so the numbers come from the server.
    func set(person: UUID, isChild: Bool, present: Bool?, unitId: UUID, programId: UUID, client: APIClient?) async {
        guard let client, !saving.contains(person) else { return }
        saving.insert(person)
        actionError = nil
        defer { saving.remove(person) }
        do {
            if isChild {
                try await client.setChildPresence(unitId: unitId, programId: programId, childId: person, present: present)
            } else {
                try await client.setLeaderPresence(unitId: unitId, programId: programId, userId: person, present: present)
            }
            await load(unitId: unitId, client: client)
        } catch let apiError as APIError {
            let message = LeadershipMessages.message(for: apiError)
            actionError = message.text
            if message.reload { await load(unitId: unitId, client: client) }
        } catch {
            actionError = APIError.network.displayText
        }
    }
}

/// Attendance of one unit at one event. The answer of the parents stays separate from who was there.
struct AttendanceView: View {
    @Environment(AppState.self) private var appState
    let unit: UnitSummary
    @State private var model = AttendanceModel()
    @State private var selectedEvent: UUID?

    var body: some View {
        Group {
            if let overview = model.overview {
                content(overview)
            } else if let error = model.error {
                ErrorRow(text: error).padding()
            } else {
                ProgressView().accessibilityLabel(Text("Lädt"))
            }
        }
        .navigationTitle(unit.name)
        .task { await model.load(unitId: unit.id, client: appState.client) }
    }

    private func content(_ overview: AttendanceOverview) -> some View {
        let events = overview.events
        let index = events.firstIndex { $0.id == selectedEvent } ?? max(events.lastIndex { $0.isPast } ?? 0, 0)
        return List {
            if events.isEmpty {
                Text("Noch keine Programme.")
            } else {
                Section {
                    Picker("Programm", selection: Binding(get: { events[index].id }, set: { selectedEvent = $0 })) {
                        ForEach(events) { event in Text(event.title).tag(event.id) }
                    }
                    if !events[index].isRecordable {
                        Text("Die Anwesenheit lässt sich erst nach Beginn des Programms und bis 14 Tage danach erfassen.").font(.callout)
                    }
                }
                if let error = model.actionError { Section { ErrorRow(text: error) } }
                Section("Kinder") {
                    quota(overview.totals.children)
                    ForEach(overview.children) { child in
                        row(name: "\(child.firstName) \(child.lastName)", rows: child.rows, index: index,
                            event: events[index], person: child.id, isChild: true, overview: overview)
                    }
                }
                Section("Leitende") {
                    quota(overview.totals.leaders)
                    ForEach(overview.leaders) { leader in
                        row(name: leader.ceviName.map { "\(leader.name) (\($0))" } ?? leader.name, rows: leader.rows, index: index,
                            event: events[index], person: leader.id, isChild: false, overview: overview)
                    }
                }
            }
        }
        .refreshable { await model.load(unitId: unit.id, client: appState.client) }
    }

    private func quota(_ quota: AttendanceQuota) -> some View {
        let percent = quota.percent.map { " (\($0) %)" } ?? ""
        return Text("Anwesend: \(quota.present) von \(quota.of)\(percent)").font(.headline)
    }

    private func row(
        name: String, rows: AttendanceRows, index: Int, event: AttendanceEvent, person: UUID, isChild: Bool, overview: AttendanceOverview
    ) -> some View {
        let presence = rows.attendance.indices.contains(index) ? rows.attendance[index] : nil
        let answer = rows.answers.indices.contains(index) ? rows.answers[index] : .open
        return VStack(alignment: .leading, spacing: 8) {
            Text(name).font(.headline)
            Text(answerText(answer)).font(.subheadline)
            if event.isRecordable {
                HStack {
                    presenceButton("Da", selected: presence == .present, person: person) { await set(person, isChild, present: presence == .present ? nil : true, event: event, overview: overview) }
                    presenceButton("Nicht da", selected: presence == .absent, person: person) { await set(person, isChild, present: presence == .absent ? nil : false, event: event, overview: overview) }
                }
            } else {
                Text(presenceText(presence)).font(.subheadline)
            }
        }
        .padding(.vertical, 4)
    }

    private func set(_ person: UUID, _ isChild: Bool, present: Bool?, event: AttendanceEvent, overview: AttendanceOverview) async {
        await model.set(person: person, isChild: isChild, present: present, unitId: overview.unit.id, programId: event.id, client: appState.client)
    }

    @ViewBuilder
    private func presenceButton(_ title: LocalizedStringKey, selected: Bool, person: UUID, action: @escaping () async -> Void) -> some View {
        Group {
            if selected {
                Button { Task { await action() } } label: { buttonLabel(title, selected: true) }.buttonStyle(.borderedProminent)
            } else {
                Button { Task { await action() } } label: { buttonLabel(title, selected: false) }.buttonStyle(.bordered)
            }
        }
        .disabled(model.saving.contains(person))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func buttonLabel(_ title: LocalizedStringKey, selected: Bool) -> some View {
        HStack {
            if selected { Image(systemName: "checkmark") }
            Text(title)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
    }

    private func answerText(_ answer: OverviewAnswer) -> String {
        switch answer {
        case .yes: String(localized: "Zusage: Ja")
        case .no: String(localized: "Zusage: Nein")
        case .open: String(localized: "Zusage: Offen")
        }
    }

    private func presenceText(_ presence: Presence?) -> String {
        switch presence {
        case .present: String(localized: "Da")
        case .absent: String(localized: "Nicht da")
        case nil: String(localized: "Nicht erfasst")
        }
    }
}

/// Entry for the attendance tab: the units the person leads (all units for admins).
struct AttendanceListView: View {
    let units: [UnitSummary]

    var body: some View {
        NavigationStack {
            List(units) { unit in
                NavigationLink(unit.name) { AttendanceView(unit: unit) }.frame(minHeight: 44)
            }
            .navigationTitle("Anwesenheit")
        }
    }
}
