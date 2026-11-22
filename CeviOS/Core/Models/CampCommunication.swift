import Foundation

// MARK: Mentions (Erwähnungen)

nonisolated enum CampMentionSourceKind: String, Codable, Sendable {
    case task = "aufgabe"
    case agendaItem = "traktandum"
    case notice = "pinnwand"
    case resolution = "beschluss"
}

nonisolated struct CampMention: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let sourceKind: CampMentionSourceKind
    let sourceId: UUID
    let title: String
    let done: Bool
    /// Set once a task was made from the mention.
    let taskId: UUID?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case title = "titel", sourceKind = "quelleTyp", sourceId = "quelleId", done = "erledigt", taskId = "aufgabeId", createdAt = "erstelltAm"
    }
}

nonisolated struct CampMentionPage: Decodable, Equatable, Sendable {
    let mentions: [CampMention]
    let next: UUID?

    enum CodingKeys: String, CodingKey { case mentions = "erwaehnungen", next = "naechster" }
}

/// Result of matching the mentions of a text: the persons it mentions now and how many are new.
nonisolated struct CampMentionSync: Decodable, Equatable, Sendable {
    let personIds: [UUID]
    let new: Int

    enum CodingKeys: String, CodingKey { case personIds, new = "neu" }
}

nonisolated struct CampMentionDoneBody: Encodable, Sendable {
    let done: Bool

    enum CodingKeys: String, CodingKey { case done = "erledigt" }
}

nonisolated struct CampMentionTask: Decodable, Equatable, Sendable {
    let taskId: UUID

    enum CodingKeys: String, CodingKey { case taskId = "aufgabeId" }
}

// MARK: Reactions

nonisolated enum CampReactionKey: String, Codable, CaseIterable, Sendable {
    case thumbsUp = "daumen"
    case heart = "herz"
    case laugh = "lachen"
    case surprise = "staunen"
    case thanks = "danke"
}

nonisolated enum CampReactionTarget: String, Sendable {
    case notice = "pinnwand_beitrag"
}

/// Counts per key and the own reaction, never names. Keys without a reaction are absent from `counts`.
nonisolated struct CampReactions: Decodable, Equatable, Sendable {
    let counts: [CampReactionKey: Int]
    let own: CampReactionKey?

    enum CodingKeys: String, CodingKey { case counts = "zaehler", own = "eigene" }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode([String: Int].self, forKey: .counts)
        // A key the app does not know is skipped, not an error.
        counts = Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in CampReactionKey(rawValue: key).map { ($0, value) } })
        own = try container.decodeIfPresent(CampReactionKey.self, forKey: .own)
    }
}

nonisolated struct CampReactionBody: Encodable, Sendable {
    let reaction: CampReactionKey

    enum CodingKeys: String, CodingKey { case reaction = "emoji" }
}

// MARK: Notice board (Pinnwand) and polls

nonisolated enum CampNoticeRole: String, Codable, Sendable {
    case leadership = "leitung"
    case team
    case readOnly = "lesen"
}

/// Who a notice is for, as the server shows it. Persons are listed only for roles that may edit the notice board.
nonisolated struct CampNoticeAudience: Decodable, Equatable, Sendable {
    /// No recipients set: the notice is for all members.
    let everyone: Bool
    let roles: [CampNoticeRole]
    let personIds: [UUID]

    enum CodingKeys: String, CodingKey { case everyone = "anAlle", roles = "rollen", personIds = "personen" }
}

/// Recipients in a request. Empty roles and persons mean everyone.
nonisolated struct CampNoticeTarget: Encodable, Equatable, Sendable {
    var roles: [CampNoticeRole] = []
    var personIds: [UUID] = []

    enum CodingKeys: String, CodingKey { case roles = "rollen", personIds = "personen" }
}

nonisolated struct CampPollOption: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let text: String
    let votes: Int
    /// True if the own vote is on this option.
    let own: Bool
    /// Empty unless the names are visible to the role (`CampPoll.namesVisible`).
    let people: [CampPersonRef]

    enum CodingKeys: String, CodingKey { case id, text, votes = "stimmen", own = "eigene", people = "personen" }
}

nonisolated struct CampPoll: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let version: Int
    let multiple: Bool
    let closesAt: Date?
    let closed: Bool
    /// The lead decided that the team sees who voted.
    let namesForTeam: Bool
    let namesVisible: Bool
    let participants: Int
    let options: [CampPollOption]

    enum CodingKeys: String, CodingKey {
        case id, version
        case multiple = "mehrfach", closesAt = "schliesstAm", closed = "geschlossen", namesForTeam = "namenFuerTeam"
        case namesVisible = "namenSichtbar", participants = "teilnehmende", options = "optionen"
    }
}

nonisolated struct CampNotice: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let version: Int
    let title: String
    let text: String
    let important: Bool
    let pinned: Bool
    let visibleFrom: Date?
    let visibleUntil: Date?
    let authorId: UUID?
    let createdAt: Date
    let author: CampPersonRef?
    let audience: CampNoticeAudience
    /// References of files (see `CampFileRef`), not content.
    let files: [CampFileRef]
    let poll: CampPoll?
    let reactions: CampReactions

    enum CodingKeys: String, CodingKey {
        case id, version
        case title = "titel", text, important = "wichtig", pinned = "angeheftet", visibleFrom = "sichtbarAb", visibleUntil = "sichtbarBis"
        case authorId = "vonPersonId", createdAt = "erstelltAm", author = "von", audience = "empfaenger", files = "dateien"
        case poll = "umfrage", reactions = "reaktionen"
    }
}

nonisolated struct CampNoticePage: Decodable, Equatable, Sendable {
    let notices: [CampNotice]
    let next: UUID?

    enum CodingKeys: String, CodingKey { case notices = "beitraege", next = "naechster" }
}

/// `active`: inside the time window (`sichtbarAb`, `sichtbarBis`); `all`: also expired and future notices (for editors).
nonisolated enum CampNoticeScope: String, Sendable {
    case active = "aktiv"
    case all = "alle"
}

nonisolated struct CampNoticeCreate: Encodable, Sendable {
    var title: String
    var text: String?
    var important: Bool?
    var pinned: Bool?
    var visibleFrom: Date?
    var visibleUntil: Date?
    var recipients: CampNoticeTarget?
    /// IDs of files that were added before.
    var fileIds: [UUID]?

    enum CodingKeys: String, CodingKey {
        case text
        case title = "titel", important = "wichtig", pinned = "angeheftet", visibleFrom = "sichtbarAb", visibleUntil = "sichtbarBis"
        case recipients = "empfaenger", fileIds = "dateiIds"
    }
}

nonisolated struct CampNoticePatch: Encodable, Sendable {
    let version: Int
    var title: String?
    var text: String?
    var important: Bool?
    var pinned: Bool?
    var visibleFrom: CampField<Date>?
    var visibleUntil: CampField<Date>?
    var recipients: CampNoticeTarget?
    /// Replaces the list of files.
    var fileIds: [UUID]?

    enum CodingKeys: String, CodingKey {
        case version, text
        case title = "titel", important = "wichtig", pinned = "angeheftet", visibleFrom = "sichtbarAb", visibleUntil = "sichtbarBis"
        case recipients = "empfaenger", fileIds = "dateiIds"
    }
}

nonisolated struct CampPollCreate: Encodable, Sendable {
    var options: [String]
    var multiple: Bool?
    var closesAt: Date?
    var namesForTeam: Bool?

    enum CodingKeys: String, CodingKey {
        case options = "optionen", multiple = "mehrfach", closesAt = "schliesstAm", namesForTeam = "namenFuerTeam"
    }
}

nonisolated struct CampPollPatch: Encodable, Sendable {
    let version: Int
    var closed: Bool?
    var closesAt: CampField<Date>?
    var namesForTeam: Bool?

    enum CodingKeys: String, CodingKey {
        case version
        case closed = "geschlossen", closesAt = "schliesstAm", namesForTeam = "namenFuerTeam"
    }
}

nonisolated struct CampPollVoteBody: Encodable, Sendable {
    let optionIds: [UUID]
}

/// The printable sheets the server renders as PDF.
nonisolated enum CampHandout: String, CaseIterable, Sendable {
    case shiftPlan = "schichtplan"
    case roomList = "zimmerliste"
    case doorSigns = "tuerschilder"
    case groupLists = "gruppenlisten"
    case tripList = "fahrtenliste"
    case organigram = "organigramm"
}

// MARK: Inbox (Eingang): ideas, wishes, questions, feedback

nonisolated enum CampInboxKind: String, Codable, CaseIterable, Sendable {
    case idea = "idee"
    case wish = "wunsch"
    case question = "frage"
    case feedback
}

nonisolated enum CampInboxStatus: String, Codable, Sendable {
    case new = "neu"
    case inProgress = "in_arbeit"
    case done = "erledigt"
}

/// An entry as the camp leadership sees it. For an anonymous entry `sender` is always `nil`, even if the answer carried a name.
nonisolated struct CampInboxEntry: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let version: Int
    let kind: CampInboxKind
    let text: String
    let anonymous: Bool
    let status: CampInboxStatus
    let reply: String?
    let repliedOn: Date?
    /// A day, never a time.
    let createdOn: Date
    let portfolioId: UUID?
    let agendaItemId: UUID?
    let sender: CampPersonRef?

    enum CodingKeys: String, CodingKey {
        case id, version, text
        case kind = "art", anonymous = "anonym", status, reply = "antwort", repliedOn = "beantwortetTag", createdOn = "erstelltTag"
        case portfolioId = "ressortId", agendaItemId = "traktandumId", sender = "von"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        version = try container.decode(Int.self, forKey: .version)
        kind = try container.decode(CampInboxKind.self, forKey: .kind)
        text = try container.decode(String.self, forKey: .text)
        anonymous = try container.decode(Bool.self, forKey: .anonymous)
        status = try container.decode(CampInboxStatus.self, forKey: .status)
        reply = try container.decodeIfPresent(String.self, forKey: .reply)
        repliedOn = try container.decodeIfPresent(Date.self, forKey: .repliedOn)
        createdOn = try container.decode(Date.self, forKey: .createdOn)
        portfolioId = try container.decodeIfPresent(UUID.self, forKey: .portfolioId)
        agendaItemId = try container.decodeIfPresent(UUID.self, forKey: .agendaItemId)
        // Anonymity is kept in the model: no sender for an anonymous entry, whatever the server sent.
        sender = anonymous ? nil : try container.decodeIfPresent(CampPersonRef.self, forKey: .sender)
    }
}

nonisolated struct CampInboxPage: Decodable, Equatable, Sendable {
    let entries: [CampInboxEntry]
    let next: UUID?

    enum CodingKeys: String, CodingKey { case entries = "eintraege", next = "naechster" }
}

/// An own, not anonymous entry.
nonisolated struct CampOwnInboxEntry: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let kind: CampInboxKind
    let text: String
    let status: CampInboxStatus
    let reply: String?
    let repliedOn: Date?
    let createdOn: Date

    enum CodingKeys: String, CodingKey {
        case id, text, status
        case kind = "art", reply = "antwort", repliedOn = "beantwortetTag", createdOn = "erstelltTag"
    }
}

nonisolated struct CampOwnInboxPage: Decodable, Equatable, Sendable {
    let entries: [CampOwnInboxEntry]
    let next: UUID?

    enum CodingKeys: String, CodingKey { case entries = "eintraege", next = "naechster" }
}

/// The answer to sending. Not anonymous: `id`. Anonymous: `followUpCode`, shown only now and never again. The app must not
/// store it or write it to a log; the person keeps it to ask for the answer with `campInboxStatus`.
nonisolated struct CampInboxSent: Decodable, Equatable, Sendable {
    let anonymous: Bool
    let id: UUID?
    let followUpCode: String?
    let kind: CampInboxKind
    let status: CampInboxStatus
    let reply: String?
    let repliedOn: Date?
    let createdOn: Date

    enum CodingKeys: String, CodingKey {
        case id, status
        case anonymous = "anonym", followUpCode = "rueckfragecode", kind = "art", reply = "antwort"
        case repliedOn = "beantwortetTag", createdOn = "erstelltTag"
    }
}

/// What the sender of an anonymous entry reads with the code: no text, no id.
nonisolated struct CampInboxCodeView: Decodable, Equatable, Sendable {
    let kind: CampInboxKind
    let status: CampInboxStatus
    let reply: String?
    let repliedOn: Date?
    let createdOn: Date

    enum CodingKeys: String, CodingKey {
        case status
        case kind = "art", reply = "antwort", repliedOn = "beantwortetTag", createdOn = "erstelltTag"
    }
}

nonisolated struct CampInboxFilter: Sendable {
    var status: CampInboxStatus?
    var kind: CampInboxKind?

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let status { items.append(URLQueryItem(name: "status", value: status.rawValue)) }
        if let kind { items.append(URLQueryItem(name: "art", value: kind.rawValue)) }
        return items
    }
}

nonisolated struct CampInboxSend: Encodable, Sendable {
    var kind: CampInboxKind
    var text: String
    var anonymous: Bool

    enum CodingKeys: String, CodingKey { case kind = "art", text, anonymous = "anonym" }
}

nonisolated struct CampInboxCodeBody: Encodable, Sendable {
    let code: String
}

/// Answers, sets the status or assigns the entry to a portfolio or an agenda item.
nonisolated struct CampInboxPatch: Encodable, Sendable {
    let version: Int
    var status: CampInboxStatus?
    var reply: CampField<String>?
    var portfolioId: CampField<UUID>?
    var agendaItemId: CampField<UUID>?

    enum CodingKeys: String, CodingKey {
        case version, status
        case reply = "antwort", portfolioId = "ressortId", agendaItemId = "traktandumId"
    }
}

nonisolated struct CampInboxToAgenda: Encodable, Sendable {
    let version: Int
    var title: String
    /// `nil`: for the next meeting.
    var meetingId: UUID?

    enum CodingKeys: String, CodingKey { case version, title = "titel", meetingId = "hoeckId" }
}
