import Foundation

// Data of children and young people (participants) is sensitive: names, levels and nicknames may be shown in
// screens for the camp members, but never go into widgets, notifications, logs, analytics or crash reports.

/// Which list a route filters: the participants or the team (members of the camp).
nonisolated enum CampPeopleKind: String, Codable, Sendable {
    case participants = "teilnehmer"
    case team
}

// MARK: Participants (Teilnehmende)

/// A participant. `ceviName` is only sent to roles that may see it (camp leadership, leadership), otherwise `nil`.
nonisolated struct CampParticipant: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let version: Int
    let firstName: String
    let lastName: String
    let level: String?
    /// Deselected participants do not appear in groups, counting or shifts.
    let deselected: Bool
    let ceviName: String?

    enum CodingKeys: String, CodingKey {
        case id, version, level = "stufe", ceviName
        case firstName = "vorname", lastName = "nachname", deselected = "abgewaehlt"
    }
}

nonisolated struct CampParticipantPage: Decodable, Equatable, Sendable {
    let participants: [CampParticipant]
    let next: UUID?

    enum CodingKeys: String, CodingKey { case participants = "teilnehmer", next = "naechster" }
}

nonisolated struct CampParticipantCreate: Encodable, Sendable {
    var firstName: String
    var lastName: String
    var level: String?
    var ceviName: String?

    enum CodingKeys: String, CodingKey { case firstName = "vorname", lastName = "nachname", level = "stufe", ceviName }
}

nonisolated struct CampParticipantPatch: Encodable, Sendable {
    let version: Int
    var firstName: String?
    var lastName: String?
    var level: CampField<String>?
    var ceviName: CampField<String>?

    enum CodingKeys: String, CodingKey { case version, firstName = "vorname", lastName = "nachname", level = "stufe", ceviName }
}

nonisolated struct CampParticipantImportBody: Encodable, Sendable {
    /// One person per line, at most 40000 characters.
    let text: String
    let confirm: Bool

    enum CodingKeys: String, CodingKey { case text, confirm = "uebernehmen" }
}

nonisolated struct CampImportRow: Decodable, Equatable, Sendable {
    /// Line number in the pasted text, from 1.
    let line: Int
    let firstName: String
    let lastName: String
    let level: String?
    let ceviName: String?

    enum CodingKeys: String, CodingKey { case line = "zeile", firstName = "vorname", lastName = "nachname", level = "stufe", ceviName }
}

nonisolated enum CampImportErrorCode: String, Decodable, Sendable {
    case tooFewColumns = "ZU_WENIG_SPALTEN"
    case tooManyColumns = "ZU_VIELE_SPALTEN"
    case firstNameMissing = "VORNAME_FEHLT"
    case lastNameMissing = "NACHNAME_FEHLT"
    case tooLong = "ZU_LANG"
    case controlCharacters = "STEUERZEICHEN"
    case unknown

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = CampImportErrorCode(rawValue: value) ?? .unknown
    }
}

nonisolated struct CampImportError: Decodable, Equatable, Sendable {
    let line: Int
    let code: CampImportErrorCode
    let message: String

    enum CodingKeys: String, CodingKey { case line = "zeile", code, message }
}

nonisolated enum CampImportDuplicateReason: String, Decodable, Sendable {
    /// Already a participant of the camp.
    case existing = "vorhanden"
    /// Twice in the pasted text.
    case inText = "im_text"
    case unknown

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = CampImportDuplicateReason(rawValue: value) ?? .unknown
    }
}

nonisolated struct CampImportDuplicate: Decodable, Equatable, Sendable {
    let line: Int
    let reason: CampImportDuplicateReason

    enum CodingKeys: String, CodingKey { case line = "zeile", reason = "grund" }
}

/// Answer of the import. With `preview` nothing is written: show the rows, errors and duplicates, then confirm
/// with `importCampParticipants`.
nonisolated struct CampParticipantImportResult: Decodable, Equatable, Sendable {
    let preview: Bool
    /// How many were created (0 in the preview).
    let created: Int
    let new: [CampImportRow]
    let errors: [CampImportError]
    let duplicates: [CampImportDuplicate]

    enum CodingKeys: String, CodingKey {
        case preview = "vorschau", created = "angelegt", new = "neu", errors = "fehler", duplicates = "doppelt"
    }
}

// MARK: Counting (Abzählen)

/// A row of the counting list. A participant has `participantId` and the name parts, a team member `personId` and `name`.
nonisolated struct CampCountEntry: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let participantId: UUID?
    let personId: UUID?
    let firstName: String?
    let lastName: String?
    let level: String?
    let name: String?
    let ceviName: String?
    /// The tick is shared: everybody who counts sees it.
    let checked: Bool
    let checkedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, ceviName
        case participantId = "teilnehmerId", personId, firstName = "vorname", lastName = "nachname", level = "stufe"
        case checked = "geprueft", checkedAt = "geprueftAm"
    }
}

nonisolated struct CampCountPage: Decodable, Equatable, Sendable {
    let entries: [CampCountEntry]
    let next: UUID?
    /// Ticked off.
    let present: Int
    let total: Int

    enum CodingKeys: String, CodingKey { case entries = "eintraege", next = "naechster", present = "da", total = "gesamt" }
}

nonisolated struct CampCountFilter: Equatable, Sendable {
    var kind: CampPeopleKind?
    var level: String?
    var groupId: UUID?

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let kind { items.append(URLQueryItem(name: "art", value: kind.rawValue)) }
        if let level { items.append(URLQueryItem(name: "stufe", value: level)) }
        if let groupId { items.append(URLQueryItem(name: "gruppe", value: groupId.uuidString.lowercased())) }
        return items
    }
}

nonisolated struct CampCountSetBody: Encodable, Sendable {
    let checked: Bool
    var participantIds: [UUID]?
    var personIds: [UUID]?

    enum CodingKeys: String, CodingKey { case checked = "geprueft", participantIds = "teilnehmerIds", personIds }
}

nonisolated struct CampCountResetBody: Encodable, Sendable {
    let confirmed: Bool

    enum CodingKeys: String, CodingKey { case confirmed = "bestaetigt" }
}

nonisolated struct CampCountChanged: Decodable, Equatable, Sendable {
    let changed: Int

    enum CodingKeys: String, CodingKey { case changed = "geaendert" }
}

nonisolated struct CampCountReset: Decodable, Equatable, Sendable {
    let reset: Int

    enum CodingKeys: String, CodingKey { case reset = "zurueckgesetzt" }
}

// MARK: Rooms and tents (Zimmer, Zelte)

nonisolated enum CampRoomKind: String, Codable, Sendable {
    case room = "zimmer"
    case tent = "zelt"
}

nonisolated enum CampRoomOccupantKind: String, Decodable, Sendable {
    case participant = "teilnehmer"
    case person
    case unknown

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = CampRoomOccupantKind(rawValue: value) ?? .unknown
    }
}

nonisolated struct CampRoomOccupant: Decodable, Equatable, Identifiable, Sendable {
    let kind: CampRoomOccupantKind
    let id: UUID
    let name: String

    enum CodingKeys: String, CodingKey { case kind = "typ", id, name }
}

/// A room or tent without occupants (the answer to create and change).
nonisolated struct CampRoomRow: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let version: Int
    let name: String
    let kind: CampRoomKind
    let places: Int
    let note: String?
    let order: Int

    enum CodingKeys: String, CodingKey { case id, version, name, kind = "art", places = "plaetze", note = "notiz", order = "reihenfolge" }
}

/// A room or tent with its occupants, as the camp leadership and leadership see it.
nonisolated struct CampRoom: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let version: Int
    let name: String
    let kind: CampRoomKind
    let places: Int
    let note: String?
    let order: Int
    let occupied: Int
    let overbooked: Bool
    let members: [CampRoomOccupant]

    enum CodingKeys: String, CodingKey {
        case id, version, name, kind = "art", places = "plaetze", note = "notiz", order = "reihenfolge"
        case occupied = "belegt", overbooked = "ueberbelegt", members = "mitglieder"
    }
}

/// The team sees only names and no counts.
nonisolated struct CampRoomTeamView: Decodable, Equatable, Identifiable, Sendable {
    nonisolated struct Member: Decodable, Equatable, Sendable { let name: String }

    let id: UUID
    let version: Int
    let name: String
    let kind: CampRoomKind
    let members: [Member]

    enum CodingKeys: String, CodingKey { case id, version, name, kind = "art", members = "mitglieder" }
}

/// Full shape for roles that see places and occupancy, short shape for the team. The shapes differ by `plaetze`.
nonisolated enum CampRoomView: Decodable, Equatable, Sendable {
    case full(CampRoom)
    case team(CampRoomTeamView)

    private enum Probe: String, CodingKey { case places = "plaetze" }

    init(from decoder: Decoder) throws {
        if try decoder.container(keyedBy: Probe.self).contains(.places) {
            self = .full(try CampRoom(from: decoder))
        } else {
            self = .team(try CampRoomTeamView(from: decoder))
        }
    }
}

nonisolated struct CampOpenCounts: Decodable, Equatable, Sendable {
    let participants: Int
    let team: Int

    enum CodingKeys: String, CodingKey { case participants = "teilnehmer", team }
}

nonisolated struct CampRoomList: Decodable, Equatable, Sendable {
    let rooms: [CampRoomView]
    /// How many are not placed yet. Absent for the team.
    let open: CampOpenCounts?

    enum CodingKeys: String, CodingKey { case rooms = "zimmer", open = "offen" }
}

nonisolated struct CampRoomOpenEntry: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    /// Team member.
    let name: String?
    let firstName: String?
    let lastName: String?
    let level: String?
    let ceviName: String?

    enum CodingKeys: String, CodingKey { case id, name, level = "stufe", ceviName, firstName = "vorname", lastName = "nachname" }
}

nonisolated struct CampRoomOpenPage: Decodable, Equatable, Sendable {
    let entries: [CampRoomOpenEntry]
    let next: UUID?

    enum CodingKeys: String, CodingKey { case entries = "eintraege", next = "naechster" }
}

nonisolated struct CampRoomCreate: Encodable, Sendable {
    var name: String
    var kind: CampRoomKind
    /// 1 to 1000.
    var places: Int
    var note: String?
    var order: Int?

    enum CodingKeys: String, CodingKey { case name, kind = "art", places = "plaetze", note = "notiz", order = "reihenfolge" }
}

nonisolated struct CampRoomPatch: Encodable, Sendable {
    let version: Int
    var name: String?
    var kind: CampRoomKind?
    var places: Int?
    var note: CampField<String>?
    var order: Int?

    enum CodingKeys: String, CodingKey { case version, name, kind = "art", places = "plaetze", note = "notiz", order = "reihenfolge" }
}

/// People to place into a room, or to take out of it.
nonisolated struct CampRoomPeople: Encodable, Sendable {
    var participantIds: [UUID]?
    var personIds: [UUID]?

    enum CodingKeys: String, CodingKey { case participantIds = "teilnehmerIds", personIds }
}

/// Answer of placing or removing. Placing over the places is allowed: `overbooked` tells.
nonisolated struct CampRoomOccupancy: Decodable, Equatable, Sendable {
    /// How many were placed (`eingeteilt`) or taken out (`entfernt`).
    let changed: Int
    let occupied: Int
    let places: Int
    let overbooked: Bool

    private enum CodingKeys: String, CodingKey {
        case placed = "eingeteilt", removed = "entfernt", occupied = "belegt", places = "plaetze", overbooked = "ueberbelegt"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        changed = try c.decodeIfPresent(Int.self, forKey: .placed) ?? c.decode(Int.self, forKey: .removed)
        occupied = try c.decode(Int.self, forKey: .occupied)
        places = try c.decode(Int.self, forKey: .places)
        overbooked = try c.decode(Bool.self, forKey: .overbooked)
    }
}

// MARK: Trips (Fahrten)

nonisolated enum CampTripDirection: String, Codable, Sendable {
    case outbound = "hin"
    case inbound = "rueck"
}

nonisolated enum CampTripKind: String, Codable, Sendable {
    case car = "auto"
    case publicTransport = "oev"
}

nonisolated struct CampTripDriver: Decodable, Equatable, Sendable {
    let personId: UUID
    let name: String?
}

nonisolated struct CampTripPassenger: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let version: Int
    let personId: UUID?
    let participantId: UUID?
    let name: String
    let level: String?

    enum CodingKeys: String, CodingKey { case id, version, personId, participantId = "teilnehmerId", name, level = "stufe" }
}

nonisolated struct CampTrip: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let version: Int
    let direction: CampTripDirection
    let kind: CampTripKind
    let name: String?
    let driverPersonId: UUID?
    /// Seats for a car; `nil` for public transport.
    let places: Int?
    let date: Date?
    /// `HH:MM`.
    let time: String?
    let from: String?
    let to: String?
    let meetingPoint: String?
    let link: String?
    let destinationLabel: String?
    let destinationAddress: String?
    let destinationLat: Double?
    let destinationLon: Double?
    let destinationLink: String?
    let driver: CampTripDriver?
    let passengers: [CampTripPassenger]
    let occupied: Int
    /// `nil` without a seat limit.
    let free: Int?
    let overbooked: Bool

    enum CodingKeys: String, CodingKey {
        case id, version, name, places = "plaetze", date = "datum", time = "zeit", link, driver = "fahrer"
        case direction = "richtung", kind = "art", driverPersonId = "fahrerPersonId", from = "von", to = "nach"
        case meetingPoint = "treffpunkt", destinationLabel = "zielBezeichnung", destinationAddress = "zielAdresse"
        case destinationLat = "zielLat", destinationLon = "zielLon", destinationLink = "zielLink"
        case passengers = "mitfahrer", occupied = "belegt", free = "frei", overbooked = "ueberbelegt"
    }
}

nonisolated struct CampTripPage: Decodable, Equatable, Sendable {
    let trips: [CampTrip]
    let next: UUID?

    enum CodingKeys: String, CodingKey { case trips = "fahrten", next = "naechster" }
}

nonisolated struct CampTripCreate: Encodable, Sendable {
    var direction: CampTripDirection
    var kind: CampTripKind
    var name: String?
    var driverPersonId: UUID?
    var places: Int?
    var date: CampCalendarDay?
    var time: String?
    var from: String?
    var to: String?
    var meetingPoint: String?
    var link: String?
    var destinationLabel: String?
    var destinationAddress: String?
    var destinationLat: Double?
    var destinationLon: Double?
    var destinationLink: String?

    enum CodingKeys: String, CodingKey {
        case name, link, places = "plaetze", date = "datum", time = "zeit"
        case direction = "richtung", kind = "art", driverPersonId = "fahrerPersonId", from = "von", to = "nach"
        case meetingPoint = "treffpunkt", destinationLabel = "zielBezeichnung", destinationAddress = "zielAdresse"
        case destinationLat = "zielLat", destinationLon = "zielLon", destinationLink = "zielLink"
    }
}

/// Direction and kind do not change after creating.
nonisolated struct CampTripPatch: Encodable, Sendable {
    let version: Int
    var name: CampField<String>?
    var driverPersonId: CampField<UUID>?
    var places: CampField<Int>?
    var date: CampField<CampCalendarDay>?
    var time: CampField<String>?
    var from: CampField<String>?
    var to: CampField<String>?
    var meetingPoint: CampField<String>?
    var link: CampField<String>?
    var destinationLabel: CampField<String>?
    var destinationAddress: CampField<String>?
    var destinationLat: CampField<Double>?
    var destinationLon: CampField<Double>?
    var destinationLink: CampField<String>?

    enum CodingKeys: String, CodingKey {
        case version, name, link, places = "plaetze", date = "datum", time = "zeit"
        case driverPersonId = "fahrerPersonId", from = "von", to = "nach"
        case meetingPoint = "treffpunkt", destinationLabel = "zielBezeichnung", destinationAddress = "zielAdresse"
        case destinationLat = "zielLat", destinationLon = "zielLon", destinationLink = "zielLink"
    }
}

nonisolated struct CampTripPassengerCreate: Encodable, Sendable {
    /// Exactly one of the two.
    var personId: UUID?
    var participantId: UUID?

    enum CodingKeys: String, CodingKey { case personId, participantId = "teilnehmerId" }
}

nonisolated struct CampTripBoarding: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let version: Int
    let tripId: UUID
    let personId: UUID?
    let participantId: UUID?
    let occupied: Int
    let places: Int?
    let overbooked: Bool

    enum CodingKeys: String, CodingKey {
        case id, version, personId, tripId = "fahrtId", participantId = "teilnehmerId"
        case occupied = "belegt", places = "plaetze", overbooked = "ueberbelegt"
    }
}

nonisolated struct CampTripPersonWithout: Decodable, Equatable, Sendable {
    let personId: UUID?
    let participantId: UUID?
    let name: String
    let level: String?

    enum CodingKeys: String, CodingKey { case personId, participantId = "teilnehmerId", name, level = "stufe" }
}

/// People without a trip in one direction. The cursor of this list is plain text, not an ID.
nonisolated struct CampTripWithoutPage: Decodable, Equatable, Sendable {
    let people: [CampTripPersonWithout]
    let total: Int
    let next: String?

    enum CodingKeys: String, CodingKey { case people = "personen", total = "gesamt", next = "naechster" }
}

// MARK: Groups (Gruppen)

nonisolated enum CampGroupRole: String, Codable, Sendable {
    case leader = "leitung"
    case member = "mitglied"
}

nonisolated struct CampGroupPerson: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let ceviName: String?
    let role: CampGroupRole

    enum CodingKeys: String, CodingKey { case id = "personId", name, ceviName, role = "rolle" }
}

nonisolated struct CampGroupParticipant: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let firstName: String
    let lastName: String
    let level: String?
    let ceviName: String?

    enum CodingKeys: String, CodingKey { case id, ceviName, firstName = "vorname", lastName = "nachname", level = "stufe" }
}

/// A group without people (the answer to create and change).
nonisolated struct CampGroupRow: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let version: Int
    let name: String
    let order: Int

    enum CodingKeys: String, CodingKey { case id, version, name, order = "reihenfolge" }
}

nonisolated struct CampGroup: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let version: Int
    let name: String
    let order: Int
    let people: [CampGroupPerson]
    let participants: [CampGroupParticipant]

    enum CodingKeys: String, CodingKey { case id, version, name, order = "reihenfolge", people = "personen", participants = "teilnehmer" }
}

nonisolated struct CampGroupList: Decodable, Equatable, Sendable {
    let groups: [CampGroup]
    /// Participants without a group.
    let withoutGroup: Int
    let deselected: Int

    enum CodingKeys: String, CodingKey { case groups = "gruppen", withoutGroup = "ohneGruppe", deselected = "abgewaehlt" }
}

nonisolated struct CampGroupCreate: Encodable, Sendable {
    var name: String
    var order: Int?

    enum CodingKeys: String, CodingKey { case name, order = "reihenfolge" }
}

nonisolated struct CampGroupPatch: Encodable, Sendable {
    let version: Int
    var name: String?
    var order: Int?

    enum CodingKeys: String, CodingKey { case version, name, order = "reihenfolge" }
}

/// Puts people into a group (`groupId`), or takes them out of every group (`nil`, sent as `null`).
nonisolated struct CampGroupAssign: Encodable, Sendable {
    var groupId: UUID?
    var participantIds: [UUID]?
    var personIds: [UUID]?
    /// For team members only.
    var role: CampGroupRole?

    enum CodingKeys: String, CodingKey { case groupId = "gruppeId", participantIds = "teilnehmerIds", personIds, role = "rolle" }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(groupId, forKey: .groupId) // required, `null` means no group
        try c.encodeIfPresent(participantIds, forKey: .participantIds)
        try c.encodeIfPresent(personIds, forKey: .personIds)
        try c.encodeIfPresent(role, forKey: .role)
    }
}

nonisolated struct CampDeselectBody: Encodable, Sendable {
    let deselected: Bool
    let participantIds: [UUID]

    enum CodingKeys: String, CodingKey { case deselected = "abgewaehlt", participantIds = "teilnehmerIds" }
}

nonisolated struct CampGroupShuffleBody: Encodable, Sendable {
    /// 2 to 20.
    let count: Int
    let confirm: Bool
    let seed: Int?

    enum CodingKeys: String, CodingKey { case count = "anzahl", confirm = "uebernehmen", seed }
}

nonisolated struct CampShuffleParticipant: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let firstName: String
    let lastName: String
    let level: String?

    enum CodingKeys: String, CodingKey { case id, firstName = "vorname", lastName = "nachname", level = "stufe" }
}

nonisolated struct CampShuffleGroup: Decodable, Equatable, Sendable {
    /// Position, from 1.
    let number: Int
    /// `nil` in the preview if the group does not exist yet.
    let groupId: UUID?
    let name: String
    let count: Int
    let participants: [CampShuffleParticipant]

    enum CodingKeys: String, CodingKey { case number = "nummer", groupId = "gruppeId", name, count = "anzahl", participants = "teilnehmer" }
}

/// The suggestion (`preview` true, nothing written) or the confirmed result (`changed` set). Confirm with
/// `confirmCampGroupShuffle`: the same `seed` gives the same mix as long as the participants did not change.
nonisolated struct CampGroupShuffle: Decodable, Equatable, Sendable {
    let preview: Bool
    let seed: Int
    let groups: [CampShuffleGroup]
    let changed: Int?

    enum CodingKeys: String, CodingKey { case preview = "vorschau", seed, groups = "gruppen", changed = "geaendert" }
}
