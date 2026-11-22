import Foundation

// Attendance names people only by ID; the app resolves names from the member and participant lists. Participants are
// children and young people: their attendance never goes into widgets, notifications, logs or analytics.

/// `A` present, `F` absent, `O` open (no entry).
nonisolated enum CampAttendanceValue: String, Codable, Sendable {
    case present = "A"
    case absent = "F"
    case open = "O"
}

/// One field of the matrix: a person on a day section. Exactly one of `personId` and `participantId` is set.
/// A person without an entry is open.
nonisolated struct CampAttendanceEntry: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let version: Int
    let personId: UUID?
    let participantId: UUID?
    let dayId: UUID
    let sectionId: UUID
    let value: CampAttendanceValue

    enum CodingKeys: String, CodingKey {
        case id, version, personId, participantId = "teilnehmerId", dayId = "lagertagId", sectionId = "tagesabschnittId", value = "wert"
    }
}

/// The matrix of the camp leadership. `deadline`: until when the team sets its own attendance directly; `nil` without one.
nonisolated struct CampAttendancePage: Codable, Equatable, Sendable {
    let entries: [CampAttendanceEntry]
    /// Cursor for the next page (`nach`); `nil` at the end.
    let next: UUID?
    let deadline: Date?

    enum CodingKeys: String, CodingKey { case entries = "eintraege", next = "naechster", deadline = "frist" }
}

nonisolated struct CampAttendanceEntryList: Codable, Equatable, Sendable {
    let entries: [CampAttendanceEntry]

    enum CodingKeys: String, CodingKey { case entries = "eintraege" }
}

// MARK: Requests (Anfragen)

nonisolated enum CampAttendanceRequestStatus: String, Codable, Sendable {
    case open = "offen"
    case accepted = "angenommen"
    case rejected = "abgelehnt"
}

/// A request of a team member to change a field that is set already (or after the deadline). The camp leadership decides.
nonisolated struct CampAttendanceRequest: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    /// The decision sends it along.
    let version: Int
    /// Who asked.
    let personId: UUID
    let dayId: UUID
    let sectionId: UUID
    /// The value the person asks for.
    let value: CampAttendanceValue
    /// Free remark, up to 500 characters.
    let note: String?
    let status: CampAttendanceRequestStatus
    let decidedBy: UUID?
    let decidedAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, version, personId, status
        case dayId = "lagertagId", sectionId = "tagesabschnittId", value = "wert", note = "notiz"
        case decidedBy = "entschiedenVon", decidedAt = "entschiedenAm", createdAt = "erstelltAm"
    }
}

/// The own fields and the own requests (the last 200, newest first) of the signed-in person.
nonisolated struct CampOwnAttendance: Codable, Equatable, Sendable {
    let entries: [CampAttendanceEntry]
    let requests: [CampAttendanceRequest]
    let deadline: Date?

    enum CodingKeys: String, CodingKey { case entries = "eintraege", requests = "anfragen", deadline = "frist" }
}

nonisolated struct CampAttendanceRequestPage: Codable, Equatable, Sendable {
    let requests: [CampAttendanceRequest]
    let next: UUID?

    enum CodingKeys: String, CodingKey { case requests = "anfragen", next = "naechster" }
}

nonisolated struct CampAttendanceRequestList: Codable, Equatable, Sendable {
    let requests: [CampAttendanceRequest]

    enum CodingKeys: String, CodingKey { case requests = "anfragen" }
}

// MARK: Summary and deadline

/// How many leaders and participants are entered for a day section and value.
nonisolated struct CampAttendanceSummaryRow: Codable, Equatable, Sendable {
    let dayId: UUID
    let sectionId: UUID
    let value: CampAttendanceValue
    let leaders: Int
    let participants: Int

    enum CodingKeys: String, CodingKey {
        case dayId = "lagertagId", sectionId = "tagesabschnittId", value = "wert", leaders = "leitende", participants = "teilnehmende"
    }
}

/// Numbers only, no names.
nonisolated struct CampAttendanceSummary: Codable, Equatable, Sendable {
    let rows: [CampAttendanceSummaryRow]

    enum CodingKeys: String, CodingKey { case rows = "zeilen" }
}

nonisolated struct CampAttendanceDeadline: Codable, Equatable, Sendable {
    let deadline: Date?

    enum CodingKeys: String, CodingKey { case deadline = "frist" }
}

// MARK: Writing

/// A field the team sets for itself or asks for. The person is always the signed-in one.
nonisolated struct CampAttendanceField: Codable, Equatable, Sendable {
    let dayId: UUID
    let sectionId: UUID
    let value: CampAttendanceValue

    enum CodingKeys: String, CodingKey { case dayId = "lagertagId", sectionId = "tagesabschnittId", value = "wert" }

    /// A whole day with one tap: the same value for every section (at most 100 fields per call).
    static func wholeDay(_ dayId: UUID, sectionIds: [UUID], value: CampAttendanceValue) -> [CampAttendanceField] {
        sectionIds.map { CampAttendanceField(dayId: dayId, sectionId: $0, value: value) }
    }
}

nonisolated struct CampAttendanceFieldsBody: Encodable, Sendable {
    let entries: [CampAttendanceField]
    /// Only for a request: free remark for the camp leadership (1 to 500 characters).
    var note: String?

    enum CodingKeys: String, CodingKey { case entries = "eintraege", note = "notiz" }
}

/// A field the camp leadership sets for any person. `version` is the last seen version of a field that is set already.
nonisolated struct CampAttendanceLeaderField: Encodable, Equatable, Sendable {
    /// Exactly one of `personId` and `participantId`.
    var personId: UUID?
    var participantId: UUID?
    let dayId: UUID
    let sectionId: UUID
    let value: CampAttendanceValue
    var version: Int?

    enum CodingKeys: String, CodingKey {
        case personId, participantId = "teilnehmerId", dayId = "lagertagId", sectionId = "tagesabschnittId", value = "wert", version
    }
}

nonisolated struct CampAttendanceLeaderBody: Encodable, Sendable {
    let entries: [CampAttendanceLeaderField]

    enum CodingKeys: String, CodingKey { case entries = "eintraege" }
}

/// `nil` lifts the deadline. The key is sent as `null`.
nonisolated struct CampAttendanceDeadlineBody: Encodable, Sendable {
    let deadline: Date?

    enum CodingKeys: String, CodingKey { case deadline = "frist" }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(deadline, forKey: .deadline)
    }
}

nonisolated enum CampAttendanceDecisionKind: String, Codable, Sendable {
    case accepted = "angenommen"
    case rejected = "abgelehnt"
}

/// At most 50 open requests per call, each with the last seen version. A whole day is one request per section.
nonisolated struct CampAttendanceDecisionBody: Encodable, Sendable {
    let decision: CampAttendanceDecisionKind
    let requests: [CampVersionRef]

    enum CodingKeys: String, CodingKey { case decision = "entscheid", requests = "anfragen" }
}

// MARK: Conflict 409 ANFRAGE_NOETIG

nonisolated enum CampAttendanceBlockReason: String, CampTolerantEnum {
    /// The field has another value already.
    case entered = "eingetragen"
    /// The deadline has passed.
    case deadline = "frist"
    case unknown

    static var fallback: Self { .unknown }
}

nonisolated struct CampAttendanceBlocked: Codable, Equatable, Sendable {
    let dayId: UUID
    let sectionId: UUID
    let reason: CampAttendanceBlockReason

    enum CodingKeys: String, CodingKey { case dayId = "lagertagId", sectionId = "tagesabschnittId", reason = "grund" }
}

nonisolated struct CampAttendanceBlockedBody: Decodable, Sendable {
    let blocked: [CampAttendanceBlocked]

    enum CodingKeys: String, CodingKey { case blocked = "gesperrt" }
}
