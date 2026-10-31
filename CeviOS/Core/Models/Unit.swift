import Foundation

/// A unit as `GET /stufen` returns it.
nonisolated struct UnitInfo: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let abbreviation: String

    enum CodingKeys: String, CodingKey { case id, name, abbreviation = "kuerzel" }
}

nonisolated struct UnitList: Decodable, Sendable {
    let units: [UnitInfo]

    enum CodingKeys: String, CodingKey { case units = "stufen" }
}
