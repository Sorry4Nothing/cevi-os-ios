import Foundation

nonisolated enum CampFormat {
    private static let locale = Locale(identifier: "de_CH")

    private static func part(_ date: Date, year: Bool, month: Bool) -> String {
        var text = "\(DateFormats.calendar.component(.day, from: date))."
        if month { text += " " + date.formatted(Date.FormatStyle(locale: locale, timeZone: DateFormats.timeZone).month(.wide)) }
        if year { text += " " + date.formatted(Date.FormatStyle(locale: locale, timeZone: DateFormats.timeZone).year()) }
        return text
    }

    /// "17. bis 24. Juli 2027", "28. Juni bis 5. Juli 2027" or, across years, with both years.
    static func dates(from: Date, to: Date) -> String {
        let calendar = DateFormats.calendar
        let a = calendar.dateComponents([.year, .month], from: from), b = calendar.dateComponents([.year, .month], from: to)
        let sameYear = a.year == b.year
        let first = part(from, year: !sameYear, month: !sameYear || a.month != b.month)
        return "\(first) bis \(part(to, year: true, month: true))"
    }
}
