import Foundation

/// Builds the redacted snapshot from the answers of the API. Redaction happens HERE: only what the snapshot model has a field
/// for gets through. Names of children (counted only), chat contents, phone numbers and names of other people never do.
nonisolated enum WidgetSnapshotBuilder {
    static let maxTitle = 80

    /// One line, no control characters, at most `maxTitle` characters.
    static func clip(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count > maxTitle ? String(trimmed.prefix(maxTitle - 1)) + "…" : trimmed
    }

    /// First line of the field; dropped when it holds a phone-like number (6 or more digits) or an e-mail address.
    static func meetingPlace(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let line = clip(raw)
        guard !line.isEmpty, line.filter(\.isNumber).count < 6, !line.contains("@") else { return nil }
        return line
    }

    // MARK: Programs (W1, W2)

    private static func effectiveStart(_ program: Program) -> Date? { program.start ?? program.dayFrom }

    private static func isUpcoming(_ program: Program, now: Date) -> Bool {
        guard program.status == .active, let start = effectiveStart(program) else { return false }
        let end = program.end ?? program.dayTo.map { $0.addingTimeInterval(86_400) } ?? start
        return end >= now
    }

    static func events(programs: [Program], now: Date, limit: Int = 5) -> [WidgetEvent] {
        programs.filter { isUpcoming($0, now: now) }
            .sorted { (effectiveStart($0) ?? .distantFuture) < (effectiveStart($1) ?? .distantFuture) }
            .prefix(limit)
            .compactMap { program in
                effectiveStart(program).map {
                    WidgetEvent(
                        id: program.id, title: clip(program.title), start: $0, isAllDay: program.isAllDay,
                        groups: Array((program.units.map(\.name) + program.otherTags.map(\.name)).map(clip).prefix(2))
                    )
                }
            }
    }

    /// The units of the person's children and the units the person leads, each with the next three programs.
    /// `place` is the meeting point of the first program (from the detail), if it was loaded.
    static func units(programs: [Program], profile: Profile, now: Date, places: [UUID: String] = [:]) -> [WidgetUnit] {
        let childUnits = Set(profile.children.map(\.unitId))
        let leaderUnits = Set(profile.roles.map(\.unitId))
        let childUnit = Dictionary(profile.children.map { ($0.id, $0.unitId) }, uniquingKeysWith: { first, _ in first })
        let upcoming = programs.filter { isUpcoming($0, now: now) }
            .sorted { (effectiveStart($0) ?? .distantFuture) < (effectiveStart($1) ?? .distantFuture) }
        return profile.units.filter { childUnits.contains($0.id) || leaderUnits.contains($0.id) }.map { unit in
            let mine = upcoming.filter { $0.units.contains { $0.id == unit.id } }.prefix(3)
            let list = mine.compactMap { program -> WidgetProgram? in
                guard let start = effectiveStart(program) else { return nil }
                let place = meetingPlace(places[program.id] ?? program.meetingPoint ?? program.place)
                return WidgetProgram(
                    id: program.id, title: clip(program.title), start: start, end: program.end, isAllDay: program.isAllDay,
                    place: program.id == mine.first?.id ? place : nil
                )
            }
            let open = mine.first.map { next in
                next.children.filter { childUnit[$0.id] == unit.id && $0.answer == nil }.count
            } ?? 0
            return WidgetUnit(id: unit.id, name: clip(unit.name), isChildUnit: childUnits.contains(unit.id), programs: list, openAnswers: open)
        }
    }

    // MARK: Chat (W6)

    /// Numbers only. Names, previews and texts of the list are not read.
    static func chat(_ chats: [ChatSummary]) -> WidgetChat {
        WidgetChat(unread: ChatRules.totalUnread(chats), chats: chats.filter { $0.unread > 0 }.count)
    }

    // MARK: Camp (W3, W4, W5)

    static func camp(
        _ camp: Camp, today: CampToday?, week: CampMyWeek?, sections: [CampDaySection], tasks: [CampTask]?, personId: UUID, now: Date
    ) -> WidgetCamp {
        let day = DateFormats.calendar
        let duty = (week?.shifts ?? [])
            .first { day.isDate($0.shift.date, inSameDayAs: today?.date ?? now) }
            .map { own in
                WidgetDuty(
                    name: clip(own.duty?.name ?? String(localized: "Dienst")),
                    time: sections.first { $0.id == own.shift.sectionId }?.time.map(clip).flatMap { $0.isEmpty ? nil : $0 }
                )
            }
        let important = (today?.page?.blocks ?? []).filter { $0.kind == .important }.sorted { $0.order < $1.order }
            .map { clip($0.text) }.filter { !$0.isEmpty }.prefix(2)
        let todos = (today?.page?.tasks ?? []).filter { $0.responsibleId == personId }
        // Prefer the full list of the own tasks; without the right to read it, «Meine Woche» still has the near ones.
        let own = (tasks ?? week?.tasks ?? []).filter { $0.responsibleId == personId || tasks == nil }
        let open = own.filter { $0.status != .done }
        let overdue = open.filter { CampTaskText.isOverdue($0, today: now) }
        let ordered = open.sorted { ($0.due ?? .distantFuture, $0.order) < ($1.due ?? .distantFuture, $1.order) }
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        return WidgetCamp(
            id: camp.id, title: clip(camp.title), from: camp.from, to: camp.to, duty: duty, important: Array(important),
            todosOpen: todos.filter { $0.status != .done }.count, todosTotal: todos.count, overdueCount: overdue.count,
            tasks: ordered.prefix(3).map { WidgetTask(id: $0.id, title: clip($0.title), due: $0.due, isOverdue: CampTaskText.isOverdue($0, today: now)) },
            laterCount: tasks == nil ? nil : open.filter { $0.due.map { CampTaskText.days(from: now, to: $0) > 7 } ?? false }.count,
            doneThisWeek: tasks == nil ? nil : own.filter { $0.status == .done && ($0.completedAt ?? .distantPast) >= weekAgo }.count
        )
    }
}
