import Foundation

/// L7: one task with checklist, links, note and history.
@MainActor @Observable
final class CampTaskDetailModel {
    let active: ActiveCamp
    let personId: UUID
    let taskId: UUID
    @ObservationIgnored var now: () -> Date = { Date() }
    private(set) var phase: CampPhase = .loading
    private(set) var task: CampTask?
    private(set) var details: CampTaskDetails?
    private(set) var history: CampTaskHistory?
    private(set) var portfolios: [CampPortfolio] = []
    private(set) var error: String?
    /// The server refused the input (400): the field is named in the text.
    private(set) var inputError: String?
    private(set) var isQueued = false
    private(set) var isGone = false
    var conflict: CampTaskConflict?

    init(active: ActiveCamp, personId: UUID, taskId: UUID, task: CampTask? = nil) {
        self.active = active
        self.personId = personId
        self.taskId = taskId
        self.task = task
        if task != nil { phase = .loaded }
    }

    var rights: CampTaskRights { CampTaskRights(role: active.role, readOnly: active.isReadOnly, personId: personId) }
    var canEdit: Bool { task != nil && rights.canEdit }
    var canSetStatus: Bool { task.map(rights.canSetStatus) ?? false }
    var checklist: [CampChecklistItem] { (details?.checklist ?? []).sorted { $0.order < $1.order } }
    var checklistDone: Int { checklist.count { $0.done } }

    /// «Nur lesen.» with the reason, when the role may see but not change this task.
    var readOnlyReason: String? {
        guard let task, !canSetStatus, !active.isReadOnly else { return nil }
        if let portfolio = task.portfolio { return String(localized: "Diese Aufgabe gehört zum Ressort \(portfolio.name). Ändern kann sie die Ressortleitung.") }
        return String(localized: "Du kannst diese Aufgabe ansehen, aber nicht ändern.")
    }

    func setPreview(phase: CampPhase, task: CampTask?, details: CampTaskDetails? = nil, error: String? = nil, inputError: String? = nil) {
        self.error = error
        self.inputError = inputError
        self.phase = phase
        self.task = task
        self.details = details
    }

    func load() async {
        guard let client = active.client, let campId = active.camp?.id else { return }
        do {
            async let loadedTask = client.campTask(campId: campId, taskId: taskId)
            async let loadedDetails = client.campTaskDetails(campId: campId, taskId: taskId)
            let (newTask, newDetails) = try await (loadedTask, loadedDetails)
            task = newTask
            details = newDetails
            phase = .loaded
            // Optional parts: a failure leaves the task readable.
            history = try? await client.campTaskHistory(campId: campId, taskId: taskId)
            if rights.canEdit { portfolios = (try? await client.campPortfolios(campId: campId).portfolios) ?? [] }
        } catch is CancellationError {
        } catch {
            if task == nil { phase = CampPhase(error: error) } else { self.error = CampPhase(error: error).failureText }
        }
    }

    // MARK: Task fields

    func setStatus(_ status: CampTaskStatus) async {
        guard let task, canSetStatus, task.status != status, let client = active.client, let campId = active.camp?.id else { return }
        await write(task, mine: [(.status, CampTaskText.statusName(status))], queue: CampTaskWriter.statusOperation(task, status)) {
            try await client.setCampTaskStatus(campId: campId, taskId: task.id, version: $0, status: status)
        }
    }

    func toggleStar() async {
        guard let task else { return }
        let starred = !task.starred
        await patch(task, mine: [(.starred, starred ? String(localized: "Ja") : String(localized: "Nein"))]) { $0.starred = starred }
    }

    func setDue(_ date: Date?) async {
        guard let task else { return }
        await patch(task, mine: [(.due, date.map(CampTaskText.day) ?? String(localized: "Keine"))]) {
            $0.due = date.map { .set(CampCalendarDay($0)) } ?? .clear
        }
    }

    func setNote(_ text: String) async {
        guard let task else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        await patch(task, mine: [(.note, trimmed.isEmpty ? String(localized: "Keine") : trimmed)]) { $0.note = trimmed.isEmpty ? .clear : .set(trimmed) }
    }

    func setPortfolio(_ portfolio: CampPortfolio?) async {
        guard let task else { return }
        await patch(task, mine: [(.portfolio, portfolio?.name ?? String(localized: "Keines"))]) { $0.portfolioId = portfolio.map { .set($0.id) } ?? .clear }
    }

    func setRepeat(_ value: CampTaskRepeat?) async {
        guard let task else { return }
        await patch(task, mine: [(.repeatEvery, CampTaskText.repeatName(value))]) { $0.repeatEvery = value.map { .set($0) } ?? .clear }
    }

    /// Returns true if the task is gone (the screen closes).
    func delete() async -> Bool {
        guard let task, rights.canDelete, let client = active.client, let campId = active.camp?.id else { return false }
        do {
            try await BusyState.shared.track { try await client.deleteCampTask(campId: campId, taskId: task.id, version: task.version) }
            isGone = true
            return true
        } catch { fail(error); return false }
    }

    // MARK: Checklist (own version per item; a conflict reloads the list)

    func toggle(_ item: CampChecklistItem) async {
        await changeItem(item) { client, campId, taskId in
            _ = try await client.updateCampChecklistItem(campId: campId, taskId: taskId, itemId: item.id, CampChecklistPatch(version: item.version, done: !item.done))
        }
    }

    func addChecklistItem(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canEdit, !trimmed.isEmpty, let client = active.client, let campId = active.camp?.id else { return }
        do { _ = try await BusyState.shared.track { try await client.createCampChecklistItem(campId: campId, taskId: taskId, CampChecklistCreate(text: trimmed)) }; await reloadDetails() }
        catch { fail(error) }
    }

    func removeChecklistItem(_ item: CampChecklistItem) async {
        guard canEdit else { return }
        await changeItem(item) { client, campId, taskId in
            try await client.deleteCampChecklistItem(campId: campId, taskId: taskId, itemId: item.id, version: item.version)
        }
    }

    /// «Nach oben» and «Nach unten»: the alternative to dragging.
    func moveChecklistItem(_ item: CampChecklistItem, by offset: Int) async {
        guard canEdit, let client = active.client, let campId = active.camp?.id else { return }
        var list = checklist
        guard let index = list.firstIndex(of: item), list.indices.contains(index + offset) else { return }
        list.swapAt(index, index + offset)
        do {
            try await BusyState.shared.track { try await client.reorderCampChecklist(campId: campId, taskId: taskId, list.map { CampVersionRef(id: $0.id, version: $0.version) }) }
            await reloadDetails()
        } catch { fail(error); await reloadDetails() }
    }

    // MARK: Private

    private func changeItem(_ item: CampChecklistItem, _ change: @escaping (APIClient, UUID, UUID) async throws -> Void) async {
        guard canSetStatus || canEdit, let client = active.client, let campId = active.camp?.id else { return }
        do { try await BusyState.shared.track { try await change(client, campId, taskId) }; await reloadDetails() }
        catch { fail(error); await reloadDetails() }
    }

    private func reloadDetails() async {
        guard let client = active.client, let campId = active.camp?.id else { return }
        details = (try? await client.campTaskDetails(campId: campId, taskId: taskId)) ?? details
    }

    private func patch(_ task: CampTask, mine: [(field: CampTaskField, text: String)], _ change: @escaping (inout CampTaskPatch) -> Void) async {
        guard canEdit, let client = active.client, let campId = active.camp?.id else { return }
        await write(task, mine: mine) {
            var patch = CampTaskPatch(version: $0)
            change(&patch)
            return try await client.updateCampTask(campId: campId, taskId: task.id, patch)
        }
    }

    private func write(_ task: CampTask, mine: [(field: CampTaskField, text: String)], queue: CampOperation? = nil,
                       _ perform: @escaping (Int) async throws -> CampTask) async {
        error = nil
        inputError = nil
        switch await CampTaskWriter(active: active).run(task, mine: mine, queue: queue, perform) {
        case .written(let written): self.task = written; isQueued = false
        case .conflict(let value): conflict = value
        case .queued: isQueued = true
        case .invalid(let text): inputError = text
        case .failed(let text): error = text
        }
    }

    private func fail(_ failure: any Error) {
        guard let failure = failure as? APIError else { error = APIError.network.displayText; return }
        if failure.kind == .invalidInput { inputError = failure.displayText } else { error = CampRules.writeError(failure) }
        if failure.kind == .notFound { phase = .failed(state: .notFound, text: failure.displayText) }
    }

    func resolveConflict(_ choice: CampConflictChoice) async {
        guard let conflict else { return }
        self.conflict = nil
        switch choice {
        case .keepCurrent, .merge: task = conflict.current
        case .keepMine:
            do { task = try await BusyState.shared.track { try await conflict.retry(conflict.current.version) } }
            catch { fail(error) }
        }
    }
}
