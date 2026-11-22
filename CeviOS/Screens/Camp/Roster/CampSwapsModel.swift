import SwiftUI

/// The shift plan with the days and sections it needs: what the swaps and the plan screen read together.
nonisolated struct CampShiftContext: Equatable, Sendable {
    var plan: CampShiftPlan
    var days: [CampDay]
    var sections: [CampDaySection]

    /// `requireSchedule` false: a missing schedule leaves days and sections empty (the swaps still read).
    static func load(client: APIClient, campId: UUID, requireSchedule: Bool) async throws -> CampShiftContext {
        async let plan = client.campShiftPlan(campId: campId)
        if requireSchedule {
            let schedule = try await client.campSchedule(campId: campId)
            return CampShiftContext(plan: try await plan, days: schedule.campDays, sections: schedule.sections)
        }
        let schedule = try? await client.campSchedule(campId: campId)
        return CampShiftContext(plan: try await plan, days: schedule?.campDays ?? [], sections: schedule?.sections ?? [])
    }

    func shift(_ id: UUID) -> CampShift? { plan.shifts.first { $0.id == id } }
    func duty(_ id: UUID) -> CampDuty? { plan.duties.first { $0.id == id } }
    func section(_ id: UUID) -> CampDaySection? { sections.first { $0.id == id } }

    /// The name of a team member the plan knows (from a shift or the statistics), else `nil`.
    func personName(_ id: UUID) -> String? {
        plan.shifts.first { $0.personId == id }.map { CampRosterText.label(name: $0.name, ceviName: $0.ceviName) }
            ?? plan.statistics.first { $0.personId == id }.map(\.name)
    }

    /// «Küche Montag».
    func dutyDay(_ shift: CampShift) -> String {
        [duty(shift.dutyId)?.name, CampRosterText.weekday(shift.date)].compactMap { $0 }.joined(separator: " ")
    }

    /// «Küche Montag Frühstück».
    func title(_ shift: CampShift) -> String {
        [dutyDay(shift), section(shift.sectionId)?.name].compactMap { $0 }.joined(separator: " ")
    }
}

/// L24: the swap requests. The camp leadership decides; everybody else sees and withdraws the own requests.
@MainActor @Observable
final class CampSwapsModel: CampRosterModel {
    struct Row: Equatable, Identifiable {
        let id: UUID
        let swap: CampShiftSwap
        let title: String
        let text: String
        let second: String?
        /// «gestern 21:10» once decided.
        let stamp: String?
        let canDecide: Bool
        let canWithdraw: Bool

        var status: CampSwapStatus { swap.status }
    }

    /// The person who uses the app (their requests, «Du»).
    let personId: UUID
    var swaps: [CampShiftSwap] = []
    var context: CampShiftContext?

    init(active: ActiveCamp, personId: UUID) {
        self.personId = personId
        super.init(active: active)
    }

    var rows: [Row] {
        guard let context else { return [] }
        return swaps.sorted { ($0.status == .open ? 0 : 1, $1.createdAt) < ($1.status == .open ? 0 : 1, $0.createdAt) }.map { row($0, context) }
    }

    /// The own shifts that have no open request yet.
    var requestable: [CampShift] {
        guard let context else { return [] }
        let asked = Set(swaps.filter { $0.status == .open }.map(\.shiftId))
        return context.plan.shifts.filter { $0.personId == personId && !asked.contains($0.id) }.sorted { ($0.date, $0.id.uuidString) < ($1.date, $1.id.uuidString) }
    }

    override func load() async {
        guard let client = active.client, let campId = active.camp?.id else { return }
        do {
            let seesAll = rights.seesAllSwaps
            async let loadedContext = CampShiftContext.load(client: client, campId: campId, requireSchedule: false)
            var all: [CampShiftSwap] = []
            if seesAll {
                var cursor: UUID?
                repeat {
                    let page = try await client.campShiftSwaps(campId: campId, after: cursor, limit: 100)
                    all += page.swaps
                    cursor = page.next
                } while cursor != nil && all.count < 1000
            } else {
                all = try await client.ownCampShiftSwaps(campId: campId)
            }
            context = try await loadedContext
            swaps = all
            loaded()
        } catch is CancellationError {
        } catch {
            failLoad(error, hasContent: !swaps.isEmpty)
        }
    }

    private func name(_ id: UUID?, context: CampShiftContext) -> String {
        guard let id else { return CampRosterText.unknownPerson }
        return context.personName(id) ?? CampRosterText.unknownPerson
    }

    private func row(_ swap: CampShiftSwap, _ context: CampShiftContext) -> Row {
        let shift = context.shift(swap.shiftId)
        let other = swap.withShiftId.flatMap(context.shift)
        let mine = swap.fromPersonId == personId
        let from = mine ? String(localized: "Du") : (shift.map { CampRosterText.label(name: $0.name, ceviName: $0.ceviName) } ?? name(swap.fromPersonId, context: context))
        let duty = shift.map(context.dutyDay) ?? String(localized: "einen Dienst")
        let withMe = swap.withPersonId == personId
        let with = withMe ? String(localized: "dir") : (swap.withPersonId.map { name($0, context: context) } ?? CampRosterText.unknownPerson)
        var second: String?
        let text: String
        switch swap.status {
        case .open:
            if swap.withPersonId != nil {
                text = mine ? String(localized: "Du möchtest \(duty) mit \(with) tauschen.") : String(localized: "\(from) möchte \(duty) mit \(with) tauschen.")
                if let other { second = withMe ? String(localized: "Du machst dafür \(context.dutyDay(other)).") : String(localized: "\(with) macht dafür \(context.dutyDay(other)).") }
            } else {
                text = mine ? String(localized: "Du suchst Ersatz für \(duty).") : String(localized: "\(from) sucht Ersatz für \(duty).")
            }
        case .accepted:
            text = swap.withPersonId != nil
                ? (mine ? String(localized: "Du hast mit \(with) getauscht.") : String(localized: "\(from) hat mit \(with) getauscht."))
                : String(localized: "Der Tausch wurde angenommen.")
        case .rejected: text = String(localized: "Die Anfrage wurde abgelehnt.")
        case .withdrawn: text = String(localized: "Die Anfrage wurde zurückgezogen.")
        }
        let open = swap.status == .open
        return Row(id: swap.id, swap: swap, title: shift.map(context.title) ?? String(localized: "Diensttausch"), text: text, second: second,
                   stamp: swap.decidedAt.map { CampRosterText.stamp($0, now: now()) },
                   canDecide: open && rights.decidesSwaps && swap.withPersonId != nil, canWithdraw: open && mine && rights.requestsSwaps)
    }

    /// An open request without a person asked needs someone to take it: the app has no member list for that (B1), so it can only be declined.
    func canReject(_ row: Row) -> Bool { row.swap.status == .open && rights.decidesSwaps }

    func decide(_ row: Row, _ decision: CampSwapDecision) async {
        guard rights.decidesSwaps, row.swap.status == .open, let context else { return }
        let body = CampShiftSwapDecide(decision: decision, version: row.swap.version, withPersonId: nil)
        guard await writeVersioned(as: CampShiftSwap.self, { try await $0.decideCampShiftSwap(campId: $1, swapId: row.id, body) }) != nil else { return }
        if decision == .accepted {
            let with = name(row.swap.withPersonId, context: context)
            show(Notice(title: String(localized: "Tausch angenommen."), message: String(localized: "\(with) macht jetzt \(row.title).")))
        } else {
            show(Notice(title: String(localized: "Anfrage abgelehnt.")))
        }
        await load()
    }

    func withdraw(_ row: Row) async {
        guard rights.requestsSwaps, row.swap.status == .open, row.swap.fromPersonId == personId else { return }
        guard await writeVersioned(as: CampShiftSwap.self, { try await $0.withdrawCampShiftSwap(campId: $1, swapId: row.id, version: row.swap.version) }) != nil else { return }
        show(Notice(title: String(localized: "Anfrage zurückgezogen.")))
        await load()
    }

    /// Asks for a swap of an own shift; whoever takes it is decided by the camp leadership.
    func request(_ shift: CampShift, note: String) async -> Bool {
        guard rights.requestsSwaps, shift.personId == personId else { return false }
        let body = CampShiftSwapCreate(shiftId: shift.id, withShiftId: nil, withPersonId: nil, note: CampRosterText.trimmed(note))
        guard await write({ try await $0.requestCampShiftSwap(campId: $1, body) }) != nil else { return false }
        show(Notice(title: String(localized: "Anfrage gesendet."), message: String(localized: "Die Lagerleitung entscheidet.")))
        await load()
        return true
    }
}
