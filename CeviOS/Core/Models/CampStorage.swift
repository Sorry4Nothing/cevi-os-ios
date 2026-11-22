import Foundation

// MARK: Files (links to the storage place) and documents

extension CampFileRef {
    /// The link, only if it is an `https` address. The app hands it to the system to open; it never loads the file itself,
    /// and the link is never logged or cached (the storage place decides who may open it).
    var openableLink: URL? { link.scheme?.lowercased() == "https" ? link : nil }
}

/// Link to a file at the storage place (`POST …/dateien`). The server checks the link strictly.
nonisolated struct CampFileCreate: Encodable, Sendable {
    var displayName: String
    var link: URL
    var type: String?
    var size: Int?

    enum CodingKeys: String, CodingKey { case displayName = "anzeigename", link, type = "typ", size = "groesse" }
}

/// An unknown kind (the server added one) decodes as `.unknown`. `nil` on the document if the file was deleted.
nonisolated enum CampDocumentKind: String, Decodable, Sendable {
    case pdf, word, excel, link, unknown
    case image = "bild"

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = CampDocumentKind(rawValue: value) ?? .unknown
    }
}

/// A document, or a file another module of the camp registered (`source` is then the name of that module).
nonisolated struct CampDocument: Decodable, Equatable, Identifiable, Sendable {
    /// `dokument` or the name of the table of the module that links the file.
    let source: String
    let id: UUID
    /// `nil` for a file of another module: only documents with a `version` can be changed here.
    let version: Int?
    let title: String
    let keywords: [String]
    let teamVisible: Bool?
    /// `nil` if the file was deleted.
    let file: CampFileRef?
    let kind: CampDocumentKind?
    /// Whether the link is on a SharePoint host. `nil` if the file was deleted.
    let isSharePoint: Bool?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case source = "quelle", id, version, title = "titel", keywords = "stichworte", teamVisible = "teamSichtbar", file = "datei"
        case kind = "art", isSharePoint = "sharepoint", createdAt = "erstelltAm"
    }
}

nonisolated struct CampDocumentPage: Decodable, Equatable, Sendable {
    let documents: [CampDocument]
    /// Cursor (`nach`); `nil` at the end. A page can be empty and still have a next one.
    let next: UUID?

    enum CodingKeys: String, CodingKey { case documents = "dokumente", next = "naechster" }
}

/// The `typ` filter of the document list (kind or storage place).
nonisolated enum CampDocumentTypeFilter: String, CaseIterable, Identifiable, Sendable {
    case pdf, word, excel, link, sharepoint
    case image = "bild"

    var id: String { rawValue }
}

nonisolated struct CampDocumentFilter: Sendable {
    /// Title and keywords, 1 to 100 characters.
    var search: String?
    /// At most 5.
    var keywords: [String] = []
    var type: CampDocumentTypeFilter?

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let search { items.append(URLQueryItem(name: "q", value: search)) }
        if !keywords.isEmpty { items.append(URLQueryItem(name: "stichwort", value: keywords.joined(separator: ","))) }
        if let type { items.append(URLQueryItem(name: "typ", value: type.rawValue)) }
        return items
    }
}

nonisolated struct CampDocumentCreate: Encodable, Sendable {
    var title: String
    /// A file link from `createCampFile`.
    var fileId: UUID
    var keywords: [String]?
    var teamVisible: Bool?

    enum CodingKeys: String, CodingKey { case title = "titel", fileId = "dateiId", keywords = "stichworte", teamVisible = "teamSichtbar" }
}

nonisolated struct CampDocumentPatch: Encodable, Sendable {
    let version: Int
    var title: String?
    var fileId: UUID?
    /// Replaces the whole list.
    var keywords: [String]?
    var teamVisible: Bool?

    enum CodingKeys: String, CodingKey { case version, title = "titel", fileId = "dateiId", keywords = "stichworte", teamVisible = "teamSichtbar" }
}

// MARK: Address book (camp leadership only)

/// A contact of the camp address book. Name, phone, email and note are data of third parties:
/// never in widgets, logs or crash reports.
nonisolated struct CampContact: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let version: Int
    let name: String
    let function: String?
    let group: String?
    let phone: String?
    let email: String?
    let note: String?
    /// «Fürs nächste Lager behalten»: takes the contact out of the clean-up period.
    let keep: Bool
    /// The day from which the daily run deletes the contact for good (camp end plus 180 days); `nil` if `keep`.
    let cleanUpFrom: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, version, name, function = "funktion", group = "gruppe", phone = "telefon", email, note = "notiz"
        case keep = "behalten", cleanUpFrom = "aufraeumenAb", createdAt = "erstelltAm"
    }
}

nonisolated struct CampContactPage: Decodable, Equatable, Sendable {
    let contacts: [CampContact]
    let next: UUID?

    enum CodingKeys: String, CodingKey { case contacts = "kontakte", next = "naechster" }
}

nonisolated struct CampContactCreate: Encodable, Sendable {
    var name: String
    var function: String?
    var group: String?
    /// Digits and the usual separators, 6 to 30 characters.
    var phone: String?
    var email: String?
    var note: String?
    var keep: Bool?

    enum CodingKeys: String, CodingKey { case name, function = "funktion", group = "gruppe", phone = "telefon", email, note = "notiz", keep = "behalten" }
}

nonisolated struct CampContactPatch: Encodable, Sendable {
    let version: Int
    var name: String?
    /// `.clear` sends `null` and removes the entry.
    var function: CampField<String>?
    var group: CampField<String>?
    var phone: CampField<String>?
    var email: CampField<String>?
    var note: CampField<String>?
    var keep: Bool?

    enum CodingKeys: String, CodingKey { case version, name, function = "funktion", group = "gruppe", phone = "telefon", email, note = "notiz", keep = "behalten" }
}

// MARK: Search

/// The kinds of object a hit can have. An unknown kind decodes as `.unknown`.
nonisolated enum CampSearchType: String, Codable, Sendable {
    case addressBook = "adressbuch", task = "aufgabe", resolution = "beschluss", shift = "dienst", document = "dokument"
    case inbox = "eingang", shopping = "einkauf", trip = "fahrt", group = "gruppe", meeting = "hoeck", info, milestone = "meilenstein"
    case emergency = "notfall", packingList = "packliste", noticeBoard = "pinnwand", meetingProtocol = "protokoll", portfolio = "ressort"
    case dayPage = "tagesseite", participant = "teilnehmer", agendaItem = "traktandum", room = "zimmer", unknown

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = CampSearchType(rawValue: value) ?? .unknown
    }
}

/// A hit shows only what the role may see; the app opens the object by `type` and `id`.
nonisolated struct CampSearchHit: Decodable, Equatable, Identifiable, Sendable {
    let type: CampSearchType
    let id: UUID
    let title: String
    /// Around 140 characters around the match; `nil` if the title itself matched.
    let excerpt: String?

    enum CodingKeys: String, CodingKey { case type = "typ", id, title = "titel", excerpt = "auszug" }
}

nonisolated struct CampSearchResult: Decodable, Equatable, Sendable {
    /// At most 50, best match first. Can be empty.
    let hits: [CampSearchHit]

    enum CodingKeys: String, CodingKey { case hits = "treffer" }
}
