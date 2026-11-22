import Foundation

// The emergency window must work with the last loaded data (also without network): all models here are `Codable`,
// so a later local cache can store them as they are. Phone numbers and addresses appear only in these models and in
// screens of the camp members, never in logs, analytics, widgets or notifications.

/// An info section (house rules, arrival, and so on). `isEmergency` puts it into the emergency window.
nonisolated struct CampInfo: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let version: Int
    let title: String
    let text: String?
    /// Only `https` addresses; the server never opens them.
    let links: [CampInfoLink]
    /// Only for roles that may read confidential rows.
    let leadershipOnly: Bool
    let isEmergency: Bool
    let order: Int
    /// Links to files, never content.
    let files: [CampFileRef]

    enum CodingKeys: String, CodingKey {
        case id, version, text, links, title = "titel", leadershipOnly = "nurLagerleitung", isEmergency = "notfall"
        case order = "reihenfolge", files = "dateien"
    }
}

/// Title and `https` address, the same shape as a link of an agenda item.
typealias CampInfoLink = CampAgendaLink

nonisolated struct CampInfoPage: Codable, Equatable, Sendable {
    let sections: [CampInfo]
    let next: UUID?

    enum CodingKeys: String, CodingKey { case sections = "abschnitte", next = "naechster" }
}

nonisolated struct CampInfoCreate: Encodable, Sendable {
    /// Up to 200 characters.
    var title: String
    /// Up to 20000 characters.
    var text: String?
    var links: [CampInfoLink]?
    var leadershipOnly: Bool?
    var isEmergency: Bool?
    var order: Int?
    /// Files that exist already as links (`CampFileRef`).
    var fileIds: [UUID]?

    enum CodingKeys: String, CodingKey {
        case text, links, title = "titel", leadershipOnly = "nurLagerleitung", isEmergency = "notfall", order = "reihenfolge", fileIds = "dateiIds"
    }
}

nonisolated struct CampInfoPatch: Encodable, Sendable {
    let version: Int
    var title: String?
    var text: CampField<String>?
    var links: [CampInfoLink]?
    var leadershipOnly: Bool?
    var isEmergency: Bool?
    var order: Int?
    var fileIds: [UUID]?

    enum CodingKeys: String, CodingKey {
        case version, text, links, title = "titel", leadershipOnly = "nurLagerleitung", isEmergency = "notfall", order = "reihenfolge", fileIds = "dateiIds"
    }
}

// MARK: Emergency window (Notfall)

/// Where the camp is. `mapLink` is the link of a maps app the camp leadership stored; the server never opens it.
nonisolated struct CampEmergencyAddress: Codable, Equatable, Sendable {
    let place: String?
    let address: String?
    let mapLink: URL?

    enum CodingKeys: String, CodingKey { case place = "ort", address = "adresse", mapLink = "kartenLink" }

    /// What opens the route to the camp: the stored map link, else a route in Apple Maps to the address text,
    /// else `nil` (no address known).
    var routeURL: URL? {
        if let mapLink, mapLink.scheme == "https" { return mapLink }
        let text = [address, place].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: ", ")
        guard !text.isEmpty else { return nil }
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [URLQueryItem(name: "daddr", value: text), URLQueryItem(name: "dirflg", value: "d")]
        return components?.url
    }
}

nonisolated enum CampEmergencyContactSource: String, CampTolerantEnum {
    /// Entered by the camp leadership (has `id` and `version`).
    case entry = "eintrag"
    /// The leader or deputy of the portfolio for emergencies; the number comes from the account.
    case portfolio = "ressort"
    case unknown

    static var fallback: Self { .unknown }
}

nonisolated struct CampEmergencyContact: Codable, Equatable, Sendable {
    let source: CampEmergencyContactSource
    /// Only for an entered contact.
    let id: UUID?
    let version: Int?
    /// The role, for example the function in the camp.
    let function: String
    let personId: UUID?
    let name: String
    let ceviName: String?
    /// The own number of the entry, else the number of the account; `nil` without one.
    let phone: String?
    let order: Int?

    enum CodingKeys: String, CodingKey {
        case id, version, name, ceviName, personId, source = "quelle", function = "funktion", phone = "telefon", order = "reihenfolge"
    }

    /// `tel:` address for a call: digits and a leading plus only. `nil` without a usable number.
    var phoneURL: URL? {
        guard let phone else { return nil }
        let digits = phone.filter { $0.isASCII && ($0.isNumber || $0 == "+") }
        guard digits.contains(where: \.isNumber) else { return nil }
        return URL(string: "tel:" + digits)
    }
}

/// Everything for an emergency in one answer: address, contacts and the info sections marked for emergencies.
nonisolated struct CampEmergency: Codable, Equatable, Sendable {
    let address: CampEmergencyAddress
    let contacts: [CampEmergencyContact]
    let infos: [CampInfo]

    enum CodingKeys: String, CodingKey { case address = "adresse", contacts = "kontakte", infos }
}

nonisolated struct CampMapLinkResult: Codable, Equatable, Sendable {
    let mapLink: URL?

    enum CodingKeys: String, CodingKey { case mapLink = "kartenLink" }
}

/// `nil` removes the link. Sent as `null`.
nonisolated struct CampMapLinkBody: Encodable, Sendable {
    /// `https` address without credentials, up to 2048 characters.
    let mapLink: URL?

    enum CodingKeys: String, CodingKey { case mapLink = "kartenLink" }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mapLink, forKey: .mapLink)
    }
}

nonisolated struct CampEmergencyContactCreate: Encodable, Sendable {
    /// Up to 100 characters.
    var function: String
    /// A member of the camp (the number comes from the account), else 400 `KEIN_MITGLIED`.
    var personId: UUID?
    /// A name without an account; needs `phone`.
    var name: String?
    var phone: String?
    var order: Int?

    enum CodingKeys: String, CodingKey { case name, personId, function = "funktion", phone = "telefon", order = "reihenfolge" }
}

/// An account stays an account (no `name`). `phone` `.clear` gives back the number of the account.
nonisolated struct CampEmergencyContactPatch: Encodable, Sendable {
    let version: Int
    var function: String?
    var name: String?
    var phone: CampField<String>?
    var order: Int?

    enum CodingKeys: String, CodingKey { case version, name, function = "funktion", phone = "telefon", order = "reihenfolge" }
}
