import SwiftUI

/// L18: the inbox of the camp leadership: feedback, questions, ideas and wishes of the team, also anonymous ones.
/// An anonymous entry shows no name, ever; the line says «anonym».
@MainActor @Observable
final class CampInboxModel {
    struct Notice: Equatable { let title: String; let message: String? }

    let active: ActiveCamp
    @ObservationIgnored var now: () -> Date = { Date() }
    private(set) var phase: CampPhase = .loading
    private(set) var entries: [CampInboxEntry] = []
    private(set) var portfolios: [CampPortfolio] = []
    private(set) var staleSince: Date?
    private(set) var error: String?
    private(set) var notice: Notice?
    private(set) var hasUndo = false
    @ObservationIgnored private var undoAction: (() async -> Void)?

    init(active: ActiveCamp) { self.active = active }

    var rights: CampCommsRights { CampCommsRights(role: active.role, readOnly: active.isReadOnly) }
    var canAnswer: Bool { rights.answersInbox }
    /// New and in progress first, done ones last; newest first.
    var sorted: [CampInboxEntry] {
        entries.sorted { a, b in
            if (a.status == .done) != (b.status == .done) { return b.status == .done }
            return a.createdOn > b.createdOn
        }
    }

    func setPreview(phase: CampPhase, entries: [CampInboxEntry], notice: Notice? = nil, offline: Bool = false, error: String? = nil) {
        self.phase = phase
        self.entries = entries
        self.notice = notice
        hasUndo = notice != nil
        self.error = error
        staleSince = offline ? now() : nil
    }

    func load() async {
        guard rights.readsInbox else { phase = .failed(state: .noAccess, text: ""); return }
        guard let client = active.client, let campId = active.camp?.id else { return }
        do {
            var all: [CampInboxEntry] = []
            var cursor: UUID?
            repeat {
                let page = try await client.campInbox(campId: campId, after: cursor, limit: 100)
                all += page.entries
                cursor = page.next
            } while cursor != nil && all.count < 1000
            entries = all
            phase = .loaded
            staleSince = nil
            error = nil
            if canAnswer { portfolios = (try? await client.campPortfolios(campId: campId).portfolios) ?? portfolios }
        } catch is CancellationError {
        } catch {
            let failure = CampPhase(error: error)
            if entries.isEmpty { phase = failure } else {
                self.error = failure.failureText
                if case .failed(.offline?, _) = failure { staleSince = staleSince ?? now() }
            }
        }
    }

    // MARK: Text

    static func kindName(_ kind: CampInboxKind) -> String {
        switch kind {
        case .idea: String(localized: "Idee")
        case .wish: String(localized: "Wunsch")
        case .question: String(localized: "Rückfrage")
        case .feedback: String(localized: "Feedback")
        }
    }

    static func statusName(_ status: CampInboxStatus) -> String {
        switch status {
        case .new: String(localized: "Neu")
        case .inProgress: String(localized: "In Arbeit")
        case .done: String(localized: "Erledigt")
        }
    }

    /// «anonym, heute» or «Jonas (Fuchs), gestern». The server sends the day, not the time.
    func sender(_ entry: CampInboxEntry) -> String {
        let day = CampCommsText.relativeDay(entry.createdOn, now: now())
        let who = entry.anonymous ? String(localized: "anonym") : (CampTaskText.personName(name: entry.sender?.name, ceviName: entry.sender?.ceviName) ?? String(localized: "Ohne Namen"))
        return "\(who), \(day)"
    }

    func portfolioName(_ entry: CampInboxEntry) -> String? { portfolios.first { $0.id == entry.portfolioId }?.name }

    // MARK: Actions

    func reply(_ entry: CampInboxEntry, text: String) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canAnswer, !trimmed.isEmpty else { return false }
        return await patch(entry) { $0.reply = .set(trimmed) }
    }

    func setStatus(_ entry: CampInboxEntry, _ status: CampInboxStatus) async {
        guard canAnswer, entry.status != status else { return }
        _ = await patch(entry) { $0.status = status }
    }

    func assign(_ entry: CampInboxEntry, to portfolio: CampPortfolio?) async {
        guard canAnswer else { return }
        _ = await patch(entry) { $0.portfolioId = portfolio.map { .set($0.id) } ?? .clear }
    }

    func delete(_ entry: CampInboxEntry) async {
        guard canAnswer, let client = active.client, let campId = active.camp?.id else { return }
        switch await CampCommsWrite.run(as: CampInboxEntry.self, { try await client.deleteCampInboxEntry(campId: campId, entryId: entry.id, version: entry.version) }) {
        case .done: entries.removeAll { $0.id == entry.id }; error = nil
        case .conflict: error = Self.conflictText; await load()
        case .invalid(let text), .failed(let text): error = text
        }
    }

    /// «Als Traktandum»: an item for the next meeting. «Rückgängig» deletes the item again.
    func makeAgendaItem(_ entry: CampInboxEntry) async {
        guard canAnswer, entry.agendaItemId == nil, let client = active.client, let campId = active.camp?.id else { return }
        let body = CampInboxToAgenda(version: entry.version, title: String(entry.text.prefix(80)), meetingId: nil)
        switch await CampCommsWrite.run(as: CampInboxEntry.self, { try await client.makeCampInboxAgendaItem(campId: campId, entryId: entry.id, body) }) {
        case .done(let changed):
            replace(changed)
            error = nil
            show(Notice(title: String(localized: "Als Traktandum übernommen."), message: String(localized: "Es steht auf dem nächsten Hoeck.")))
            undoAction = { [weak self] in
                guard let self, let itemId = changed.agendaItemId, let client = self.active.client, let campId = self.active.camp?.id else { return }
                let items = (try? await client.campWaitingAgendaItems(campId: campId)) ?? []
                if let item = items.first(where: { $0.id == itemId }) {
                    _ = await CampCommsWrite.run { try await client.deleteCampAgendaItem(campId: campId, itemId: itemId, version: item.version) }
                }
                await self.load()
                self.dismissNotice()
            }
            hasUndo = true
        case .conflict: error = Self.conflictText; await load()
        case .invalid(let text), .failed(let text): error = text
        }
    }

    func undo() async { await undoAction?() }

    func dismissNotice() { notice = nil; undoAction = nil; hasUndo = false }

    private static var conflictText: String { String(localized: "Jemand hat diesen Eintrag gerade geändert. Er wird neu geladen.") }

    private func patch(_ entry: CampInboxEntry, _ change: (inout CampInboxPatch) -> Void) async -> Bool {
        guard let client = active.client, let campId = active.camp?.id else { return false }
        var body = CampInboxPatch(version: entry.version)
        change(&body)
        switch await CampCommsWrite.run(as: CampInboxEntry.self, { try await client.updateCampInboxEntry(campId: campId, entryId: entry.id, body) }) {
        case .done(let changed): replace(changed); error = nil; return true
        case .conflict: error = Self.conflictText; await load()
        case .invalid(let text), .failed(let text): error = text
        }
        return false
    }

    private func replace(_ entry: CampInboxEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) { entries[index] = entry }
    }

    private func show(_ notice: Notice) {
        self.notice = notice
        AccessibilityNotification.Announcement([notice.title, notice.message].compactMap { $0 }.joined(separator: " ")).post()
    }
}
