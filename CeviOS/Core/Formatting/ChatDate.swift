import Foundation

/// Short time stamps in Swiss German: today the time, yesterday "Gestern", this week the weekday, else the date.
nonisolated enum ChatDate {
    private static let locale = Locale(identifier: "de_CH")

    static func time(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: DateFormats.timeZone))
    }

    static func listStamp(_ date: Date, now: Date = .now) -> String {
        let calendar = DateFormats.calendar
        if calendar.isDate(date, inSameDayAs: now) { return time(date) }
        if calendar.isDateInYesterday(date) { return String(localized: "Gestern") }
        if let days = calendar.dateComponents([.day], from: date, to: now).day, days < 7 {
            return date.formatted(Date.FormatStyle(locale: locale, timeZone: DateFormats.timeZone).weekday(.abbreviated))
        }
        return date.formatted(Date.FormatStyle(date: .numeric, time: .omitted, locale: locale, timeZone: DateFormats.timeZone))
    }

    static func day(_ date: Date) -> String {
        let calendar = DateFormats.calendar
        if calendar.isDateInToday(date) { return String(localized: "Heute") }
        if calendar.isDateInYesterday(date) { return String(localized: "Gestern") }
        return date.formatted(Date.FormatStyle(date: .long, time: .omitted, locale: locale, timeZone: DateFormats.timeZone))
    }
}
