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

/// `clientArt`: how the server rates the client of the session. An unknown value decodes as `.unknown`.
nonisolated enum ClientKind: String, CampTolerantEnum {
    case web
    case verifiedApp = "app_nachgewiesen"
    case unverifiedApp = "app_ungeprueft"
    case unknown

    static var fallback: Self { .unknown }
}

/// A right of the person from the catalogue, for example `kinder.verwalten`. The server may add rights.
nonisolated struct ProfileRight: Decodable, Equatable, Sendable {
    let name: String
    /// `alle` or `eigene` (only the groups of the person's roles). Kept as a string: the server may add values.
    let scope: String

    enum CodingKeys: String, CodingKey { case name = "recht", scope = "geltung" }
}

/// Only for the own account of a child (participant). Such an account has no role, no department lead and no admin area.
nonisolated struct ParticipantAccount: Decodable, Equatable, Sendable {
    let childId: UUID
    let unitId: UUID
    /// `false` if the child is inactive: the account then sees nothing.
    let isActive: Bool
    /// What the account may do in the group chat of its unit: `aus`, `lesen` or `schreiben`.
    let chat: String

    enum CodingKeys: String, CodingKey { case childId = "kindId", unitId = "stufeId", isActive = "aktiv", chat }
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
    /// Department lead. Replaces the field `admin`, which the server dropped without alias.
    let isDepartmentLead: Bool
    let isDeveloper: Bool
    let clientKind: ClientKind
    let rights: [ProfileRight]
    /// Set only for the own account of a child.
    let participant: ParticipantAccount?
    let roles: [Role]
    let units: [UnitSummary]
    let children: [Child]

    enum CodingKeys: String, CodingKey {
        case id, name, ceviName, pushChat, participant = "teilnehmer"
        case isDepartmentLead = "abteilungsleitung", isDeveloper = "entwickler", clientKind = "clientArt", rights = "rechte"
        case username = "benutzername"
        case mustChangePassword = "mussPasswortAendern"
        case privacyReadAt = "datenschutzGelesenAm"
        case phone = "telefon"
        case imageURL = "bildUrl"
        case pushPrograms = "pushProgramme"
        case pushRegistrations = "pushAnmeldungen"
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

    /// Department leads who are neither parents nor leaders do not use the app.
    var isAdminOnly: Bool { isDepartmentLead && children.isEmpty && roles.isEmpty }

    var isUnitLeader: Bool { roles.contains { $0.type == .unitLeader } }
}

nonisolated extension Profile {
    /// The new fields are read tolerantly: a missing key must not break the sign-in.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        ceviName = try c.decodeIfPresent(String.self, forKey: .ceviName)
        username = try c.decodeIfPresent(String.self, forKey: .username)
        mustChangePassword = try c.decode(Bool.self, forKey: .mustChangePassword)
        privacyReadAt = try c.decodeIfPresent(Date.self, forKey: .privacyReadAt)
        phone = try c.decodeIfPresent(String.self, forKey: .phone)
        imageURL = try c.decodeIfPresent(String.self, forKey: .imageURL)
        pushChat = try c.decode(Bool.self, forKey: .pushChat)
        pushPrograms = try c.decode(Bool.self, forKey: .pushPrograms)
        pushRegistrations = try c.decodeIfPresent(Bool.self, forKey: .pushRegistrations)
        isDepartmentLead = try c.decodeIfPresent(Bool.self, forKey: .isDepartmentLead) ?? false
        isDeveloper = try c.decodeIfPresent(Bool.self, forKey: .isDeveloper) ?? false
        clientKind = try c.decodeIfPresent(ClientKind.self, forKey: .clientKind) ?? .unknown
        rights = try c.decodeIfPresent([ProfileRight].self, forKey: .rights) ?? []
        participant = try c.decodeIfPresent(ParticipantAccount.self, forKey: .participant)
        roles = try c.decode([Role].self, forKey: .roles)
        units = try c.decode([UnitSummary].self, forKey: .units)
        children = try c.decode([Child].self, forKey: .children)
    }
}
