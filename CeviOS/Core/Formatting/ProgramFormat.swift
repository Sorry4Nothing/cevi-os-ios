import Foundation

nonisolated enum ProgramFormat {
    /// "Ganztägig", "14:00–17:00" or, for multi-day programs, with start and end on the right days.
    static func time(of program: Program, on day: Date) -> String {
        if program.isAllDay { return String(localized: "Ganztägig") }
        guard let start = program.start, let end = program.end else { return "" }
        let calendar = DateFormats.calendar
        let style = Date.FormatStyle(date: .omitted, time: .shortened, locale: Locale(identifier: "de_CH"), timeZone: DateFormats.timeZone)
        let startsToday = calendar.isDate(start, inSameDayAs: day)
        let endsToday = calendar.isDate(end, inSameDayAs: day)
        switch (startsToday, endsToday) {
        case (true, true): return "\(start.formatted(style))–\(end.formatted(style))"
        case (true, false): return String(localized: "ab \(start.formatted(style))")
        case (false, true): return String(localized: "bis \(end.formatted(style))")
        case (false, false): return String(localized: "Ganztägig")
        }
    }

    private static let locale = Locale(identifier: "de_CH")

    /// "SA" for the timeline.
    static func weekday(_ day: Date) -> String {
        day.formatted(Date.FormatStyle(locale: locale, timeZone: DateFormats.timeZone).weekday(.abbreviated))
            .replacingOccurrences(of: ".", with: "").uppercased()
    }

    /// "Samstag, 14. November 2026" for VoiceOver.
    static func fullDate(_ day: Date) -> String {
        day.formatted(Date.FormatStyle(date: .complete, time: .omitted, locale: locale, timeZone: DateFormats.timeZone))
    }

    /// "Sa., 14. November" for the detail subtitle.
    static func shortDate(_ day: Date) -> String {
        day.formatted(Date.FormatStyle(locale: locale, timeZone: DateFormats.timeZone).weekday(.abbreviated).day().month(.wide))
    }

    /// "14:00" in Swiss time.
    static func clock(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: DateFormats.timeZone))
    }
}
