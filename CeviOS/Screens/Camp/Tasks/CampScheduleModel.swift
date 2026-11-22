import Foundation

/// One line of the schedule: a milestone or the deadline of a task.
nonisolated struct CampScheduleItem: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable { case milestone, deadline }
    let id: UUID
    let title: String
    let date: Date
    let kind: Kind
    /// The task to open for a deadline.
    let taskId: UUID?
}

nonisolated struct CampScheduleWeek: Identifiable, Equatable, Sendable {
    let id: Date
    let title: String
    let items: [CampScheduleItem]
}

nonisolated enum CampCalendarMark: Equatable, Sendable {
    case milestone, deadline, campDay
    var letter: String {
        switch self {
        case .milestone: "M"
        case .deadline: "F"
        case .campDay: "L"
        }
    }
    var name: String {
        switch self {
        case .milestone: String(localized: "Meilenstein")
        case .deadline: String(localized: "Frist")
        case .campDay: String(localized: "Lagertag")
        }
    }
}

nonisolated enum CampScheduleBuilder {
    private static var calendar: Calendar {
        var calendar = DateFormats.calendar
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    static func items(schedule: CampSchedule, tasks: [CampTask]) -> [CampScheduleItem] {
        let milestones = schedule.milestones.map { CampScheduleItem(id: $0.id, title: $0.title, date: $0.date, kind: .milestone, taskId: nil) }
        let deadlines = tasks.filter { $0.status != .done }.compactMap { task in
            task.due.map { CampScheduleItem(id: task.id, title: task.title, date: $0, kind: .deadline, taskId: task.id) }
        }
        return (milestones + deadlines).sorted { ($0.date, $0.title) < ($1.date, $1.title) }
    }

    /// «Woche 11, 15. bis 21. März».
    static func weeks(_ items: [CampScheduleItem]) -> [CampScheduleWeek] {
        let calendar = calendar
        let groups = Dictionary(grouping: items) { calendar.dateInterval(of: .weekOfYear, for: $0.date)?.start ?? $0.date }
        return groups.keys.sorted().map { start in
            let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
            let number = calendar.component(.weekOfYear, from: start)
            return CampScheduleWeek(id: start, title: String(localized: "Woche \(number), \(CampFormat.dates(from: start, to: end))"), items: groups[start] ?? [])
        }
    }

    /// Weeks of the month as rows of seven (Monday first); `nil` for days of the neighbouring months.
    static func monthGrid(for date: Date) -> [[Date?]] {
        let calendar = calendar
        guard let month = calendar.dateInterval(of: .month, for: date) else { return [] }
        let first = calendar.component(.weekday, from: month.start)
        let leading = (first - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: date)?.count ?? 30
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for day in 0..<count { cells.append(calendar.date(byAdding: .day, value: day, to: month.start)) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    static func marks(on date: Date, items: [CampScheduleItem], campDays: [CampDay]) -> [CampCalendarMark] {
        let calendar = calendar
        var result: [CampCalendarMark] = []
        if items.contains(where: { $0.kind == .milestone && calendar.isDate($0.date, inSameDayAs: date) }) { result.append(.milestone) }
        if items.contains(where: { $0.kind == .deadline && calendar.isDate($0.date, inSameDayAs: date) }) { result.append(.deadline) }
        if campDays.contains(where: { calendar.isDate($0.date, inSameDayAs: date) }) { result.append(.campDay) }
        return result
    }
}

/// T3: schedule and month calendar.
@MainActor @Observable
final class CampScheduleModel {
    enum Tab: String, CaseIterable, Identifiable { case schedule, calendar; var id: String { rawValue } }

    let active: ActiveCamp
    var tab: Tab = .schedule
    /// Any day of the month the calendar shows.
    var month: Date
    private(set) var phase: CampPhase = .loading
    private(set) var schedule: CampSchedule?
    private(set) var tasks: [CampTask] = []
    private(set) var isOffline = false
    private(set) var loadedAt: Date?
    @ObservationIgnored var now: () -> Date = { Date() }

    init(active: ActiveCamp) {
        self.active = active
        month = active.camp?.from ?? Date()
    }

    var items: [CampScheduleItem] { schedule.map { CampScheduleBuilder.items(schedule: $0, tasks: tasks) } ?? [] }
    var weeks: [CampScheduleWeek] { CampScheduleBuilder.weeks(items) }
    var isEmpty: Bool { items.isEmpty }

    func setPreview(phase: CampPhase, schedule: CampSchedule?, tasks: [CampTask], offline: Bool = false) {
        self.phase = phase
        self.schedule = schedule
        self.tasks = tasks
        isOffline = offline
        loadedAt = offline ? now() : nil
    }

    func shiftMonth(by value: Int) {
        month = DateFormats.calendar.date(byAdding: .month, value: value, to: month) ?? month
    }

    func load() async {
        guard let client = active.client, let campId = active.camp?.id else { return }
        do {
            schedule = try await client.campSchedule(campId: campId)
            // Deadlines come from the tasks the role may read; without them the schedule shows the milestones only.
            tasks = (try? await client.campTasks(campId: campId, limit: 100).tasks) ?? tasks
            phase = .loaded
            isOffline = false
            loadedAt = now()
        } catch is CancellationError {
        } catch {
            let failure = CampPhase(error: error)
            if schedule != nil, case .failed(.offline?, _) = failure { isOffline = true } else { phase = failure }
        }
    }
}
