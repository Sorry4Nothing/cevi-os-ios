import SwiftUI

/// T2: the shift plan as a list per day. People are placed with a choice (no dragging), «Leere Dienste füllen» is a suggestion.
@MainActor @Observable
final class CampShiftsModel: CampRosterModel {
    struct DutyRow: Identifiable, Equatable {
        let duty: CampDuty
        let section: CampDaySection?
        let shifts: [CampShift]
        let free: Int
        /// The whole sentence a screen reader says («Küche, Montag Vormittag, Pat Muster, noch ein Platz frei»).
        let sentence: String

        var id: UUID { duty.id }
        var isStaffed: Bool { shifts.count >= duty.minStaff }
        /// «2 von 2».
        var countText: String { CampRosterText.occupancy(shifts.count, of: duty.minStaff) }
        /// «Vormittag, 08:00–12:00».
        var when: String { [section?.name, section?.time].compactMap(CampRosterText.trimmed).joined(separator: ", ") }
    }

    /// The person who uses the app («Du»).
    let personId: UUID
    var context: CampShiftContext?
    var selectedDayId: UUID?
    /// The suggestion shown for confirmation (nothing is written yet).
    var proposal: CampShiftProposal?
    var options = CampShiftOptions()
    var isSuggesting = false

    init(active: ActiveCamp, personId: UUID) {
        self.personId = personId
        super.init(active: active)
    }

    var days: [CampDay] { (context?.days ?? []).sorted { $0.date < $1.date } }
    var selectedDay: CampDay? { days.first { $0.id == selectedDayId } ?? days.first }
    var isEmpty: Bool { context.map { $0.plan.duties.isEmpty || $0.days.isEmpty } ?? true }
    var statistics: [CampShiftStats] { (context?.plan.statistics ?? []).sorted { ($0.count, $1.name) > ($1.count, $0.name) } }
    var sections: [CampDaySection] { (context?.sections ?? []).sorted { $0.order < $1.order } }

    /// The duties of a day in the order of the sections.
    func rows(for day: CampDay) -> [DutyRow] {
        guard let context else { return [] }
        let duties = context.plan.duties.sorted {
            (context.section($0.sectionId)?.order ?? .max, $0.order, $0.name) < (context.section($1.sectionId)?.order ?? .max, $1.order, $1.name)
        }
        return duties.map { duty in
            let shifts = context.plan.shifts.filter { $0.dutyId == duty.id && $0.dayId == day.id }.sorted { $0.name < $1.name }
            let free = context.plan.freePlaces(duty: duty, dayId: day.id)
            let section = context.section(duty.sectionId)
            let sentence = CampShiftText.sentence(duty: duty.name, date: day.date, section: section?.name ?? "",
                                                  people: shifts.map(label), free: free)
            return DutyRow(duty: duty, section: section, shifts: shifts, free: free, sentence: sentence)
        }
    }

    /// «Du, Tim» for the own shift, else the name of the shift.
    func label(_ shift: CampShift) -> String { shift.personId == personId ? String(localized: "Du, \(shift.name)") : shift.name }

    override func load() async {
        guard let client = active.client, let campId = active.camp?.id else { return }
        do {
            let loadedContext = try await CampShiftContext.load(client: client, campId: campId, requireSchedule: true)
            context = loadedContext
            if !loadedContext.days.contains(where: { $0.id == selectedDayId }) {
                let today = DateFormats.calendar.startOfDay(for: now())
                selectedDayId = (days.first { DateFormats.calendar.startOfDay(for: $0.date) == today } ?? days.first)?.id
            }
            loaded()
        } catch is CancellationError {
        } catch {
            failLoad(error, hasContent: context != nil)
        }
    }

    // MARK: Placing people

    /// The people «Person wählen» offers: those the plan and the groups know by name, minus those already on the duty that day.
    func loadChoices(for row: DutyRow) async {
        let taken = Set(row.shifts.compactMap { $0.personId ?? $0.participantId })
        let known = context?.plan.statistics ?? []
        await loadChoices { client, campId in
            var result: [CampPersonChoice] = known.compactMap { stats in
                guard let id = stats.participantId ?? stats.personId else { return nil }
                return CampPersonChoice(id: id, isParticipant: stats.participantId != nil, label: CampRosterText.trimmed(stats.name) ?? CampRosterText.unknownPerson)
            }
            if let groups = try? await client.campGroups(campId: campId) {
                for person in groups.groups.flatMap(\.people) where !result.contains(where: { $0.id == person.id }) {
                    result.append(CampPersonChoice(id: person.id, isParticipant: false, label: CampRosterText.label(name: person.name, ceviName: person.ceviName)))
                }
            }
            return result.filter { !taken.contains($0.id) }.sorted { $0.label < $1.label }
        }
    }

    private func setStaff(_ shifts: [CampShift], added: [CampPersonChoice], dutyId: UUID, dayId: UUID) async -> Bool {
        let people = shifts.compactMap(\.personId) + added.filter { !$0.isParticipant }.map(\.id)
        let participants = shifts.compactMap(\.participantId) + added.filter(\.isParticipant).map(\.id)
        let body = CampShiftStaff(dayId: dayId, dutyId: dutyId, personIds: people, participantIds: participants)
        return await write({ try await $0.setCampShifts(campId: $1, body) }) != nil
    }

    func add(_ people: [CampPersonChoice], to row: DutyRow, day: CampDay) async {
        guard rights.editsShifts, !people.isEmpty else { return }
        guard await setStaff(row.shifts, added: people, dutyId: row.duty.id, dayId: day.id) else { return }
        let title = people.count == 1 ? String(localized: "\(people[0].label) macht \(row.duty.name).") : String(localized: "\(people.count) Personen eingeteilt.")
        show(Notice(title: title))
        await load()
    }

    func remove(_ shift: CampShift, from row: DutyRow, day: CampDay) async {
        guard rights.editsShifts else { return }
        guard await setStaff(row.shifts.filter { $0.id != shift.id }, added: [], dutyId: row.duty.id, dayId: day.id) else { return }
        show(Notice(title: String(localized: "\(shift.name) macht \(row.duty.name) nicht mehr.")))
        await load()
    }

    func createDuty(name: String, sectionId: UUID, minStaff: Int, night: Bool) async -> Bool {
        guard rights.editsShifts else { return false }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { error = String(localized: "Gib dem Dienst einen Namen."); return false }
        let body = CampDutyCreate(name: title, description: nil, minStaff: minStaff, night: night, sectionId: sectionId, order: nil)
        guard await write({ try await $0.createCampDuty(campId: $1, body) }) != nil else { return false }
        show(Notice(title: String(localized: "Dienst angelegt.")))
        await load()
        return true
    }

    // MARK: «Leere Dienste füllen»

    /// Step 1: a suggestion, nothing is written. Without a seed each call gives a new mix («Neu mischen»).
    func suggest() async {
        guard rights.editsShifts else { return }
        isSuggesting = true
        defer { isSuggesting = false }
        let options = options
        proposal = await write({ try await $0.suggestCampShifts(campId: $1, options: options) })
    }

    /// Step 2: writes the suggestion the person saw, with the same seed and options.
    func confirmProposal() async -> Bool {
        guard rights.editsShifts, let proposal else { return false }
        let options = options
        guard let result = await write({ try await $0.confirmCampShifts(campId: $1, proposal, options: options) }) else { return false }
        self.proposal = nil
        let changed = result.changed ?? proposal.shifts.count
        show(Notice(title: String(localized: "Dienste gefüllt."), message: changed == 1 ? String(localized: "1 Schicht eingeteilt.") : String(localized: "\(changed) Schichten eingeteilt.")))
        await load()
        return true
    }

    func cancelProposal() { proposal = nil }

    /// The suggestion as lines «Mo 17., Küche: Jonas, Sina» for the confirmation.
    var proposalLines: [String] {
        guard let proposal, let context else { return [] }
        let grouped = Dictionary(grouping: proposal.shifts) { "\($0.dayId)|\($0.dutyId)" }
        return grouped.values.sorted { ($0[0].date, $0[0].dutyId.uuidString) < ($1[0].date, $1[0].dutyId.uuidString) }.map { shifts in
            let duty = context.duty(shifts[0].dutyId)?.name ?? String(localized: "Dienst")
            return "\(CampRosterText.dayChip(shifts[0].date)), \(duty): \(shifts.map(\.name).sorted().joined(separator: ", "))"
        }
    }

    var proposalMissing: Int { proposal?.unfilled.reduce(0) { $0 + $1.missing } ?? 0 }
}
