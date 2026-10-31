import Foundation

/// Timestamps are ISO 8601 in UTC, calendar days `YYYY-MM-DD` (Swiss calendar days).
nonisolated enum DateFormats {
    static let timeZone = TimeZone(identifier: "Europe/Zurich") ?? .current

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// Timestamp like `2026-11-07T14:00:00Z`, with or without fractional seconds.
    static func timestamp(_ text: String) -> Date? {
        if let date = try? Date(text, strategy: .iso8601) { return date }
        return try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }

    static func timestampText(_ date: Date) -> String {
        date.formatted(.iso8601)
    }

    /// Calendar day like `2026-11-07`, as midnight in the Swiss time zone.
    static func calendarDay(_ text: String) -> Date? {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false).compactMap { Int($0) }
        guard text.count == 10, parts.count == 3 else { return nil }
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard let date = calendar.date(from: components),
              calendar.dateComponents([.year, .month, .day], from: date) == components
        else { return nil }
        return date
    }

    static func calendarDayText(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

extension JSONDecoder {
    /// Decoder for the API: timestamps and calendar days become `Date`.
    nonisolated static var api: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = DateFormats.timestamp(text) ?? DateFormats.calendarDay(text) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Ungültiges Datum"))
        }
        return decoder
    }
}

extension JSONEncoder {
    nonisolated static var api: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(DateFormats.timestampText(date))
        }
        return encoder
    }
}
