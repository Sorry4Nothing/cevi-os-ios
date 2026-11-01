import Foundation

/// A unit as `GET /stufen` returns it.
nonisolated struct UnitInfo: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let abbreviation: String
    /// Path of the unit's own logo, `nil` without one (then the Cevi logo is shown).
    let logoURL: String?

    enum CodingKeys: String, CodingKey { case id, name, abbreviation = "kuerzel", logoURL = "logoUrl" }
}

nonisolated struct UnitList: Decodable, Sendable {
    let units: [UnitInfo]

    enum CodingKeys: String, CodingKey { case units = "stufen" }
}
