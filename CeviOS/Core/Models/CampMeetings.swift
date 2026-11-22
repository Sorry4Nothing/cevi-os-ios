import Foundation

// MARK: Files (references only, never bytes)

/// A link to a file at the storage place of the department. The app never loads the content through the API.
nonisolated struct CampFileRef: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let version: Int
    let displayName: String
    let link: URL
    /// MIME type, if known.
    let type: String?
    /// Bytes, if known.
    let size: Int?
    let addedBy: UUID?
    let addedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, version, link
        case displayName = "anzeigename", type = "typ", size = "groesse", addedBy = "hinzugefuegtVon", addedAt = "hinzugefuegtAm"
    }
}

// MARK: Meetings (Höcks) and agenda items (Traktanden)

nonisolated enum CampMeetingKind: String, Codable, Sendable {
    case campLeadership = "lagerleitung"
    case team
}

nonisolated enum CampAgendaStatus: String, Codable, Sendable {
    case open = "offen"
    case discussed = "besprochen"
}

nonisolated struct CampAgendaLink: Codable, Equatable, Sendable {
    var title: String
    /// `https`, checked by the server.
    var url: String

    enum CodingKeys: String, CodingKey { case title = "titel", url }
}

nonisolated struct CampAgendaItem: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let version: Int
    /// `nil`: the item waits for the next meeting.
    let meetingId: UUID?
    let title: String
    let text: String?
    let decision: String?
    let links: [CampAgendaLink]
    let order: Int
    let taskId: UUID?
    let status: CampAgendaStatus
    let responsible: [CampPersonRef]

    enum CodingKeys: String, CodingKey {
        case id, version, links, status
        case meetingId = "hoeckId", title = "titel", text, decision = "entscheid", order = "reihenfolge"
        case taskId = "aufgabeId", responsible = "verantwortliche"
    }
}

/// The meeting as the camp leadership sees it. In the meeting mode `attendees` is absent (see `CampMeetingMode.members`).
nonisolated struct CampMeeting: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let version: Int
    let kind: CampMeetingKind
    let date: Date
    /// `HH:MM`, Swiss time, or `nil` for a day without time.
    let time: String?
    let title: String
    let place: String?
    /// Names of guests as free text.
    let guests: String?
    let protocolId: UUID?
    let attendees: [CampPersonRef]?
    let agenda: [CampAgendaItem]

    enum CodingKeys: String, CodingKey {
        case id, version
        case kind = "art", date = "datum", time = "zeit", title = "titel", place = "ort", guests = "gaeste"
        case protocolId = "protokollId", attendees = "anwesende", agenda = "traktanden"
    }
}

nonisolated struct CampMeetingSummary: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let version: Int
    let kind: CampMeetingKind
    let date: Date
    let time: String?
    let title: String
    let place: String?
    let guests: String?
    let protocolId: UUID?
    let agendaCount: Int
    let attendeeCount: Int

    enum CodingKeys: String, CodingKey {
        case id, version
        case kind = "art", date = "datum", time = "zeit", title = "titel", place = "ort", guests = "gaeste"
        case protocolId = "protokollId", agendaCount = "anzahlTraktanden", attendeeCount = "anzahlAnwesende"
    }
}

/// A team meeting as the team sees it: only date, time, title and place.
nonisolated struct CampMeetingTeamView: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let version: Int
    let date: Date
    let time: String?
    let title: String
    let place: String?

    enum CodingKeys: String, CodingKey { case id, version, date = "datum", time = "zeit", title = "titel", place = "ort" }
}

/// The server answers with the full shape for roles that may read all meetings and with the short team shape for the others.
/// The shapes differ by the field `art`.
nonisolated enum CampMeetingView<Full: Decodable & Sendable>: Decodable, Sendable {
    case full(Full)
    case team(CampMeetingTeamView)

    private enum Probe: String, CodingKey { case kind = "art" }

    init(from decoder: Decoder) throws {
        if try decoder.container(keyedBy: Probe.self).contains(.kind) {
            self = .full(try Full(from: decoder))
        } else {
            self = .team(try CampMeetingTeamView(from: decoder))
        }
    }
}

extension CampMeetingView: Equatable where Full: Equatable {}

nonisolated struct CampMeetingPage: Decodable, Equatable, Sendable {
    let meetings: [CampMeetingView<CampMeetingSummary>]
    let next: UUID?

    enum CodingKeys: String, CodingKey { case meetings = "hoecks", next = "naechster" }
}

nonisolated struct CampMeetingMember: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String?
    let ceviName: String?
    let role: CampRole
    let present: Bool

    enum CodingKeys: String, CodingKey { case id, name, ceviName, role = "rolle", present = "anwesend" }
}

nonisolated struct CampPortfolioTaskCounts: Decodable, Equatable, Sendable {
    let total: Int
    let done: Int
    /// Not done.
    let open: Int
    let overdue: Int

    enum CodingKeys: String, CodingKey { case total = "gesamt", done = "erledigt", open = "offen", overdue = "ueberfaellig" }
}

/// One portfolio with the state of its tasks, for the round of portfolios in the meeting.
nonisolated struct CampPortfolioRound: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let code: String
    let name: String
    let leader: CampPersonRef?
    /// `nil` if the role may not read all tasks.
    let tasks: CampPortfolioTaskCounts?

    enum CodingKeys: String, CodingKey { case id, name, code = "kuerzel", leader = "leitung", tasks = "aufgaben" }
}

/// Everything for the meeting: meeting with agenda, members to tick off and the round of portfolios.
nonisolated struct CampMeetingMode: Decodable, Equatable, Sendable {
    let meeting: CampMeeting
    let members: [CampMeetingMember]
    /// `nil` without the right to read portfolios.
    let portfolioRound: [CampPortfolioRound]?

    enum CodingKeys: String, CodingKey { case meeting = "hoeck", members = "mitglieder", portfolioRound = "ressortRunde" }
}

nonisolated struct CampMeetingCreate: Encodable, Sendable {
    var title: String
    var kind: CampMeetingKind
    var date: CampCalendarDay
    /// `HH:MM`.
    var time: String?
    var place: String?
    var guests: String?

    enum CodingKeys: String, CodingKey {
        case kind = "art", date = "datum", time = "zeit", title = "titel", place = "ort", guests = "gaeste"
    }
}

nonisolated struct CampMeetingPatch: Encodable, Sendable {
    let version: Int
    var title: String?
    var kind: CampMeetingKind?
    var date: CampCalendarDay?
    var time: CampField<String>?
    var place: CampField<String>?
    var guests: CampField<String>?

    enum CodingKeys: String, CodingKey {
        case version
        case kind = "art", date = "datum", time = "zeit", title = "titel", place = "ort", guests = "gaeste"
    }
}

nonisolated struct CampAgendaItemCreate: Encodable, Sendable {
    var title: String
    /// `nil`: for the next meeting.
    var meetingId: UUID?
    var text: String?
    var decision: String?
    var links: [CampAgendaLink]?
    var responsibleIds: [UUID]?
    var taskId: UUID?
    var status: CampAgendaStatus?
    var order: Int?

    enum CodingKeys: String, CodingKey {
        case status, links
        case meetingId = "hoeckId", title = "titel", text, decision = "entscheid", order = "reihenfolge"
        case taskId = "aufgabeId", responsibleIds = "verantwortlichePersonIds"
    }
}

/// Also moves an item (`meetingId`) or decides it (`decision`, `status`). `links` and `responsibleIds` replace the whole list.
nonisolated struct CampAgendaItemPatch: Encodable, Sendable {
    let version: Int
    var title: String?
    var meetingId: CampField<UUID>?
    var text: CampField<String>?
    var decision: CampField<String>?
    var links: [CampAgendaLink]?
    var responsibleIds: [UUID]?
    var taskId: CampField<UUID>?
    var status: CampAgendaStatus?
    var order: Int?

    enum CodingKeys: String, CodingKey {
        case version, status, links
        case meetingId = "hoeckId", title = "titel", text, decision = "entscheid", order = "reihenfolge"
        case taskId = "aufgabeId", responsibleIds = "verantwortlichePersonIds"
    }
}

/// Body of `PUT …/traktanden/reihenfolge`: the order inside one meeting, or inside the list for the next meeting (`nil`).
nonisolated struct CampAgendaOrderBody: Encodable, Sendable {
    let meetingId: UUID?
    let entries: [CampVersionRef]

    enum CodingKeys: String, CodingKey { case meetingId = "hoeckId", entries = "eintraege" }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(meetingId, forKey: .meetingId) // required, `null` is the list for the next meeting
        try container.encode(entries, forKey: .entries)
    }
}

nonisolated struct CampAgendaAdoptBody: Encodable, Sendable {
    /// `nil`: all waiting items.
    var itemIds: [UUID]?

    enum CodingKeys: String, CodingKey { case itemIds = "traktandumIds" }
}

nonisolated struct CampAgendaAdopted: Decodable, Equatable, Sendable {
    let adopted: Int

    enum CodingKeys: String, CodingKey { case adopted = "uebernommen" }
}

nonisolated struct CampAgendaWaiting: Decodable, Equatable, Sendable {
    let items: [CampAgendaItem]

    enum CodingKeys: String, CodingKey { case items = "traktanden" }
}

// MARK: Protocols and decisions (Protokolle, Beschlüsse)

nonisolated enum CampProtocolKind: String, Codable, Sendable {
    case meeting = "sitzung"
    case note = "notiz"
    case contact = "kontakt"
    case idea = "idee"
}

/// The protocol is a row (title, date, kind, link to a meeting) that points to a file; the API has no sections.
/// The row has a `version`: on a 409 `VERSION_KONFLIKT` read `CampRules.versionConflict(error, as: CampProtocol.self)`.
nonisolated struct CampProtocol: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let version: Int
    let kind: CampProtocolKind
    let title: String
    let date: Date
    let meetingId: UUID?
    let fileId: UUID
    /// `nil` if the file was deleted.
    let file: CampFileRef?
    let createdAt: Date
    let createdBy: UUID?

    enum CodingKeys: String, CodingKey {
        case id, version
        case kind = "art", title = "titel", date = "datum", meetingId = "hoeckId", fileId = "dateiId", file = "datei"
        case createdAt = "erstelltAm", createdBy = "erstelltVon"
    }
}

nonisolated struct CampProtocolPage: Decodable, Equatable, Sendable {
    let protocols: [CampProtocol]
    let next: UUID?

    enum CodingKeys: String, CodingKey { case protocols = "protokolle", next = "naechster" }
}

nonisolated struct CampProtocolFilter: Sendable {
    var meetingId: UUID?
    var kind: CampProtocolKind?
    var search: String?

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let meetingId { items.append(URLQueryItem(name: "hoeckId", value: meetingId.uuidString.lowercased())) }
        if let kind { items.append(URLQueryItem(name: "art", value: kind.rawValue)) }
        if let search { items.append(URLQueryItem(name: "q", value: search)) }
        return items
    }
}

nonisolated struct CampProtocolCreate: Encodable, Sendable {
    var kind: CampProtocolKind
    var title: String
    var date: CampCalendarDay
    var fileId: UUID
    var meetingId: UUID?

    enum CodingKeys: String, CodingKey { case kind = "art", title = "titel", date = "datum", fileId = "dateiId", meetingId = "hoeckId" }
}

nonisolated struct CampProtocolPatch: Encodable, Sendable {
    let version: Int
    var kind: CampProtocolKind?
    var title: String?
    var date: CampCalendarDay?
    var fileId: UUID?
    var meetingId: CampField<UUID>?

    enum CodingKeys: String, CodingKey {
        case version
        case kind = "art", title = "titel", date = "datum", fileId = "dateiId", meetingId = "hoeckId"
    }
}

nonisolated struct CampResolution: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let version: Int
    let text: String
    let protocolId: UUID?
    let meetingId: UUID?
    let createdAt: Date
    let createdBy: UUID?

    enum CodingKeys: String, CodingKey {
        case id, version, text
        case protocolId = "protokollId", meetingId = "hoeckId", createdAt = "erstelltAm", createdBy = "erstelltVon"
    }
}

nonisolated struct CampResolutionPage: Decodable, Equatable, Sendable {
    let resolutions: [CampResolution]
    let next: UUID?

    enum CodingKeys: String, CodingKey { case resolutions = "beschluesse", next = "naechster" }
}

nonisolated struct CampResolutionCreate: Encodable, Sendable {
    var text: String
    var protocolId: UUID?
    var meetingId: UUID?

    enum CodingKeys: String, CodingKey { case text, protocolId = "protokollId", meetingId = "hoeckId" }
}

nonisolated struct CampResolutionPatch: Encodable, Sendable {
    let version: Int
    var text: String?
    var protocolId: CampField<UUID>?
    var meetingId: CampField<UUID>?

    enum CodingKeys: String, CodingKey { case version, text, protocolId = "protokollId", meetingId = "hoeckId" }
}
