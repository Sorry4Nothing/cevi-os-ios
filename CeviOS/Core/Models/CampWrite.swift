import Foundation

/// A row and the version the app last saw. Used for the order of lists and for confirmations.
nonisolated struct CampVersionRef: Encodable, Equatable, Sendable {
    let id: UUID
    let version: Int
}

/// Body of the `…/reihenfolge` routes: the position in the list is the new order.
nonisolated struct CampOrderBody: Encodable, Sendable {
    let entries: [CampVersionRef]

    enum CodingKeys: String, CodingKey { case entries = "eintraege" }
}

/// A calendar day in a request (`YYYY-MM-DD`, Swiss calendar day), not a timestamp.
nonisolated struct CampCalendarDay: Encodable, Equatable, Sendable {
    let date: Date

    init(_ date: Date) { self.date = date }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(DateFormats.calendarDayText(date))
    }
}

/// A field of a PATCH body that is sent: a value, or `null` to clear it. Not sent: the property stays `nil`
/// (declare it as `CampField<T>?`).
nonisolated enum CampField<Value: Encodable & Sendable>: Encodable, Sendable {
    case set(Value)
    case clear

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .set(let value): try container.encode(value)
        case .clear: try container.encodeNil()
        }
    }
}

/// A person as the server resolves it on reading (names are looked up, not stored in the row).
nonisolated struct CampPersonRef: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String?
    let ceviName: String?
}

/// 409 `VERSION_KONFLIKT`: the row changed since the app read it. The app shows both versions and lets the person choose.
nonisolated struct CampVersionConflict<Row: Decodable & Sendable>: Decodable, Sendable {
    let message: String
    /// The row as it stands now, in the view of the role. `nil` if the answer carried a shape the app does not know.
    let current: Row?
    /// Names of the fields that differ from the version the app sent (JSON names).
    let differing: [String]

    enum CodingKeys: String, CodingKey { case message, current = "aktuell", differing = "abweichend" }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decode(String.self, forKey: .message)
        current = try? container.decode(Row.self, forKey: .current)
        differing = try container.decode([String].self, forKey: .differing)
    }
}
