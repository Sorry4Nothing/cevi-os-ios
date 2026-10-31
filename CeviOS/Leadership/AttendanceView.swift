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
    @State private var showsLeaders = false

    var body: some View {
        Group {
            if let overview = model.overview {
                content(overview)
            } else if let error = model.error {
                ErrorRow(text: error).padding()
            } else {
                LoadingView(label: "Lädt")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ceviScreenBackground()
        .navigationTitle(unit.name)
        .task { await model.load(unitId: unit.id, client: appState.client) }
    }

    private func content(_ overview: AttendanceOverview) -> some View {
        let events = overview.events
        let index = events.firstIndex { $0.id == selectedEvent } ?? max(events.lastIndex { $0.isPast } ?? 0, 0)
        return ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                if events.isEmpty {
                    Text("Noch keine Programme.").foregroundStyle(Color.ceviOnSurfaceVariant)
                } else {
                    VStack(alignment: .leading, spacing: Spacing.s2) {
                        Picker("Programm", selection: Binding(get: { events[index].id }, set: { selectedEvent = $0 })) {
                            ForEach(events) { event in Text(event.title).tag(event.id) }
                        }
                        .pickerStyle(.menu)
                        .frame(minHeight: Size.touchTarget)
                        if !events[index].isRecordable {
                            Text("Die Anwesenheit lässt sich erst nach Beginn des Programms und bis 14 Tage danach erfassen.")
                                .font(.callout)
                                .foregroundStyle(Color.ceviOnSurfaceVariant)
                        }
                    }
                    Picker("Gruppe", selection: $showsLeaders) {
                        Text("Kinder").tag(false)
                        Text("Leitende").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(minHeight: Size.touchTarget)
                    if let error = model.actionError { ErrorRow(text: error) }
                    if showsLeaders {
                        quota(overview.totals.leaders)
                        ForEach(overview.leaders) { leader in
                            row(name: leader.ceviName.map { "\(leader.name) (\($0))" } ?? leader.name, rows: leader.rows, index: index,
                                event: events[index], person: leader.id, isChild: false, overview: overview)
                        }
                    } else {
                        quota(overview.totals.children)
                        ForEach(overview.children) { child in
                            row(name: "\(child.firstName) \(child.lastName)", rows: child.rows, index: index,
                                event: events[index], person: child.id, isChild: true, overview: overview)
                        }
                    }
                }
            }
            .padding(Spacing.s4)
            .frame(maxWidth: Size.contentMax)
            .frame(maxWidth: .infinity)
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
        return VStack(alignment: .leading, spacing: Spacing.s3) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s2) {
                Text(name).font(.title(.cardTitle)).frame(maxWidth: .infinity, alignment: .leading)
                Text("\(rows.quota.present)/\(rows.quota.of)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.ceviOnSurfaceVariant)
                    .accessibilityLabel(Text("\(rows.quota.present) von \(rows.quota.of) Anlässen da"))
            }
            HStack(spacing: Spacing.s2) {
                Text("Zusage").font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
                AnswerChip(answer: answer)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(answerText(answer)))
            if event.isRecordable {
                ViewThatFits {
                    HStack(spacing: Spacing.s2) { presenceButtons(presence, person, isChild, event, overview) }
                    VStack(spacing: Spacing.s2) { presenceButtons(presence, person, isChild, event, overview) }
                }
            } else {
                PresenceChip(presence: presence)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ceviCard()
    }

    @ViewBuilder
    private func presenceButtons(_ presence: Presence?, _ person: UUID, _ isChild: Bool, _ event: AttendanceEvent, _ overview: AttendanceOverview) -> some View {
        presenceButton("Da", symbol: "checkmark", selected: presence == .present, person: person) {
            await set(person, isChild, present: presence == .present ? nil : true, event: event, overview: overview)
        }
        presenceButton("Nicht da", symbol: "xmark", selected: presence == .absent, person: person) {
            await set(person, isChild, present: presence == .absent ? nil : false, event: event, overview: overview)
        }
    }

    private func set(_ person: UUID, _ isChild: Bool, present: Bool?, event: AttendanceEvent, overview: AttendanceOverview) async {
        await model.set(person: person, isChild: isChild, present: present, unitId: overview.unit.id, programId: event.id, client: appState.client)
    }

    private func presenceButton(
        _ title: LocalizedStringKey, symbol: String, selected: Bool, person: UUID, action: @escaping () async -> Void
    ) -> some View {
        Button { Task { await action() } } label: {
            Label(title, systemImage: selected ? "\(symbol).circle.fill" : "circle")
                .font(.body.weight(.semibold))
                .foregroundStyle(selected ? Color.ceviOnSecondary : Color.ceviOnSurface)
                .padding(.horizontal, Spacing.s3)
                .frame(maxWidth: .infinity, minHeight: Size.touchTarget)
                .background(selected ? Color.ceviSecondary : Color.clear, in: Capsule())
                .overlay { if !selected { Capsule().strokeBorder(Color.ceviOutline, lineWidth: Size.border) } }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(model.saving.contains(person))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func answerText(_ answer: OverviewAnswer) -> String {
        switch answer {
        case .yes: String(localized: "Zusage: Ja")
        case .no: String(localized: "Zusage: Nein")
        case .open: String(localized: "Zusage: Offen")
        }
    }
}

/// Recorded presence as chip: symbol and word.
private struct PresenceChip: View {
    let presence: Presence?

    var body: some View {
        let (title, symbol, foreground, background): (LocalizedStringKey, String, Color, Color) = switch presence {
        case .present: ("Da", "checkmark", .ceviOnSuccessContainer, .ceviSuccessContainer)
        case .absent: ("Nicht da", "xmark", .ceviOnErrorContainer, .ceviErrorContainer)
        case nil: ("Nicht erfasst", "circle.dashed", .ceviOnSurfaceVariant, .clear)
        }
        Label(title, systemImage: symbol)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, Spacing.s3)
            .padding(.vertical, Spacing.s1)
            .background(background, in: Capsule())
            .overlay { if presence == nil { Capsule().strokeBorder(Color.ceviOutline, lineWidth: Size.border) } }
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

#Preview {
    NavigationStack { AttendanceView(unit: UnitSummary(id: UUID(), name: "Jungschar", abbreviation: "JS")) }.environment(AppState())
}
