import Foundation

/// The six widgets (W1 to W6).
nonisolated enum WidgetKind: String, CaseIterable, Sendable {
    case nextProgram, calendar, campToday, tasks, emergency, chat
}

/// Where in the widget the content sits; decides how many rows fit (`WidgetLayoutPlan`).
nonisolated enum WidgetSize: Sendable {
    case small, medium, large, circular, rectangular, inline
}

/// The state boards of the design: N normal, I never opened, E empty, U signed out, R no camp or role, F error, S redacted.
/// Placeholder (P) and Tag/Nacht/Z are not states of the data: the system draws the placeholder, the look follows the environment.
nonisolated enum WidgetPhase: Equatable, Sendable {
    case content, redacted, neverOpened, empty, signedOut, noCamp, failed
}

/// «Stand 18:02», from 2 hours «Stand vor 2 Std.», without network «Ohne Netz. Stand 18:02.».
nonisolated struct WidgetStand: Equatable, Sendable {
    let text: String
    /// From 2 hours: the line gets a symbol and the warning colour (never colour alone).
    let isStale: Bool
    let isOffline: Bool

    static let staleAfter: TimeInterval = 2 * 3600

    static func make(updatedAt: Date, now: Date, offline: Bool) -> WidgetStand {
        let age = max(0, now.timeIntervalSince(updatedAt))
        let stale = age >= staleAfter
        let text: String
        if offline {
            text = String(localized: "Ohne Netz. \(since(updatedAt, age: age, now: now)).")
        } else {
            text = since(updatedAt, age: age, now: now)
        }
        return WidgetStand(text: text, isStale: stale && !offline, isOffline: offline)
    }

    private static func since(_ date: Date, age: TimeInterval, now: Date) -> String {
        if age < staleAfter {
            return String(localized: "Stand \(WidgetFormat.time(date))")
        }
        let hours = Int(age / 3600)
        if hours < 24 { return String(localized: "Stand vor \(hours) Std.") }
        let days = hours / 24
        return days == 1 ? String(localized: "Stand vor 1 Tag") : String(localized: "Stand vor \(days) Tagen")
    }
}

/// What a widget shows after all rules: the phase and the stand line. The views read their rows from the snapshot.
nonisolated struct WidgetModel: Equatable, Sendable {
    let phase: WidgetPhase
    let stand: WidgetStand?
    let snapshot: WidgetSnapshot?
    /// The unit (W1) or the camp (W3, W4, W5) the widget shows.
    let unit: WidgetUnit?
    let camp: WidgetCamp?

    /// `unitId` and `campId` come from the configuration (WC1, WC2); unknown or `nil` falls back to the first fitting entry.
    static func resolve(
        kind: WidgetKind, snapshot: WidgetSnapshot?, now: Date, privacyRedacted: Bool, unitId: UUID? = nil, campId: UUID? = nil
    ) -> WidgetModel {
        func model(_ phase: WidgetPhase, unit: WidgetUnit? = nil, camp: WidgetCamp? = nil, withStand: Bool = true) -> WidgetModel {
            let stand = withStand ? snapshot.map { WidgetStand.make(updatedAt: $0.updatedAt, now: now, offline: $0.status == .offline) } : nil
            return WidgetModel(phase: phase, stand: stand, snapshot: snapshot, unit: unit, camp: camp)
        }
        guard let snapshot, snapshot.version == WidgetSnapshot.currentVersion else { return model(.neverOpened, withStand: false) }
        if snapshot.session == .signedOut { return model(.signedOut, withStand: false) }
        if snapshot.status == .failed { return model(.failed, withStand: false) }

        let camp = snapshot.camps.first { $0.id == campId } ?? snapshot.camps.first
        let unit = snapshot.units.first { $0.id == unitId && !$0.programs.isEmpty }
            ?? snapshot.units.filter { !$0.programs.isEmpty }.min { $0.programs[0].start < $1.programs[0].start }
        let hidden = privacyRedacted || snapshot.hidesContent

        let phase: WidgetPhase
        switch kind {
        case .nextProgram: phase = unit == nil ? .empty : (hidden ? .redacted : .content)
        case .calendar: phase = snapshot.events.isEmpty ? .empty : (hidden ? .redacted : .content)
        case .campToday:
            phase = camp == nil ? .noCamp : (camp.map(Self.hasToday) == true ? (hidden ? .redacted : .content) : .empty)
        case .tasks:
            phase = camp == nil ? .noCamp : (camp.map(Self.hasTasks) == true ? (hidden ? .redacted : .content) : .empty)
        case .emergency: phase = camp == nil ? .noCamp : .content
        case .chat: phase = (snapshot.chat?.unread ?? 0) == 0 ? .empty : (hidden ? .redacted : .content)
        }
        // The emergency widget needs no data and shows no stand.
        return model(phase, unit: unit, camp: camp, withStand: kind != .emergency)
    }

    static func hasToday(_ camp: WidgetCamp) -> Bool { camp.duty != nil || !camp.important.isEmpty || camp.todosTotal > 0 }
    static func hasTasks(_ camp: WidgetCamp) -> Bool { camp.overdueCount > 0 || !camp.tasks.isEmpty }
}

/// How many rows fit. Large type (accessibility sizes) halves the rows instead of cutting text.
nonisolated enum WidgetLayoutPlan {
    struct Plan: Equatable, Sendable {
        var rows: Int
        var showsPlace: Bool
        var showsGroups: Bool
        var showsLater: Bool
    }

    static func nextProgram(_ size: WidgetSize, largeType: Bool) -> Plan {
        switch size {
        case .small: Plan(rows: 0, showsPlace: false, showsGroups: true, showsLater: false)
        case .medium: Plan(rows: 0, showsPlace: !largeType, showsGroups: true, showsLater: false)
        case .large: Plan(rows: largeType ? 0 : 2, showsPlace: true, showsGroups: true, showsLater: !largeType)
        default: Plan(rows: 0, showsPlace: false, showsGroups: false, showsLater: false)
        }
    }

    static func calendar(_ size: WidgetSize, largeType: Bool) -> Plan {
        let rows: Int
        switch size {
        case .small: rows = 1
        case .medium: rows = largeType ? 1 : 3
        case .large: rows = largeType ? 3 : 5
        default: rows = 1
        }
        return Plan(rows: rows, showsPlace: false, showsGroups: !largeType || size == .large, showsLater: false)
    }

    static func tasks(_ size: WidgetSize, largeType: Bool) -> Plan {
        let rows: Int
        switch size {
        case .small: rows = 1
        case .medium: rows = largeType ? 1 : 2
        case .large: rows = largeType ? 2 : 3
        default: rows = 1
        }
        return Plan(rows: rows, showsPlace: false, showsGroups: false, showsLater: size == .large && !largeType)
    }

    static func campToday(_ size: WidgetSize, largeType: Bool) -> Plan {
        let rows: Int
        switch size {
        case .large: rows = largeType ? 1 : 2
        case .medium: rows = largeType ? 0 : 1
        default: rows = 0
        }
        return Plan(rows: rows, showsPlace: false, showsGroups: false, showsLater: size == .large && !largeType)
    }
}

/// Deep links of the widgets: `cevios://open?typ=…&id=…`. `typ` and `id` are read like the data of a push (`PushTarget`).
nonisolated enum WidgetLink {
    static func url(typ: String? = nil, id: UUID? = nil) -> URL {
        var components = URLComponents()
        components.scheme = "cevios"
        components.host = "open"
        var items: [URLQueryItem] = []
        if let typ { items.append(URLQueryItem(name: "typ", value: typ)) }
        if let id { items.append(URLQueryItem(name: "id", value: id.uuidString.lowercased())) }
        components.queryItems = items.isEmpty ? nil : items
        return components.url ?? URL(string: "cevios://open")!
    }

    /// The push-style data of a link; `nil` for a foreign scheme or host.
    static func userInfo(from url: URL) -> [AnyHashable: Any]? {
        guard url.scheme == "cevios", url.host() == "open" else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        var info: [AnyHashable: Any] = [:]
        for item in items where item.name == "typ" || item.name == "id" { info[item.name] = item.value }
        return info
    }
}

/// Texts of dates in Swiss form. Fixed names instead of the system format: the result is the same on every device.
nonisolated enum WidgetFormat {
    private static let weekdays = ["Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"]
    private static let months = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"]
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich") ?? .current
        return calendar
    }

    private static func parts(_ date: Date) -> DateComponents {
        calendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: date)
    }

    /// «18:02»
    static func time(_ date: Date) -> String {
        let c = parts(date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// «Sa» (first two letters of the weekday).
    static func shortWeekday(_ date: Date) -> String { String(weekdays[(parts(date).weekday ?? 1) - 1].prefix(2)) }

    static func longWeekday(_ date: Date) -> String { weekdays[(parts(date).weekday ?? 1) - 1] }

    /// «14.11.»
    static func shortDay(_ date: Date) -> String {
        let c = parts(date)
        return "\(c.day ?? 0).\(c.month ?? 0)."
    }

    /// «Sa 14.11., 14:00» (all day: «Sa 14.11.»)
    static func shortDateTime(_ date: Date, allDay: Bool = false) -> String {
        allDay ? "\(shortWeekday(date)) \(shortDay(date))" : "\(shortWeekday(date)) \(shortDay(date)), \(time(date))"
    }

    /// «Samstag, 14. November, 14:00–17:00»
    static func longRange(start: Date, end: Date?, allDay: Bool) -> String {
        let c = parts(start)
        let day = "\(longWeekday(start)), \(c.day ?? 0). \(months[(c.month ?? 1) - 1])"
        if allDay { return day }
        guard let end, end > start else { return "\(day), \(time(start))" }
        return "\(day), \(time(start))–\(time(end))"
    }

    /// «Samstag, 14. November»
    static func longDay(_ date: Date) -> String {
        let c = parts(date)
        return "\(longWeekday(date)), \(c.day ?? 0). \(months[(c.month ?? 1) - 1])"
    }

    /// «Samstag, 14:00» (redacted form: kind of the day and time only).
    static func redactedStart(_ date: Date, allDay: Bool) -> String {
        allDay ? longWeekday(date) : "\(longWeekday(date)), \(time(date))"
    }

    /// «15. März»
    static func dueDay(_ date: Date) -> String {
        let c = parts(date)
        return "\(c.day ?? 0). \(months[(c.month ?? 1) - 1])"
    }

    /// «17. bis 24. Juli 2027» (the same month and year once).
    static func campRange(from: Date, to: Date) -> String {
        let a = parts(from), b = parts(to)
        let end = "\(b.day ?? 0). \(months[(b.month ?? 1) - 1]) \(b.year ?? 0)"
        if a.year == b.year, a.month == b.month { return "\(a.day ?? 0). bis \(end)" }
        return "\(a.day ?? 0). \(months[(a.month ?? 1) - 1]) bis \(end)"
    }

    /// Day number of `date` in the camp from 1, and the number of days; `nil` outside the camp.
    static func campDay(_ date: Date, from: Date, to: Date) -> (day: Int, of: Int)? {
        let cal = calendar
        let start = cal.startOfDay(for: from), end = cal.startOfDay(for: to), today = cal.startOfDay(for: date)
        guard today >= start, today <= end else { return nil }
        let day = (cal.dateComponents([.day], from: start, to: today).day ?? 0) + 1
        let total = (cal.dateComponents([.day], from: start, to: end).day ?? 0) + 1
        return (day, total)
    }
}
