import Foundation

/// Role of a person in a unit. A unit leader also has all rights of a leader of the same unit.
/// Raw values are the wire values of the API.
nonisolated enum RoleType: String, Decodable, Sendable {
    case leader = "leitung"
    case unitLeader = "stufenleitung"
}

nonisolated struct Role: Decodable, Equatable, Sendable {
    let unitId: UUID
    let type: RoleType

    enum CodingKeys: String, CodingKey {
        case unitId = "stufeId"
        case type = "typ"
    }
}

nonisolated struct UnitSummary: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let abbreviation: String

    enum CodingKeys: String, CodingKey {
        case id, name
        case abbreviation = "kuerzel"
    }
}

nonisolated struct Child: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let firstName: String
    let lastName: String
    let unitId: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case firstName = "vorname"
        case lastName = "nachname"
        case unitId = "stufeId"
    }
}

/// Response of `GET /api/v1/ich`. The app derives from it what the person sees.
nonisolated struct Profile: Decodable, Equatable, Sendable {
    let id: UUID
    let name: String
    let ceviName: String?
    let username: String?
    let mustChangePassword: Bool
    let privacyReadAt: Date?
    let phone: String?
    let imageURL: String?
    let pushChat: Bool
    let pushPrograms: Bool
    /// Missing for people without a unit role.
    let pushRegistrations: Bool?
    let admin: Bool
    let secondFactor: Bool
    let roles: [Role]
    let units: [UnitSummary]
    let children: [Child]

    enum CodingKeys: String, CodingKey {
        case id, name, ceviName, admin, pushChat
        case username = "benutzername"
        case mustChangePassword = "mussPasswortAendern"
        case privacyReadAt = "datenschutzGelesenAm"
        case phone = "telefon"
        case imageURL = "bildUrl"
        case pushPrograms = "pushProgramme"
        case pushRegistrations = "pushAnmeldungen"
        case secondFactor = "zweiterFaktor"
        case roles = "rollen"
        case units = "stufen"
        case children = "kinder"
    }

    /// Leaders and unit leaders have at least one unit role.
    var isLeader: Bool { !roles.isEmpty }

    func isUnitLeader(of unitId: UUID) -> Bool {
        roles.contains { $0.unitId == unitId && $0.type == .unitLeader }
    }

    func isLeader(of unitId: UUID) -> Bool {
        roles.contains { $0.unitId == unitId }
    }

    var isUnitLeader: Bool { roles.contains { $0.type == .unitLeader } }
}
