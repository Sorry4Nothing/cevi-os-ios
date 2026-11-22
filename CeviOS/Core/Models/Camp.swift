import Foundation

/// Role in a camp. The department lead (admin) counts as `campLeader` in every camp of the department.
nonisolated enum CampRole: String, Decodable, Sendable {
    case campLeader = "lagerleitung"
    case leader = "leitung"
    case team
    case readOnly = "lesen"
}

/// `abgeschlossen` and `archiviert` are read-only.
nonisolated enum CampStatus: String, Decodable, Sendable {
    case draft = "entwurf"
    case active = "aktiv"
    case completed = "abgeschlossen"
    case archived = "archiviert"
}

nonisolated struct Camp: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    /// First and last day (calendar days).
    let from: Date
    let to: Date
    let preparationFrom: Date?
    let place: String?
    let address: String?
    let status: CampStatus
    /// Lower-case hex colour, `#rrggbb`.
    let color: String?
    /// Logo in the media storage (`GET /api/v1/medien/{id}`).
    let logoMediumId: UUID?

    enum CodingKeys: String, CodingKey {
        case id, status, color
        case title = "titel", from = "von", to = "bis", preparationFrom = "vorbereitungAb"
        case place = "ort", address = "adresse", logoMediumId
    }
}

/// A camp of `GET /api/v1/lager` with the own role.
nonisolated struct CampListEntry: Decodable, Equatable, Identifiable, Sendable {
    let camp: Camp
    let role: CampRole

    var id: UUID { camp.id }

    private enum RoleKey: String, CodingKey { case role = "rolle" }

    init(from decoder: Decoder) throws {
        camp = try Camp(from: decoder)
        role = try decoder.container(keyedBy: RoleKey.self).decode(CampRole.self, forKey: .role)
    }
}

nonisolated struct CampList: Decodable, Sendable {
    let camps: [CampListEntry]

    enum CodingKeys: String, CodingKey { case camps = "lager" }
}

/// A camp of `GET /api/v1/lager/{id}`.
nonisolated struct CampDetail: Decodable, Equatable, Identifiable, Sendable {
    let camp: Camp
    let role: CampRole
    /// True for completed and archived camps: writing requests answer 409 `LAGER_GESCHLOSSEN`.
    let isReadOnly: Bool

    var id: UUID { camp.id }

    private enum ExtraKeys: String, CodingKey { case role = "rolle", isReadOnly = "schreibgeschuetzt" }

    init(from decoder: Decoder) throws {
        camp = try Camp(from: decoder)
        let container = try decoder.container(keyedBy: ExtraKeys.self)
        role = try container.decode(CampRole.self, forKey: .role)
        isReadOnly = try container.decode(Bool.self, forKey: .isReadOnly)
    }
}

// MARK: Rights

/// Allowed or not, per adjustable role. The camp lead is not listed: it has every right.
nonisolated struct CampRoleFlags: Decodable, Equatable, Sendable {
    let leader: Bool
    let team: Bool
    let readOnly: Bool

    enum CodingKeys: String, CodingKey { case leader = "leitung", team, readOnly = "lesen" }
}

nonisolated struct CampRightEntry: Decodable, Equatable, Sendable {
    /// `<area>.<action>`, for example `aufgaben.bearbeiten`. The server may add rights, so this stays a string.
    let right: String
    let meaning: String
    let standard: CampRoleFlags
    let current: CampRoleFlags

    enum CodingKeys: String, CodingKey { case right = "recht", meaning = "bedeutung", standard, current = "aktuell" }
}

/// `GET /api/v1/lager/{id}/rechte`. Only the camp lead (and the department lead) may read it; others get 403.
nonisolated struct CampRights: Decodable, Equatable, Sendable {
    let entries: [CampRightEntry]

    enum CodingKeys: String, CodingKey { case entries = "rechte" }

    /// The camp lead may do everything; the other roles as the current matrix says. Unknown right: no.
    func allows(_ right: String, role: CampRole) -> Bool {
        guard role != .campLeader else { return true }
        guard let entry = entries.first(where: { $0.right == right }) else { return false }
        return switch role {
        case .leader: entry.current.leader
        case .team: entry.current.team
        case .readOnly: entry.current.readOnly
        case .campLeader: true
        }
    }
}

// MARK: Notifications

/// An unknown kind (the server added one) decodes as `.unknown`; the list then still shows the entry.
nonisolated enum CampNotificationKind: String, Decodable, Sendable {
    case taskAssigned = "aufgabe_zugeteilt"
    case taskChanged = "aufgabe_geaendert"
    case mention = "erwaehnung"
    case deadline = "frist"
    case importantNotice = "pinnwand_wichtig"
    case feedbackReply = "eingang_antwort"
    case shiftSwapRequest = "diensttausch_anfrage"
    case shiftSwapDecision = "diensttausch_entscheid"
    case attendanceRequest = "anwesenheit_anfrage"
    case addressBookCleanup = "adressbuch_aufraeumen"
    case unknown

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = CampNotificationKind(rawValue: value) ?? .unknown
    }
}

/// A row without text or content: kind, object and time. The app builds the text from the kind.
nonisolated struct CampNotification: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let kind: CampNotificationKind
    /// What the app opens, for example `aufgabe`.
    let objectType: String
    let objectId: UUID
    let isRead: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, kind = "art", objectType = "objektTyp", objectId = "objektId", isRead = "gelesen", createdAt = "erstelltAm"
    }
}

nonisolated struct CampNotificationPage: Decodable, Equatable, Sendable {
    let entries: [CampNotification]
    /// Cursor for older entries (`nach`); `nil` at the end.
    let next: UUID?

    enum CodingKeys: String, CodingKey { case entries = "eintraege", next = "naechster" }
}

nonisolated struct CampUnreadCount: Decodable, Sendable {
    let count: Int

    enum CodingKeys: String, CodingKey { case count = "anzahl" }
}

nonisolated struct CampMarkReadBody: Encodable, Sendable {
    /// `nil`: all unread entries of the person in this camp.
    let ids: [UUID]?
}

/// The switch per kind of `GET`/`PUT /api/v1/ich/lager-benachrichtigungen`. The kinds the app does not know are skipped.
nonisolated struct CampNotificationSetting: Equatable, Sendable {
    let kind: CampNotificationKind
    var enabled: Bool
}

nonisolated struct CampNotificationSettings: Decodable, Equatable, Sendable {
    let kinds: [CampNotificationSetting]

    private struct Entry: Decodable { let art: String; let aktiv: Bool }
    private enum CodingKeys: String, CodingKey { case kinds = "arten" }

    init(kinds: [CampNotificationSetting]) { self.kinds = kinds }

    init(from decoder: Decoder) throws {
        let entries = try decoder.container(keyedBy: CodingKeys.self).decode([Entry].self, forKey: .kinds)
        kinds = entries.compactMap { entry in
            CampNotificationKind(rawValue: entry.art).flatMap { $0 == .unknown ? nil : CampNotificationSetting(kind: $0, enabled: entry.aktiv) }
        }
    }
}

nonisolated struct CampNotificationSettingsBody: Encodable, Sendable {
    struct Entry: Encodable, Sendable { let art: String; let aktiv: Bool }
    let arten: [Entry]
}

// MARK: Push

/// Push types of the camp (`LagerPushTyp`). A push carries only `typ` and `id`, never a camp id.
nonisolated enum CampPushType: String, Sendable {
    case task = "lager_aufgabe"
    case mention = "lager_erwaehnung"
    case notice = "lager_pinnwand"
    case feedback = "lager_eingang"
    case planning = "lager_einteilung"
    case attendance = "lager_anwesenheit"
}

/// `GET /api/v1/lager/aufloesen/{typ}/{id}`: in which camp the object of a push lies.
nonisolated struct CampPushResolution: Decodable, Equatable, Sendable {
    let campId: UUID
    let objectType: String
    let objectId: UUID

    enum CodingKeys: String, CodingKey { case campId = "lagerId", objectType = "objektTyp", objectId = "objektId" }
}

// MARK: Change feed

nonisolated enum CampChangeKind: String, Decodable, Sendable {
    case new = "neu"
    case changed = "geaendert"
    case deleted = "geloescht"
}

/// A change: only a reference to the row, no content.
nonisolated struct CampChange: Decodable, Equatable, Sendable {
    /// Sequence number of the write in the camp.
    let seq: Int
    let objectType: String
    let id: UUID
    let kind: CampChangeKind
    /// Version of the row after the change.
    let version: Int
    let time: Date

    enum CodingKeys: String, CodingKey {
        case seq, id, version
        case objectType = "objekttyp", kind = "art", time = "zeitpunkt"
    }
}

nonisolated struct CampChangesPage: Decodable, Equatable, Sendable {
    let changes: [CampChange]
    /// Ask on with `since=until`.
    let until: Int
    let hasMore: Bool

    enum CodingKeys: String, CodingKey { case changes = "eintraege", until = "bis", hasMore = "weitere" }
}

/// Answer of the feed without `seit`: where the feed stands and which object types the role may read.
nonisolated struct CampFeedState: Decodable, Equatable, Sendable {
    let seq: Int
    let objectTypes: [String]

    enum CodingKeys: String, CodingKey { case seq, objectTypes = "objekttypen" }
}

/// Answer of the feed with `seit`. `reload`: the server answered 410, the app loads the camp anew from `seq`.
nonisolated enum CampChangesResult: Equatable, Sendable {
    case page(CampChangesPage)
    case reload
}
