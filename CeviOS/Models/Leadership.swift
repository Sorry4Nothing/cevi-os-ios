import Foundation

/// Answer including "open" (no answer yet), as the overviews report it.
nonisolated enum OverviewAnswer: String, Decodable, Sendable {
    case yes = "ja"
    case no = "nein"
    case open = "offen"
}

nonisolated struct ParticipationCounts: Decodable, Equatable, Sendable {
    let yes: Int
    let no: Int
    let open: Int

    enum CodingKeys: String, CodingKey { case yes = "ja", no = "nein", open = "offen" }
}

nonisolated struct ParticipationChild: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let firstName: String
    let lastName: String
    let unitId: UUID
    let answer: OverviewAnswer

    enum CodingKeys: String, CodingKey {
        case id, firstName = "vorname", lastName = "nachname", unitId = "stufeId", answer = "status"
    }
}

nonisolated struct ParticipationLeader: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let ceviName: String?
    let unitId: UUID
    let role: RoleType
    let answer: OverviewAnswer

    enum CodingKeys: String, CodingKey {
        case id, name, ceviName, unitId = "stufeId", role = "rolle", answer = "status"
    }
}

/// `GET /programme/{id}/teilnahmen`. The server computes the numbers; the app does not recount.
nonisolated struct ParticipationOverview: Decodable, Equatable, Sendable {
    struct Totals: Decodable, Equatable, Sendable {
        let children: ParticipationCounts
        let leaders: ParticipationCounts

        enum CodingKeys: String, CodingKey { case children = "kinder", leaders = "leitende" }
    }

    let totals: Totals
    let children: [ParticipationChild]
    let leaders: [ParticipationLeader]

    enum CodingKeys: String, CodingKey { case totals = "zahlen", children = "kinder", leaders = "leitende" }
}

/// Attendance of a person at one event. `nil` means "not recorded".
nonisolated enum Presence: String, Decodable, Sendable {
    case present = "da"
    case absent = "nicht_da"

    var flag: Bool { self == .present }
}

nonisolated struct AttendanceEvent: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let isAllDay: Bool
    let start: Date?
    let end: Date?
    let dayFrom: Date?
    let dayTo: Date?
    let isPast: Bool
    /// Recording is possible from the start until 14 days after.
    let isRecordable: Bool

    enum CodingKeys: String, CodingKey {
        case id, title = "titel", isAllDay = "ganztaegig", start = "beginn", end = "ende"
        case dayFrom = "tagVon", dayTo = "tagBis", isPast = "vergangen", isRecordable = "erfassbar"
    }
}

nonisolated struct AttendanceQuota: Decodable, Equatable, Sendable {
    let present: Int
    let of: Int
    let percent: Int?

    enum CodingKeys: String, CodingKey { case present = "da", of = "von", percent = "prozent" }
}

/// One person's rows: both arrays have one entry per event, in the order of `AttendanceOverview.events`.
nonisolated struct AttendanceRows: Decodable, Equatable, Sendable {
    let attendance: [Presence?]
    let answers: [OverviewAnswer]
    let quota: AttendanceQuota

    enum CodingKeys: String, CodingKey { case attendance = "anwesenheit", answers = "zusage" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        attendance = try c.decode([Presence?].self, forKey: .attendance)
        answers = try c.decode([OverviewAnswer].self, forKey: .answers)
        quota = try AttendanceQuota(from: decoder)
    }
}

nonisolated struct AttendanceChild: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let firstName: String
    let lastName: String
    let rows: AttendanceRows

    enum CodingKeys: String, CodingKey { case id, firstName = "vorname", lastName = "nachname" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        firstName = try c.decode(String.self, forKey: .firstName)
        lastName = try c.decode(String.self, forKey: .lastName)
        rows = try AttendanceRows(from: decoder)
    }
}

nonisolated struct AttendanceLeader: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let ceviName: String?
    let role: RoleType
    let rows: AttendanceRows

    enum CodingKeys: String, CodingKey { case id, name, ceviName, role = "rolle" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        ceviName = try c.decodeIfPresent(String.self, forKey: .ceviName)
        role = try c.decode(RoleType.self, forKey: .role)
        rows = try AttendanceRows(from: decoder)
    }
}

/// `GET /stufen/{id}/anwesenheit`. Never cached.
nonisolated struct AttendanceOverview: Decodable, Equatable, Sendable {
    struct Unit: Decodable, Equatable, Sendable {
        let id: UUID
        let name: String
    }

    struct Totals: Decodable, Equatable, Sendable {
        let children: AttendanceQuota
        let leaders: AttendanceQuota

        enum CodingKeys: String, CodingKey { case children = "kinder", leaders = "leitende" }
    }

    let unit: Unit
    let events: [AttendanceEvent]
    let totals: Totals
    let children: [AttendanceChild]
    let leaders: [AttendanceLeader]

    enum CodingKeys: String, CodingKey {
        case unit = "stufe", events = "anlaesse", totals = "zahlen", children = "kinder", leaders = "leitende"
    }
}

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
