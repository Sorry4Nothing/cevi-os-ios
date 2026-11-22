import Foundation

/// Load state of a camp screen. `failed.state` is the cross-cutting state (U1 to U4), `nil` for the general error.
nonisolated enum CampPhase: Equatable, Sendable {
    case loading
    case loaded
    case failed(state: CampScreenState?, text: String)

    init(error: any Error) {
        if let error = error as? APIError {
            self = .failed(state: CampScreenState(error: error), text: error.displayText)
        } else {
            self = .failed(state: .offline, text: APIError.network.displayText)
        }
    }
}

/// What the role may do with tasks. The app shows only these actions; the server decides again (`docs/lager.md`).
nonisolated struct CampTaskRights: Equatable, Sendable {
    let role: CampRole?
    /// The camp is completed or archived.
    let readOnly: Bool
    let personId: UUID?

    private var edits: Bool { !readOnly && (role == .campLeader || role == .leader) }
    var canCreate: Bool { edits }
    var canEdit: Bool { edits }
    var canDelete: Bool { !readOnly && role == .campLeader }
    var canMerge: Bool { canDelete }
    /// Leads change every status; the team only that of the own tasks.
    func canSetStatus(_ task: CampTask) -> Bool {
        edits || (!readOnly && role == .team && personId != nil && task.responsibleId == personId)
    }
    /// The task list is for leads; the team reaches its own tasks on the start page.
    var seesTaskList: Bool { role == .campLeader || role == .leader }
}

nonisolated enum CampTaskTab: String, CaseIterable, Identifiable, Sendable {
    case list, mine, people, portfolio
    var id: String { rawValue }
}

nonisolated enum CampTaskSort: String, CaseIterable, Identifiable, Sendable {
    case due, title, manual
    var id: String { rawValue }
}

/// Local filter on the loaded tasks.
nonisolated struct CampTaskLocalFilter: Equatable, Sendable {
    var overdueOnly = false
    var starredOnly = false
    var status: CampTaskStatus?
    var portfolioId: UUID?
    var responsibleId: UUID?

    var isActive: Bool { overdueOnly || starredOnly || status != nil || portfolioId != nil || responsibleId != nil }
}

nonisolated struct CampTaskSection: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let tasks: [CampTask]
    let isDone: Bool
}

nonisolated enum CampTaskText {
    static func statusName(_ status: CampTaskStatus) -> String {
        switch status {
        case .open: String(localized: "Offen")
        case .running: String(localized: "Läuft")
        case .waiting: String(localized: "Wartet")
        case .done: String(localized: "Erledigt")
        case .nextMeeting: String(localized: "Nächster Hoeck")
        }
    }

    /// The four columns of the board and the status choice; `nextMeeting` stays reachable through the server only.
    static let boardStatuses: [CampTaskStatus] = [.open, .running, .waiting, .done]

    static func repeatName(_ value: CampTaskRepeat?) -> String {
        switch value {
        case nil: String(localized: "Keine")
        case .weekly: String(localized: "Jede Woche")
        case .biweekly: String(localized: "Alle 2 Wochen")
        case .monthly: String(localized: "Jeden Monat")
        }
    }

    static func day(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: Locale(identifier: "de_CH"), timeZone: DateFormats.timeZone).day().month(.wide))
    }

    static func person(_ person: CampTaskResponsible?) -> String? {
        guard let person else { return nil }
        return personName(name: person.name, ceviName: person.ceviName)
    }

    /// «Tim (Spatz)»: first name and Cevi name.
    static func personName(name: String?, ceviName: String?) -> String? {
        switch (name, ceviName) {
        case (let name?, let cevi?): "\(name) (\(cevi))"
        case (let name?, nil): name
        case (nil, let cevi?): cevi
        default: nil
        }
    }

    static func days(from today: Date, to date: Date) -> Int {
        let calendar = DateFormats.calendar
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: today), to: calendar.startOfDay(for: date)).day ?? 0
    }

    static func isOverdue(_ task: CampTask, today: Date) -> Bool {
        guard task.status != .done, let due = task.due else { return false }
        return days(from: today, to: due) < 0
    }

    /// «Überfällig seit 2 Tagen», «Heute fällig», «Fällig in 5 Tagen» (up to 14 days); `nil` for done tasks and far deadlines.
    static func dueHint(_ task: CampTask, today: Date) -> (text: String, isOverdue: Bool)? {
        guard task.status != .done, let due = task.due else { return nil }
        let n = days(from: today, to: due)
        if n < 0 { return (n == -1 ? String(localized: "Überfällig seit 1 Tag") : String(localized: "Überfällig seit \(-n) Tagen"), true) }
        if n == 0 { return (String(localized: "Heute fällig"), false) }
        if n <= 14 { return (n == 1 ? String(localized: "Fällig in 1 Tag") : String(localized: "Fällig in \(n) Tagen"), false) }
        return nil
    }

    static func doneTitle(_ count: Int) -> String {
        count == 1 ? String(localized: "Erledigt, 1 Aufgabe") : String(localized: "Erledigt, \(count) Aufgaben")
    }

    /// The tab's grouping. Done tasks always form the last section.
    static func sections(_ tasks: [CampTask], tab: CampTaskTab, personId: UUID?, filter: CampTaskLocalFilter, sort: CampTaskSort, today: Date) -> [CampTaskSection] {
        var visible = tasks.filter { task in
            (!filter.overdueOnly || isOverdue(task, today: today))
                && (!filter.starredOnly || task.starred)
                && (filter.status == nil || task.status == filter.status)
                && (filter.portfolioId == nil || task.portfolioId == filter.portfolioId)
                && (filter.responsibleId == nil || task.responsibleId == filter.responsibleId)
        }
        if tab == .mine { visible = visible.filter { $0.responsibleId == personId } }
        let open = ordered(visible.filter { $0.status != .done }, sort)
        var result: [CampTaskSection] = []
        switch tab {
        case .list, .mine:
            func part(_ id: String, _ title: String, _ test: (CampTask) -> Bool) {
                let part = open.filter(test)
                if !part.isEmpty { result.append(CampTaskSection(id: id, title: title, tasks: part, isDone: false)) }
            }
            part("overdue", String(localized: "Überfällig")) { isOverdue($0, today: today) }
            part("soon", String(localized: "Diese zwei Wochen")) { task in
                guard !isOverdue(task, today: today), let due = task.due else { return false }
                return days(from: today, to: due) <= 14
            }
            part("later", String(localized: "Später")) { task in
                guard let due = task.due else { return false }
                return days(from: today, to: due) > 14
            }
            part("none", String(localized: "Ohne Frist")) { $0.due == nil }
        case .people:
            result = grouped(open, key: { person($0.responsible) ?? "" }, empty: String(localized: "Ohne Verantwortliche"), prefix: "person")
        case .portfolio:
            result = grouped(open, key: { $0.portfolio?.name ?? "" }, empty: String(localized: "Ohne Ressort"), prefix: "portfolio")
        }
        let done = ordered(visible.filter { $0.status == .done }, sort)
        if !done.isEmpty { result.append(CampTaskSection(id: "done", title: doneTitle(done.count), tasks: done, isDone: true)) }
        return result
    }

    private static func grouped(_ tasks: [CampTask], key: (CampTask) -> String, empty: String, prefix: String) -> [CampTaskSection] {
        let groups = Dictionary(grouping: tasks, by: key)
        return groups.keys.sorted { a, b in a.isEmpty != b.isEmpty ? b.isEmpty : a.localizedStandardCompare(b) == .orderedAscending }
            .map { CampTaskSection(id: "\(prefix)-\($0)", title: $0.isEmpty ? empty : $0, tasks: groups[$0] ?? [], isDone: false) }
    }

    private static func ordered(_ tasks: [CampTask], _ sort: CampTaskSort) -> [CampTask] {
        switch sort {
        case .manual: tasks.sorted { $0.order < $1.order }
        case .title: tasks.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .due: tasks.sorted { ($0.due ?? .distantFuture, $0.order) < ($1.due ?? .distantFuture, $1.order) }
        }
    }
}

/// A field of a task that a conflict can name.
nonisolated enum CampTaskField: Sendable {
    case status, due, title, note, portfolio, starred, repeatEvery

    var label: String {
        switch self {
        case .status: String(localized: "Status")
        case .due: String(localized: "Frist")
        case .title: String(localized: "Titel")
        case .note: String(localized: "Notiz")
        case .portfolio: String(localized: "Ressort")
        case .starred: String(localized: "Stern")
        case .repeatEvery: String(localized: "Wiederholung")
        }
    }

    func text(of task: CampTask) -> String {
        switch self {
        case .status: CampTaskText.statusName(task.status)
        case .due: task.due.map(CampTaskText.day) ?? String(localized: "Keine")
        case .title: task.title
        case .note: task.note ?? String(localized: "Keine")
        case .portfolio: task.portfolio?.name ?? String(localized: "Keines")
        case .starred: task.starred ? String(localized: "Ja") : String(localized: "Nein")
        case .repeatEvery: CampTaskText.repeatName(task.repeatEvery)
        }
    }
}

/// Someone else changed the task (409 `VERSION_KONFLIKT`): the person chooses (U7).
struct CampTaskConflict: Identifiable {
    let id = UUID()
    let subject: String
    let current: CampTask
    /// What the person wanted, per field.
    let mine: [(field: CampTaskField, text: String)]
    /// Sends the same change again on the version the server holds now.
    let retry: (Int) async throws -> CampTask

    var fields: [CampConflictField] {
        mine.map { CampConflictField(label: $0.field.label, mine: $0.text, current: $0.field.text(of: current)) }
    }
}

/// Runs one write on a task and sorts the answer: written, conflict, queued for later, or failed.
@MainActor
struct CampTaskWriter {
    let active: ActiveCamp

    enum Outcome {
        case written(CampTask)
        case conflict(CampTaskConflict)
        /// No network: the change waits in the queue (U6).
        case queued
        /// 400: the server refused the input; the text names the field.
        case invalid(String)
        case failed(String)
    }

    /// `queue` is the same change as an operation of `POST …/aenderungen`, for the routes that have one.
    func run(_ task: CampTask, mine: [(field: CampTaskField, text: String)], queue: CampOperation? = nil,
             _ perform: @escaping (Int) async throws -> CampTask) async -> Outcome {
        do {
            return .written(try await BusyState.shared.track { try await perform(task.version) })
        } catch let error as APIError {
            if let conflict = CampRules.versionConflict(error, as: CampTask.self), let current = conflict.current {
                return .conflict(CampTaskConflict(subject: task.title, current: current, mine: mine, retry: perform))
            }
            if error.kind == .network, let queue, let outbox = active.outbox {
                await outbox.enqueue(queue)
                await active.refreshQueue()
                return .queued
            }
            if error.kind == .invalidInput { return .invalid(error.displayText) }
            return .failed(CampRules.writeError(error))
        } catch {
            return .failed(APIError.network.displayText)
        }
    }

    static func statusOperation(_ task: CampTask, _ status: CampTaskStatus) -> CampOperation {
        CampOperation(type: "aufgabe.aendern", payload: [
            "id": .string(task.id.uuidString.lowercased()), "version": .int(task.version), "status": .string(status.rawValue),
        ])
    }
}
