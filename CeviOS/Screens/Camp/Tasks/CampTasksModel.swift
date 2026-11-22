import SwiftUI

/// L5 list, T1 board, L9 multi-select, and the quick actions on rows. Loads all tasks the role may read.
@MainActor @Observable
final class CampTasksModel {
    /// «Aufgabe erledigt.» with «Rückgängig».
    struct Notice: Equatable {
        let title: String
        let message: String?
    }

    let active: ActiveCamp
    let personId: UUID
    @ObservationIgnored var now: () -> Date = { Date() }
    private(set) var phase: CampPhase = .loading
    private(set) var tasks: [CampTask] = []
    private(set) var portfolios: [CampPortfolio] = []
    var tab: CampTaskTab = .list
    var filter = CampTaskLocalFilter()
    var sort: CampTaskSort = .due
    var isSelecting = false
    var selection: Set<UUID> = []
    /// Tasks whose change waits in the queue.
    private(set) var queuedIds: Set<UUID> = []
    private(set) var notice: Notice?
    private(set) var error: String?
    var conflict: CampTaskConflict?
    @ObservationIgnored private var undoAction: (() async -> Void)?

    init(active: ActiveCamp, personId: UUID) {
        self.active = active
        self.personId = personId
    }

    var rights: CampTaskRights { CampTaskRights(role: active.role, readOnly: active.isReadOnly, personId: personId) }
    var today: Date { now() }
    var sections: [CampTaskSection] {
        CampTaskText.sections(tasks, tab: tab, personId: personId, filter: filter, sort: sort, today: today)
    }
    var isEmpty: Bool { tasks.isEmpty }
    func tasks(in status: CampTaskStatus) -> [CampTask] {
        tasks.filter { $0.status == status && (filter.portfolioId == nil || $0.portfolioId == filter.portfolioId)
            && (filter.responsibleId == nil || $0.responsibleId == filter.responsibleId) }
            .sorted { $0.order < $1.order }
    }

    /// The people who are responsible for at least one task, for the board filter.
    var responsibles: [CampTaskResponsible] {
        var seen = Set<UUID>()
        return tasks.compactMap(\.responsible).filter { seen.insert($0.id).inserted }
            .sorted { (CampTaskText.person($0) ?? "").localizedStandardCompare(CampTaskText.person($1) ?? "") == .orderedAscending }
    }

    /// For previews and tests.
    func setPreview(phase: CampPhase, tasks: [CampTask], portfolios: [CampPortfolio] = [], notice: Notice? = nil, error: String? = nil) {
        self.notice = notice
        self.error = error
        self.phase = phase
        self.tasks = tasks
        self.portfolios = portfolios
    }

    func load() async {
        guard let client = active.client, let campId = active.camp?.id else { return }
        do {
            var all: [CampTask] = []
            var cursor: UUID?
            repeat {
                let page = try await client.campTasks(campId: campId, after: cursor, limit: 100)
                all += page.tasks
                cursor = page.next
            } while cursor != nil && all.count < 2000
            tasks = all
            phase = .loaded
            // The portfolios only add names and the filter: a failure here does not fail the screen.
            portfolios = (try? await client.campPortfolios(campId: campId).portfolios) ?? portfolios
        } catch is CancellationError {
        } catch {
            if tasks.isEmpty { phase = CampPhase(error: error) } else { self.error = CampPhase(error: error).failureText }
        }
    }

    // MARK: Single task

    func setStatus(_ task: CampTask, to status: CampTaskStatus) async {
        guard rights.canSetStatus(task), task.status != status, let client = active.client, let campId = active.camp?.id else { return }
        let previous = task.status
        let outcome = await CampTaskWriter(active: active).run(task, mine: [(.status, CampTaskText.statusName(status))],
                                                               queue: CampTaskWriter.statusOperation(task, status)) {
            try await client.setCampTaskStatus(campId: campId, taskId: task.id, version: $0, status: status)
        }
        guard let written = settle(outcome, task: task) else {
            if case .queued = outcome { queuedIds.insert(task.id) }
            return
        }
        if status == .done {
            show(Notice(title: String(localized: "Aufgabe erledigt."), message: String(localized: "«\(task.title)» steht jetzt unter Erledigt.")))
        } else {
            show(Notice(title: String(localized: "Status geändert."), message: String(localized: "«\(task.title)» ist jetzt \(CampTaskText.statusName(status))."))) 
        }
        undoAction = { [weak self] in
            guard let self, let current = self.tasks.first(where: { $0.id == written.id }) else { return }
            await self.setStatus(current, to: previous)
            self.notice = nil
        }
    }

    /// The circle on a row: done, or open again.
    func toggleDone(_ task: CampTask) async { await setStatus(task, to: task.status == .done ? .open : .done) }

    func toggleStar(_ task: CampTask) async {
        guard rights.canEdit, let client = active.client, let campId = active.camp?.id else { return }
        let starred = !task.starred
        let outcome = await CampTaskWriter(active: active).run(task, mine: [(.starred, starred ? String(localized: "Ja") : String(localized: "Nein"))]) {
            var patch = CampTaskPatch(version: $0)
            patch.starred = starred
            return try await client.updateCampTask(campId: campId, taskId: task.id, patch)
        }
        _ = settle(outcome, task: task)
    }

    func undo() async {
        let action = undoAction
        notice = nil
        undoAction = nil
        await action?()
    }

    func dismissNotice() { notice = nil; undoAction = nil }
    func dismissError() { error = nil }

    func resolveConflict(_ choice: CampConflictChoice) async {
        guard let conflict else { return }
        self.conflict = nil
        switch choice {
        case .keepCurrent, .merge: replace(conflict.current)
        case .keepMine:
            do { replace(try await BusyState.shared.track { try await conflict.retry(conflict.current.version) }) }
            catch let error as APIError { self.error = CampRules.writeError(error) }
            catch { self.error = APIError.network.displayText }
        }
    }

    // MARK: Several tasks (L9)

    func startSelecting(_ task: CampTask? = nil) {
        isSelecting = true
        selection = task.map { [$0.id] } ?? []
    }

    func stopSelecting() { isSelecting = false; selection = [] }

    func toggleSelection(_ task: CampTask) {
        if selection.contains(task.id) { selection.remove(task.id) } else { selection.insert(task.id) }
    }

    var selected: [CampTask] { tasks.filter { selection.contains($0.id) } }

    func setStatusOfSelection(_ status: CampTaskStatus) async {
        guard let client = active.client, let campId = active.camp?.id else { return }
        let before = selected.filter { rights.canSetStatus($0) && $0.status != status }.map { ($0.id, $0.status) }
        let title = status == .done ? String(localized: "\(selection.count) Aufgaben auf Erledigt gesetzt.")
            : String(localized: "\(selection.count) Aufgaben auf \(CampTaskText.statusName(status)) gesetzt.")
        let ok = await bulk(selected.filter { rights.canSetStatus($0) }) { task, version in
            try await client.setCampTaskStatus(campId: campId, taskId: task.id, version: version, status: status)
        }
        guard ok else { return }
        show(Notice(title: title, message: nil))
        undoAction = { [weak self] in
            guard let self else { return }
            for (id, old) in before { if let task = self.tasks.first(where: { $0.id == id }) { await self.setStatus(task, to: old) } }
            self.notice = nil
        }
    }

    func setDueOfSelection(_ date: Date?) async {
        guard rights.canEdit, let client = active.client, let campId = active.camp?.id else { return }
        let ok = await bulk(selected) { task, version in
            var patch = CampTaskPatch(version: version)
            patch.due = date.map { .set(CampCalendarDay($0)) } ?? .clear
            return try await client.updateCampTask(campId: campId, taskId: task.id, patch)
        }
        if ok { show(Notice(title: String(localized: "Frist geändert."), message: nil)) }
    }

    func setPortfolioOfSelection(_ portfolioId: UUID?) async {
        guard rights.canEdit, let client = active.client, let campId = active.camp?.id else { return }
        let ok = await bulk(selected) { task, version in
            var patch = CampTaskPatch(version: version)
            patch.portfolioId = portfolioId.map { .set($0) } ?? .clear
            return try await client.updateCampTask(campId: campId, taskId: task.id, patch)
        }
        if ok { show(Notice(title: String(localized: "Ressort geändert."), message: nil)) }
    }

    func deleteSelection() async {
        guard rights.canDelete, let client = active.client, let campId = active.camp?.id else { return }
        let count = selection.count
        for task in selected {
            do { try await BusyState.shared.track { try await client.deleteCampTask(campId: campId, taskId: task.id, version: task.version) } }
            catch { fail(count: count, error); return }
            tasks.removeAll { $0.id == task.id }
            selection.remove(task.id)
        }
        stopSelecting()
        show(Notice(title: count == 1 ? String(localized: "1 Aufgabe gelöscht.") : String(localized: "\(count) Aufgaben gelöscht."), message: nil))
    }

    // MARK: Private

    /// Runs `change` on each task. Stops at the first failure and keeps the selection; true if all went through.
    private func bulk(_ list: [CampTask], _ change: @escaping (CampTask, Int) async throws -> CampTask) async -> Bool {
        let count = selection.count
        error = nil
        for task in list {
            let outcome = await CampTaskWriter(active: active).run(task, mine: []) { try await change(task, $0) }
            guard case .written(let written) = outcome else { fail(count: count, nil); return false }
            replace(written)
        }
        stopSelecting()
        return true
    }

    private func fail(count: Int, _ error: (any Error)?) {
        let reason = (error as? APIError).map(CampRules.writeError)
        let selected = count == 1 ? String(localized: "Die Aufgabe ist noch gewählt.") : String(localized: "Die \(count) Aufgaben sind noch gewählt.")
        self.error = String(localized: "Das hat nicht geklappt.") + " " + (reason.map { $0 + " " } ?? "") + selected + " " + String(localized: "Versuche es nochmals.")
    }

    /// Takes the outcome of a single write. Returns the written task, `nil` otherwise.
    private func settle(_ outcome: CampTaskWriter.Outcome, task: CampTask) -> CampTask? {
        switch outcome {
        case .written(let written):
            error = nil
            replace(written)
            return written
        case .conflict(let value): conflict = value
        case .queued: break
        case .failed(let text), .invalid(let text): error = text
        }
        return nil
    }

    private func replace(_ task: CampTask) {
        queuedIds.remove(task.id)
        if let index = tasks.firstIndex(where: { $0.id == task.id }) { tasks[index] = task } else { tasks.append(task) }
    }

    private func show(_ notice: Notice) {
        self.notice = notice
        AccessibilityNotification.Announcement([notice.title, notice.message].compactMap { $0 }.joined(separator: " ")).post()
    }
}

nonisolated extension CampPhase {
    var failureText: String {
        if case .failed(_, let text) = self { text } else { "" }
    }
}
