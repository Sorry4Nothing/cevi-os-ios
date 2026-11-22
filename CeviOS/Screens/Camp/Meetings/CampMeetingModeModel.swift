import SwiftUI

/// L14: the meeting while it runs. Tick off who is there, go through the agenda and the round of portfolios.
@MainActor @Observable
final class CampMeetingModeModel {
    let active: ActiveCamp
    let meetingId: UUID
    @ObservationIgnored var now: () -> Date = { Date() }
    private(set) var phase: CampPhase = .loading
    private(set) var mode: CampMeetingMode?
    private(set) var staleSince: Date?
    private(set) var error: String?

    init(active: ActiveCamp, meetingId: UUID) {
        self.active = active
        self.meetingId = meetingId
    }

    var rights: CampCommsRights { CampCommsRights(role: active.role, readOnly: active.isReadOnly) }
    var members: [CampMeetingMember] { mode?.members ?? [] }
    var presentCount: Int { members.count { $0.present } }
    var agenda: [CampAgendaItem] { (mode?.meeting.agenda ?? []).sorted { $0.order < $1.order } }
    /// The round starts with the portfolios that have overdue tasks.
    var round: [CampPortfolioRound] {
        (mode?.portfolioRound ?? []).sorted { ($0.tasks?.overdue ?? 0) > ($1.tasks?.overdue ?? 0) }
    }

    func setPreview(phase: CampPhase, mode: CampMeetingMode?, offline: Bool = false, error: String? = nil) {
        self.phase = phase
        self.mode = mode
        self.error = error
        staleSince = offline ? now() : nil
    }

    func load() async {
        guard let client = active.client, let campId = active.camp?.id else { return }
        do {
            mode = try await client.campMeetingMode(campId: campId, meetingId: meetingId)
            phase = .loaded
            staleSince = nil
            error = nil
        } catch is CancellationError {
        } catch {
            let failure = CampPhase(error: error)
            if mode == nil { phase = failure } else {
                self.error = failure.failureText
                if case .failed(.offline?, _) = failure { staleSince = staleSince ?? now() }
            }
        }
    }

    static func name(_ member: CampMeetingMember) -> String { member.name ?? member.ceviName ?? String(localized: "Ohne Namen") }

    /// The tick. It shows at once and goes back if the server refuses.
    func togglePresent(_ member: CampMeetingMember) async {
        guard rights.editsMeetings, let current = mode, let client = active.client, let campId = active.camp?.id else { return }
        let present = !member.present
        set(member.id, present: present, in: current)
        let outcome = await CampCommsWrite.run {
            if present { try await client.markCampMeetingPresent(campId: campId, meetingId: meetingId, personId: member.id) }
            else { try await client.unmarkCampMeetingPresent(campId: campId, meetingId: meetingId, personId: member.id) }
        }
        switch outcome {
        case .done: error = nil
        case .invalid(let text), .failed(let text):
            if let mode { set(member.id, present: !present, in: mode) }
            error = text
        }
    }

    /// «Besprochen» on an agenda item.
    func toggleDiscussed(_ item: CampAgendaItem) async {
        guard rights.editsMeetings, let client = active.client, let campId = active.camp?.id else { return }
        var patch = CampAgendaItemPatch(version: item.version)
        patch.status = item.status == .discussed ? .open : .discussed
        switch await CampCommsWrite.run(as: CampAgendaItem.self, { try await client.updateCampAgendaItem(campId: campId, itemId: item.id, patch) }) {
        case .done: error = nil; await load()
        case .conflict: error = String(localized: "Jemand hat dieses Traktandum gerade geändert. Es wird neu geladen."); await load()
        case .invalid(let text), .failed(let text): error = text
        }
    }

    private func set(_ id: UUID, present: Bool, in current: CampMeetingMode) {
        let members = current.members.map { $0.id == id ? CampMeetingMember(id: $0.id, name: $0.name, ceviName: $0.ceviName, role: $0.role, present: present) : $0 }
        mode = CampMeetingMode(meeting: current.meeting, members: members, portfolioRound: current.portfolioRound)
    }
}
