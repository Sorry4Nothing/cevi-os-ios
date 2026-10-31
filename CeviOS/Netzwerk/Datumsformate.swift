import Foundation

/// Zeitpunkte sind ISO-8601 in UTC, Kalendertage `JJJJ-MM-TT` (Schweizer Kalendertage).
nonisolated enum Datumsformate {
    static let zeitzone = TimeZone(identifier: "Europe/Zurich") ?? .current

    private static var kalender: Calendar {
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = zeitzone
        return kalender
    }

    /// Zeitpunkt wie `2026-11-07T14:00:00Z`, mit oder ohne Sekundenbruchteile.
    static func zeitpunkt(_ text: String) -> Date? {
        if let datum = try? Date(text, strategy: .iso8601) { return datum }
        return try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }

    static func zeitpunktText(_ datum: Date) -> String {
        datum.formatted(.iso8601)
    }

    /// Kalendertag wie `2026-11-07`, als Mitternacht in der Schweizer Zeitzone.
    static func kalendertag(_ text: String) -> Date? {
        let teile = text.split(separator: "-", omittingEmptySubsequences: false).compactMap { Int($0) }
        guard text.count == 10, teile.count == 3 else { return nil }
        let komponenten = DateComponents(year: teile[0], month: teile[1], day: teile[2])
        guard let datum = kalender.date(from: komponenten),
              kalender.dateComponents([.year, .month, .day], from: datum) == komponenten
        else { return nil }
        return datum
    }

    static func kalendertagText(_ datum: Date) -> String {
        let k = kalender.dateComponents([.year, .month, .day], from: datum)
        return String(format: "%04d-%02d-%02d", k.year ?? 0, k.month ?? 0, k.day ?? 0)
    }
}

extension JSONDecoder {
    /// Decoder für die API: Zeitpunkte und Kalendertage werden zu `Date`.
    nonisolated static var api: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let datum = Datumsformate.zeitpunkt(text) ?? Datumsformate.kalendertag(text) {
                return datum
            }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Ungültiges Datum"))
        }
        return decoder
    }
}

extension JSONEncoder {
    nonisolated static var api: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { datum, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Datumsformate.zeitpunktText(datum))
        }
        return encoder
    }
}
