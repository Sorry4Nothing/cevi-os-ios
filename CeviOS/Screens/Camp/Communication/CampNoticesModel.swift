import SwiftUI

/// L16: the notice board (Pinnwand). Everybody reads what is meant for them; leads write, pin and mark as important.
@MainActor @Observable
final class CampNoticesModel {
    let active: ActiveCamp
    @ObservationIgnored var now: () -> Date = { Date() }
    private(set) var phase: CampPhase = .loading
    private(set) var notices: [CampNotice] = []
    private(set) var staleSince: Date?
    private(set) var error: String?

    init(active: ActiveCamp) { self.active = active }

    var rights: CampCommsRights { CampCommsRights(role: active.role, readOnly: active.isReadOnly) }

    /// Pinned first, then important, then the newest.
    var sorted: [CampNotice] {
        notices.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            if a.important != b.important { return a.important }
            return a.createdAt > b.createdAt
        }
    }

    func setPreview(phase: CampPhase, notices: [CampNotice], offline: Bool = false, error: String? = nil) {
        self.phase = phase
        self.notices = notices
        self.error = error
        staleSince = offline ? now() : nil
    }

    func load() async {
        guard let client = active.client, let campId = active.camp?.id else { return }
        do {
            var all: [CampNotice] = []
            var cursor: UUID?
            repeat {
                // Editors also see expired and future notices (the time window), the others what is valid now.
                let page = try await client.campNotices(campId: campId, scope: rights.editsNotices ? .all : .active, after: cursor, limit: 100)
                all += page.notices
                cursor = page.next
            } while cursor != nil && all.count < 1000
            notices = all
            phase = .loaded
            staleSince = nil
            error = nil
        } catch is CancellationError {
        } catch {
            let failure = CampPhase(error: error)
            if notices.isEmpty { phase = failure } else {
                self.error = failure.failureText
                if case .failed(.offline?, _) = failure { staleSince = staleSince ?? now() }
            }
        }
    }

    // MARK: Text

    /// «An alle, sichtbar bis 17. Juli», «An Leitung, endet am 1. Juli» (with a poll).
    func audience(_ notice: CampNotice) -> String {
        let who: String
        if notice.audience.everyone || notice.audience.roles.isEmpty { who = String(localized: "An alle") } else {
            who = String(localized: "An") + " " + notice.audience.roles.map(Self.roleName).joined(separator: ", ")
        }
        var parts = [who]
        if let until = notice.visibleUntil {
            let day = CampCommsText.day(until)
            parts.append(notice.poll != nil ? String(localized: "endet am \(day)") : String(localized: "sichtbar bis \(day)"))
        }
        if let from = notice.visibleFrom, from > now() { parts.append(String(localized: "sichtbar ab \(CampCommsText.day(from))")) }
        return parts.joined(separator: ", ")
    }

    static func roleName(_ role: CampNoticeRole) -> String {
        switch role {
        case .leadership: String(localized: "Leitung")
        case .team: String(localized: "Team")
        case .readOnly: String(localized: "Lesende")
        }
    }

    static func reactionName(_ key: CampReactionKey) -> String {
        switch key {
        case .thumbsUp: String(localized: "Daumen hoch")
        case .heart: String(localized: "Herz")
        case .laugh: String(localized: "Lachen")
        case .surprise: String(localized: "Staunen")
        case .thanks: String(localized: "Danke")
        }
    }

    /// The window of an editor: «Abgelaufen» or «Noch nicht sichtbar».
    func windowState(_ notice: CampNotice) -> String? {
        if let until = notice.visibleUntil, until <= now() { return String(localized: "Abgelaufen") }
        if let from = notice.visibleFrom, from > now() { return String(localized: "Noch nicht sichtbar") }
        return nil
    }

    // MARK: Actions

    /// Pin and importance (editors).
    func setFlags(_ notice: CampNotice, pinned: Bool? = nil, important: Bool? = nil) async {
        guard rights.editsNotices, let client = active.client, let campId = active.camp?.id else { return }
        var patch = CampNoticePatch(version: notice.version)
        patch.pinned = pinned
        patch.important = important
        switch await CampCommsWrite.run(as: CampNotice.self, { try await client.updateCampNotice(campId: campId, noticeId: notice.id, patch) }) {
        case .done(let changed): replace(changed); error = nil
        case .conflict: error = String(localized: "Jemand hat diese Mitteilung gerade geändert. Sie wird neu geladen."); await load()
        case .invalid(let text), .failed(let text): error = text
        }
    }

    func delete(_ notice: CampNotice) async {
        guard rights.editsNotices, let client = active.client, let campId = active.camp?.id else { return }
        switch await CampCommsWrite.run(as: CampNotice.self, { try await client.deleteCampNotice(campId: campId, noticeId: notice.id, version: notice.version) }) {
        case .done: notices.removeAll { $0.id == notice.id }; error = nil
        case .conflict: error = String(localized: "Jemand hat diese Mitteilung gerade geändert. Sie wird neu geladen."); await load()
        case .invalid(let text), .failed(let text): error = text
        }
    }

    /// One reaction per person: the same key again takes it back.
    func react(_ notice: CampNotice, _ key: CampReactionKey) async {
        guard rights.interacts, let client = active.client, let campId = active.camp?.id else { return }
        let outcome: CampWriteOutcome<Void, Never> = await CampCommsWrite.run {
            if notice.reactions.own == key { try await client.removeCampReaction(campId: campId, targetId: notice.id) }
            else { _ = try await client.setCampReaction(campId: campId, targetId: notice.id, key) }
        }
        switch outcome {
        case .done: error = nil; await reload(notice.id)
        case .invalid(let text), .failed(let text): error = text
        }
    }

    /// The own vote: the one option, or the set of options if the poll allows several. Choosing the same option again withdraws it.
    func vote(_ notice: CampNotice, option: CampPollOption) async {
        guard rights.interacts, let poll = notice.poll, !poll.closed, let client = active.client, let campId = active.camp?.id else { return }
        let own = Set(poll.options.filter(\.own).map(\.id))
        var chosen = poll.multiple ? own : []
        if own.contains(option.id) { chosen.remove(option.id) } else { chosen.insert(option.id) }
        let outcome: CampWriteOutcome<Void, Never> = await CampCommsWrite.run {
            if chosen.isEmpty { try await client.withdrawCampPollVote(campId: campId, noticeId: notice.id) }
            else { _ = try await client.voteCampPoll(campId: campId, noticeId: notice.id, optionIds: Array(chosen)) }
        }
        switch outcome {
        case .done: error = nil; await reload(notice.id)
        case .invalid(let text), .failed(let text): error = text
        }
    }

    private func reload(_ id: UUID) async {
        guard let client = active.client, let campId = active.camp?.id, let fresh = try? await client.campNotice(campId: campId, noticeId: id) else { return }
        replace(fresh)
    }

    private func replace(_ notice: CampNotice) {
        if let index = notices.firstIndex(where: { $0.id == notice.id }) { notices[index] = notice }
    }
}
