import SwiftUI

/// What the role may do in the on-site screens (attendance, shopping, packing, infos). The defaults of the rights matrix
/// (`docs/lager.md`): the app shows only these actions, the server decides again. A missing action is a missing button.
nonisolated struct CampOnSiteRights: Equatable, Sendable {
    let role: CampRole?
    /// The camp is completed or archived.
    let readOnly: Bool

    private var isLead: Bool { role == .campLeader }
    private var isLeadership: Bool { role == .campLeader || role == .leader }

    /// The camp leadership reads and sets the whole matrix; everybody else sees the own row.
    var readsMatrix: Bool { isLead }
    var setsAttendance: Bool { !readOnly && (isLeadership || role == .team) }
    var decidesRequests: Bool { !readOnly && isLead }
    /// The shopping list is not for the team (the server answers 403 by default).
    var seesShopping: Bool { isLeadership }
    var editsShopping: Bool { !readOnly && isLeadership }
    /// Everybody with a role ticks the own copy; only the camp leadership writes the template.
    var ticksPacking: Bool { !readOnly && role != nil && role != .readOnly }
    var editsPackingTemplate: Bool { !readOnly && isLead }
    var reordersInfos: Bool { !readOnly && isLead }
    /// Some info sections are for the camp leadership only: the others are told that they see the rest.
    var seesAllInfos: Bool { isLeadership }
}

extension CampRosterModel {
    var onSite: CampOnSiteRights { CampOnSiteRights(role: active.role, readOnly: active.isReadOnly) }
}

nonisolated enum CampOnSiteText {
    private static func style() -> Date.FormatStyle { Date.FormatStyle(locale: Locale(identifier: "de_CH"), timeZone: DateFormats.timeZone) }

    /// «Mittwoch, 19. Juli».
    static func dayTitle(_ date: Date) -> String { date.formatted(style().weekday(.wide).day().month(.wide)) }

    /// «Tag 3 von 8, Mittwoch, 19. Juli»; outside the camp only the date.
    static func campDay(_ date: Date, from: Date, to: Date) -> String {
        let number = CampTaskText.days(from: from, to: date) + 1
        let total = CampTaskText.days(from: from, to: to) + 1
        guard number >= 1, number <= total else { return dayTitle(date) }
        return String(localized: "Tag \(number) von \(total), \(dayTitle(date))")
    }

    /// «07:00–10:00» becomes «07:00 bis 10:00».
    static func timeRange(_ text: String?) -> String? {
        guard let text = CampRosterText.trimmed(text) else { return nil }
        return text.replacingOccurrences(of: "–", with: " bis ").replacingOccurrences(of: "-", with: " bis ")
    }

    /// «Sonnig, 24 Grad».
    static func weather(_ day: CampWeatherDay) -> String? {
        var parts: [String] = []
        if let condition = CampRosterText.trimmed(day.condition) { parts.append(condition) }
        if let max = day.maxTemperature { parts.append(String(localized: "\(Int(max.rounded())) Grad")) }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// «Gewitter möglich», for the first warning of a day the app knows.
    static func warning(_ warning: CampWeatherWarning) -> String? {
        switch warning {
        case .thunderstorm: String(localized: "Gewitter möglich")
        case .gusts: String(localized: "Starke Böen möglich")
        case .heat: String(localized: "Grosse Hitze möglich")
        case .rain: String(localized: "Starker Regen möglich")
        case .unknown: nil
        }
    }

    /// «6 kg», «12»; without an amount `nil`.
    static func amount(_ amount: Double?, unit: String?) -> String? {
        guard let amount else { return nil }
        let number = amount.formatted(.number.locale(Locale(identifier: "de_CH")).precision(.fractionLength(0...3)).grouping(.never))
        guard let unit = CampRosterText.trimmed(unit) else { return number }
        return "\(number) \(unit)"
    }

    static func value(_ value: CampAttendanceValue) -> String {
        switch value {
        case .present: String(localized: "Da")
        case .absent: String(localized: "Frei")
        case .open: String(localized: "Offen")
        }
    }

    static func person(name: String?, ceviName: String?) -> String { CampRosterText.label(name: name, ceviName: ceviName) }
}

/// A big row button of the on-site screens: symbol, title and an optional second line.
struct CampOnSiteCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .ceviCard()
            .overlay(Radius.shape(Radius.md).stroke(Color.ceviOutlineVariant, lineWidth: Size.border))
    }
}

/// Section heading of the on-site screens.
struct CampSectionTitle: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text).font(.subheadline.bold()).foregroundStyle(Color.ceviOnSurfaceVariant)
            .frame(maxWidth: .infinity, alignment: .leading).accessibilityAddTraits(.isHeader)
    }
}

/// The to-dos of a day: shared by «Heute» (L4) and the day page (L27). Ticking and moving to the next day.
@MainActor @Observable
class CampTodoModel: CampRosterModel {
    let personId: UUID
    var todos: [CampTask] = []
    /// Ticked while offline: the change waits in the queue («Wartet»).
    var queuedIds: Set<UUID> = []
    /// The status shown for a task whose change waits in the queue.
    private var queuedStatus: [UUID: CampTaskStatus] = [:]

    func isDone(_ task: CampTask) -> Bool { (queuedStatus[task.id] ?? task.status) == .done }

    init(active: ActiveCamp, personId: UUID) {
        self.personId = personId
        super.init(active: active)
    }

    var taskRights: CampTaskRights { CampTaskRights(role: active.role, readOnly: active.isReadOnly, personId: personId) }

    func toggle(_ task: CampTask) async {
        let status: CampTaskStatus = task.status == .done ? .open : .done
        await write(task, mine: [(.status, CampTaskText.statusName(status))], queue: CampTaskWriter.statusOperation(task, status), queuedAs: status,
                    allowed: taskRights.canSetStatus(task)) {
            try await $0.setCampTaskStatus(campId: $1, taskId: task.id, version: $2, status: status)
        }
    }

    /// «In den nächsten Tag schieben»: the deadline moves by one day.
    func postpone(_ task: CampTask) async {
        guard let due = task.due else { return }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = DateFormats.timeZone
        guard let next = calendar.date(byAdding: .day, value: 1, to: due) else { return }
        await write(task, mine: [(.due, CampTaskText.day(next))], queue: nil, queuedAs: nil, allowed: taskRights.canEdit) {
            try await $0.updateCampTask(campId: $1, taskId: task.id, CampTaskPatch(version: $2, due: .set(CampCalendarDay(next))))
        }
        // The task no longer belongs to this day.
        if !queuedIds.contains(task.id), error == nil { todos.removeAll { $0.id == task.id } }
    }

    private func write(_ task: CampTask, mine: [(field: CampTaskField, text: String)], queue: CampOperation?, queuedAs: CampTaskStatus?, allowed: Bool,
                       _ perform: @escaping (APIClient, UUID, Int) async throws -> CampTask) async {
        guard allowed, let client = active.client, let campId = active.camp?.id else { return }
        let outcome = await CampTaskWriter(active: active).run(task, mine: mine, queue: queue) { try await perform(client, campId, $0) }
        switch outcome {
        case .written(let written):
            error = nil
            queuedIds.remove(task.id)
            queuedStatus[task.id] = nil
            if let index = todos.firstIndex(where: { $0.id == task.id }) { todos[index] = written }
        case .queued:
            queuedIds.insert(task.id)
            queuedStatus[task.id] = queuedAs
        case .conflict:
            error = String(localized: "Jemand hat das gerade geändert. Die Liste wird neu geladen.")
            await load()
        case .invalid(let text), .failed(let text):
            error = text
        }
    }
}
