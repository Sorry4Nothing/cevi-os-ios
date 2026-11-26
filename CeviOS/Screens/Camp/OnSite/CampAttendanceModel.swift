import SwiftUI

/// L26: attendance. The camp leadership sees and sets the whole matrix; the team sees the own row and asks for a change
/// of a field that is set already (or after the deadline); the camp leadership decides.
@MainActor @Observable
final class CampAttendanceModel: CampRosterModel {
    struct Cell: Equatable, Identifiable {
        let sectionId: UUID
        let name: String
        let time: String?
        let value: CampAttendanceValue
        /// The value an open request of the person asks for.
        let requested: CampAttendanceValue?

        var id: UUID { sectionId }
    }

    struct Row: Equatable, Identifiable {
        let id: UUID
        let label: String
        let cells: [Cell]

        var isWholeDayPresent: Bool { !cells.isEmpty && cells.allSatisfy { $0.value == .present } }
    }

    /// An open request the camp leadership decides on.
    struct OpenRequest: Equatable, Identifiable {
        let id: UUID
        let version: Int
        let text: String
        let note: String?
    }

    /// A change that needs a request: the dialog «Anfrage an die Lagerleitung nötig» asks before it is sent.
    struct PendingRequest: Equatable {
        let fields: [CampAttendanceField]
        let message: String
    }

    let personId: UUID
    /// The own name, for the own row.
    let ownLabel: String
    var days: [CampDay] = []
    var sections: [CampDaySection] = []
    var selectedDayId: UUID?
    var entries: [CampAttendanceEntry] = []
    var requests: [CampAttendanceRequest] = []
    var deadline: Date?
    /// The people of the matrix (leadership view): id and label.
    var people: [CampPersonChoice] = []
    var pending: PendingRequest?
    /// The row that is being written («Aktion läuft»).
    var busyId: UUID?

    init(active: ActiveCamp, personId: UUID, ownLabel: String) {
        self.personId = personId
        self.ownLabel = ownLabel
        super.init(active: active)
    }

    /// The camp leadership writes through the matrix route, everybody else through the own route.
    private var usesMatrix: Bool { onSite.readsMatrix }

    var canSet: Bool { onSite.setsAttendance }

    var selectedDay: CampDay? { days.first { $0.id == selectedDayId } }

    var orderedSections: [CampDaySection] { sections.sorted { ($0.order, $0.name) < ($1.order, $1.name) } }

    var rows: [Row] {
        guard let day = selectedDay else { return [] }
        let list = usesMatrix ? people : [CampPersonChoice(id: personId, isParticipant: false, label: ownLabel)]
        return list.map { person in
            Row(id: person.id, label: person.label, cells: orderedSections.map { section in
                let entry = entries.first { $0.personId == person.id && $0.dayId == day.id && $0.sectionId == section.id }
                let asked = requests.first { $0.personId == person.id && $0.dayId == day.id && $0.sectionId == section.id && $0.status == .open }
                return Cell(sectionId: section.id, name: section.name, time: section.time, value: entry?.value ?? .open, requested: asked?.value)
            })
        }
    }

    /// The open requests of the whole team (leadership), as sentences.
    var openRequests: [OpenRequest] {
        guard usesMatrix else { return [] }
        return requests.filter { $0.status == .open }.sorted { $0.createdAt < $1.createdAt }.map { request in
            let who = personName(request.personId)
            let day = days.first { $0.id == request.dayId }.map { CampRosterText.weekday($0.date) } ?? String(localized: "einen Tag")
            let section = sections.first { $0.id == request.sectionId }?.name ?? String(localized: "einen Abschnitt")
            let text = String(localized: "\(who) möchte \(day) \(section) auf «\(CampOnSiteText.value(request.value))» ändern.")
            return OpenRequest(id: request.id, version: request.version, text: text, note: CampRosterText.trimmed(request.note))
        }
    }

    /// The own open requests as lines under the own row.
    var ownRequestLines: [String] {
        guard !usesMatrix else { return [] }
        return requests.filter { $0.status == .open }.map { request in
            let day = days.first { $0.id == request.dayId }.map { CampRosterText.weekday($0.date) } ?? ""
            let section = sections.first { $0.id == request.sectionId }?.name ?? ""
            return String(localized: "Anfrage offen: \(day) \(section), \(CampOnSiteText.value(request.value))")
        }
    }

    /// Until when the person sets the own fields without a request; leadership sets always.
    var deadlineHint: String? {
        guard !usesMatrix, let deadline else { return nil }
        return String(localized: "Du kannst deine Zusage bis \(CampCommsText.day(deadline)) selbst ändern.")
    }

    func personName(_ id: UUID) -> String { people.first { $0.id == id }?.label ?? CampRosterText.unknownPerson }

    func select(_ dayId: UUID) async {
        selectedDayId = dayId
        await load()
    }

    override func load() async {
        guard let client = active.client, let campId = active.camp?.id else { return }
        do {
            await active.loadMemberNames()
            if days.isEmpty {
                let schedule = try await client.campSchedule(campId: campId)
                days = schedule.campDays.sorted { $0.date < $1.date }
                sections = schedule.sections
            }
            if selectedDayId == nil || selectedDay == nil {
                selectedDayId = (days.first { CampTaskText.days(from: $0.date, to: now()) == 0 } ?? days.first)?.id
            }
            guard let dayId = selectedDayId else { loaded(); return }
            if usesMatrix {
                async let team = Self.teamPeople(client, campId)
                async let open = client.campAttendanceRequests(campId: campId, status: .open, limit: 100)
                let page = try await client.campAttendance(campId: campId, dayIds: [dayId])
                entries = page.entries
                deadline = page.deadline
                requests = (try? await open.requests) ?? requests
                people = Self.merged(await team, entries: page.entries, names: active.memberNames)
            } else {
                let own = try await client.ownCampAttendance(campId: campId)
                entries = own.entries
                requests = own.requests
                deadline = own.deadline
            }
            loaded()
        } catch is CancellationError {
        } catch {
            failLoad(error, hasContent: !entries.isEmpty || !days.isEmpty)
        }
    }

    /// The team members with their names, from the counting list (the only list of members a non-admin may read).
    private static func teamPeople(_ client: APIClient, _ campId: UUID) async -> [CampPersonChoice] {
        var all: [CampCountEntry] = []
        var cursor: UUID?
        do {
            repeat {
                let page = try await client.campCount(campId: campId, filter: CampCountFilter(kind: .team), after: cursor, limit: 100)
                all += page.entries
                cursor = page.next
            } while cursor != nil && all.count < 500
        } catch { return [] }
        return all.compactMap { entry in
            guard let id = entry.personId else { return nil }
            let name = entry.name ?? CampRosterText.fullName(first: entry.firstName, last: entry.lastName)
            return CampPersonChoice(id: id, isParticipant: false, label: CampRosterText.label(name: name, ceviName: entry.ceviName))
        }
    }

    /// People without a name in the list (the list failed or is stale) still show up with a neutral label.
    static func merged(_ named: [CampPersonChoice], entries: [CampAttendanceEntry], names: [UUID: String] = [:]) -> [CampPersonChoice] {
        var result = named
        for id in entries.compactMap(\.personId) where !result.contains(where: { $0.id == id }) {
            result.append(CampPersonChoice(id: id, isParticipant: false, label: names[id] ?? CampRosterText.unknownPerson))
        }
        return result
    }

    // MARK: Writing

    /// One field: «Da» or «Frei» for one section of the selected day.
    func set(_ row: Row, section: UUID, to value: CampAttendanceValue) async {
        guard let day = selectedDay else { return }
        await setFields(of: row, [CampAttendanceField(dayId: day.id, sectionId: section, value: value)])
    }

    /// «Ganzer Tag da»: one tap, the same value for every section.
    func setWholeDay(_ row: Row, to value: CampAttendanceValue = .present) async {
        guard let day = selectedDay else { return }
        await setFields(of: row, CampAttendanceField.wholeDay(day.id, sectionIds: orderedSections.map(\.id), value: value))
    }

    private func setFields(of row: Row, _ fields: [CampAttendanceField]) async {
        guard canSet, let client = active.client, let campId = active.camp?.id, !fields.isEmpty else { return }
        busyId = row.id
        defer { busyId = nil }
        do {
            let written: [CampAttendanceEntry]
            if usesMatrix {
                let leaderFields = fields.map { field in
                    CampAttendanceLeaderField(personId: row.id, dayId: field.dayId, sectionId: field.sectionId, value: field.value,
                                              version: entries.first { $0.personId == row.id && $0.dayId == field.dayId && $0.sectionId == field.sectionId }?.version)
                }
                written = try await BusyState.shared.track { try await client.setCampAttendance(campId: campId, leaderFields) }
            } else {
                written = try await BusyState.shared.track { try await client.setOwnCampAttendance(campId: campId, fields) }
            }
            error = nil
            merge(written)
        } catch let failure as APIError {
            await handle(failure, fields: fields)
        } catch {
            self.error = APIError.network.displayText
        }
    }

    private func merge(_ written: [CampAttendanceEntry]) {
        for entry in written {
            if let index = entries.firstIndex(where: { $0.id == entry.id }) { entries[index] = entry } else { entries.append(entry) }
        }
    }

    private func handle(_ failure: APIError, fields: [CampAttendanceField]) async {
        if let blocked = CampRules.attendanceBlocked(failure), !blocked.isEmpty {
            let asked = fields.filter { field in blocked.contains { $0.dayId == field.dayId && $0.sectionId == field.sectionId } }
            let reason = blocked.first?.reason
            let day = selectedDay.map { CampRosterText.weekday($0.date) } ?? String(localized: "diesen Tag")
            let message = reason == .deadline
                ? String(localized: "Die Frist ist abgelaufen. Die Lagerleitung muss die Änderung für \(day) bestätigen.")
                : String(localized: "Du hast für \(day) schon etwas eingetragen. Die Lagerleitung muss die Änderung bestätigen.")
            pending = PendingRequest(fields: asked, message: message)
        } else if CampRules.versionConflict(failure, as: CampAttendanceEntry.self) != nil {
            error = String(localized: "Jemand hat das gerade geändert. Die Liste wird neu geladen.")
            await load()
        } else {
            error = failure.kind == .invalidInput ? failure.displayText : CampRules.writeError(failure)
        }
    }

    func cancelRequest() { pending = nil }

    /// «Anfrage senden»: step 1 of a change. The camp leadership decides.
    func sendRequest(note: String?) async {
        guard let pending, let client = active.client, let campId = active.camp?.id else { return }
        self.pending = nil
        let text = CampRosterText.trimmed(note)
        do {
            let created = try await BusyState.shared.track { try await client.requestCampAttendanceChange(campId: campId, pending.fields, note: text) }
            requests += created
            error = nil
            show(Notice(title: String(localized: "Anfrage gesendet."), message: String(localized: "Die Lagerleitung entscheidet.")))
        } catch let failure as APIError {
            error = failure.kind == .invalidInput ? failure.displayText : CampRules.writeError(failure)
        } catch {
            self.error = APIError.network.displayText
        }
    }

    /// The camp leadership accepts or rejects one open request.
    func decide(_ request: OpenRequest, _ decision: CampAttendanceDecisionKind) async {
        guard onSite.decidesRequests else { return }
        guard await writeVersioned(as: CampAttendanceRequest.self, { client, campId in
            try await client.decideCampAttendanceRequests(campId: campId, decision, requests: [CampVersionRef(id: request.id, version: request.version)])
        }) != nil else { return }
        show(Notice(title: decision == .accepted ? String(localized: "Anfrage angenommen.") : String(localized: "Anfrage abgelehnt."), message: nil))
        await load()
    }
}
