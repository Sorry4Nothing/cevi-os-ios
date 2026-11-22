import SwiftUI

/// L12: the agenda of one meeting, or the list of items that wait for the next one (`meeting` is `nil`).
@MainActor @Observable
final class CampAgendaModel {
    struct Notice: Equatable { let title: String; let message: String? }

    struct Draft: Equatable {
        var title = ""
        var text = ""
        var decision = ""
    }

    let active: ActiveCamp
    let meetingId: UUID
    @ObservationIgnored var now: () -> Date = { Date() }
    private(set) var phase: CampPhase = .loading
    private(set) var meeting: CampMeeting?
    private(set) var items: [CampAgendaItem] = []
    /// Items without a meeting (they wait for the next one).
    private(set) var waiting: [CampAgendaItem] = []
    private(set) var staleSince: Date?
    private(set) var error: String?
    private(set) var inputError: String?
    private(set) var notice: Notice?
    @ObservationIgnored private var undoAction: (() async -> Void)?

    init(active: ActiveCamp, meetingId: UUID) {
        self.active = active
        self.meetingId = meetingId
    }

    var rights: CampCommsRights { CampCommsRights(role: active.role, readOnly: active.isReadOnly) }
    var canEdit: Bool { rights.editsMeetings }
    var subtitle: String { meeting.map { CampCommsText.meetingDate($0.date, time: nil) } ?? "" }
    var hasUndo: Bool { undoAction != nil }

    func setPreview(phase: CampPhase, meeting: CampMeeting?, waiting: [CampAgendaItem] = [], notice: Notice? = nil, offline: Bool = false, error: String? = nil) {
        self.phase = phase
        self.meeting = meeting
        items = (meeting?.agenda ?? []).sorted { $0.order < $1.order }
        self.waiting = waiting
        self.notice = notice
        undoAction = notice == nil ? nil : {}
        self.error = error
        staleSince = offline ? now() : nil
    }

    func load() async {
        guard let client = active.client, let campId = active.camp?.id else { return }
        do {
            let view = try await client.campMeeting(campId: campId, meetingId: meetingId)
            switch view {
            case .full(let full):
                meeting = full
                items = full.agenda.sorted { $0.order < $1.order }
            case .team:
                // The team sees no agenda (short form only).
                phase = .failed(state: .noAccess, text: "")
                return
            }
            phase = .loaded
            staleSince = nil
            error = nil
            // Optional: the items that wait, for «Übernehmen».
            if canEdit { waiting = (try? await client.campWaitingAgendaItems(campId: campId)) ?? waiting }
        } catch is CancellationError {
        } catch {
            let failure = CampPhase(error: error)
            if meeting == nil { phase = failure } else {
                self.error = failure.failureText
                if case .failed(.offline?, _) = failure { staleSince = staleSince ?? now() }
            }
        }
    }

    // MARK: Order (the alternative to dragging)

    func canMove(_ item: CampAgendaItem, by offset: Int) -> Bool {
        guard canEdit, let index = items.firstIndex(where: { $0.id == item.id }) else { return false }
        return items.indices.contains(index + offset)
    }

    func move(_ item: CampAgendaItem, by offset: Int) async {
        guard canMove(item, by: offset), let index = items.firstIndex(where: { $0.id == item.id }),
              let client = active.client, let campId = active.camp?.id else { return }
        var reordered = items
        reordered.swapAt(index, index + offset)
        let entries = reordered.map { CampVersionRef(id: $0.id, version: $0.version) }
        switch await CampCommsWrite.run({ try await client.reorderCampAgenda(campId: campId, meetingId: meetingId, entries) }) {
        case .done:
            error = nil
            AccessibilityNotification.Announcement(String(localized: "«\(item.title)» ist jetzt Nummer \(index + offset + 1).")).post()
            await load()
        case .invalid(let text), .failed(let text): error = text
        }
    }

    // MARK: Items

    /// Returns true if saved. `item` `nil` creates a new item at the end.
    func save(_ draft: Draft, item: CampAgendaItem?) async -> Bool {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        inputError = nil
        guard canEdit, let client = active.client, let campId = active.camp?.id else { return false }
        guard !title.isEmpty else { inputError = String(localized: "Gib dem Traktandum einen Titel."); return false }
        let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines), decision = draft.decision.trimmingCharacters(in: .whitespacesAndNewlines)
        if let item {
            var patch = CampAgendaItemPatch(version: item.version)
            patch.title = title
            patch.text = text.isEmpty ? .clear : .set(text)
            patch.decision = decision.isEmpty ? .clear : .set(decision)
            switch await CampCommsWrite.run(as: CampAgendaItem.self, { try await client.updateCampAgendaItem(campId: campId, itemId: item.id, patch) }) {
            case .done: await load(); return true
            case .conflict: inputError = String(localized: "Jemand hat dieses Traktandum gerade geändert. Es wird neu geladen."); await load()
            case .invalid(let text), .failed(let text): inputError = text
            }
        } else {
            let body = CampAgendaItemCreate(title: title, meetingId: meetingId, text: text.isEmpty ? nil : text, decision: decision.isEmpty ? nil : decision, order: items.count)
            switch await CampCommsWrite.run({ try await client.createCampAgendaItem(campId: campId, body) }) {
            case .done: await load(); return true
            case .invalid(let text), .failed(let text): inputError = text
            }
        }
        return false
    }

    func delete(_ item: CampAgendaItem) async {
        guard canEdit, let client = active.client, let campId = active.camp?.id else { return }
        switch await CampCommsWrite.run(as: CampAgendaItem.self, { try await client.deleteCampAgendaItem(campId: campId, itemId: item.id, version: item.version) }) {
        case .done: error = nil; await load()
        case .conflict: error = String(localized: "Jemand hat dieses Traktandum gerade geändert. Es wird neu geladen."); await load()
        case .invalid(let text), .failed(let text): error = text
        }
    }

    /// «Auf nächsten Höck»: the item leaves this meeting and waits. «Rückgängig» puts it back.
    func postpone(_ item: CampAgendaItem) async {
        guard let moved = await setMeeting(item, to: nil) else { return }
        show(Notice(title: String(localized: "«\(item.title)» ist auf dem nächsten Hoeck."), message: nil))
        let meetingId = meetingId
        undoAction = { [weak self] in
            guard let self else { return }
            _ = await self.setMeeting(moved, to: meetingId)
            self.notice = nil
        }
    }

    /// Moves every waiting item into this meeting. Returns how many.
    func adoptWaiting() async {
        guard canEdit, !waiting.isEmpty, let client = active.client, let campId = active.camp?.id else { return }
        switch await CampCommsWrite.run({ try await client.adoptCampAgendaItems(campId: campId, meetingId: meetingId) }) {
        case .done(let count):
            show(Notice(title: count == 1 ? String(localized: "1 Traktandum übernommen.") : String(localized: "\(count) Traktanden übernommen."), message: nil))
            waiting = []
            await load()
        case .invalid(let text), .failed(let text): error = text
        }
    }

    private func setMeeting(_ item: CampAgendaItem, to meetingId: UUID?) async -> CampAgendaItem? {
        guard canEdit, let client = active.client, let campId = active.camp?.id else { return nil }
        var patch = CampAgendaItemPatch(version: item.version)
        patch.meetingId = meetingId.map { .set($0) } ?? .clear
        switch await CampCommsWrite.run(as: CampAgendaItem.self, { try await client.updateCampAgendaItem(campId: campId, itemId: item.id, patch) }) {
        case .done(let moved): error = nil; await load(); return moved
        case .conflict: error = String(localized: "Jemand hat dieses Traktandum gerade geändert. Es wird neu geladen."); await load()
        case .invalid(let text), .failed(let text): error = text
        }
        return nil
    }

    func undo() async { await undoAction?() }

    func dismissNotice() { notice = nil; undoAction = nil }

    private func show(_ notice: Notice) {
        self.notice = notice
        AccessibilityNotification.Announcement([notice.title, notice.message].compactMap { $0 }.joined(separator: " ")).post()
    }
}
