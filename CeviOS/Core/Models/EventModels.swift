import Foundation

// MARK: Mein Kalender (`GET /api/v1/termine/mein`, `GET /api/v1/termine/{id}`)

/// Kind of a tag. A kind the server adds later decodes as `.unknown`.
nonisolated enum EventTagKind: String, Decodable, Sendable {
    case unit = "stufe"
    case role = "funktion"
    case team
    case camp = "lager"
    case unknown

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = EventTagKind(rawValue: value) ?? .unknown
    }
}

/// A tag (category) of an event or of a suggestion.
nonisolated struct EventTag: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let kind: EventTagKind

    enum CodingKeys: String, CodingKey { case id, name, kind = "typ" }
}

/// `abgesagt` stays visible. `pruefen`: the event became unclear in the calendar of the department.
nonisolated enum EventStatus: String, Decodable, Sendable {
    case active = "aktiv"
    case cancelled = "abgesagt"
    case check = "pruefen"
    case unknown

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = EventStatus(rawValue: value) ?? .unknown
    }
}

/// Link from an event to the registration of an occasion (`GET /api/v1/anlaesse/{id}`).
nonisolated struct EventOccasionRef: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    /// `nil`: no deadline.
    let deadline: Date?
    let isOpen: Bool
    /// The person or one of the own children is registered.
    let isRegistered: Bool

    enum CodingKeys: String, CodingKey { case id, deadline = "anmeldeschluss", isOpen = "anmeldungOffen", isRegistered = "angemeldet" }
}

/// An own child whose unit hangs on the event. `answer` `nil` means "open".
nonisolated struct EventChild: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let firstName: String
    let answer: Answer?

    enum CodingKeys: String, CodingKey { case id, firstName = "vorname", answer = "status" }
}

/// A visible event of "Mein Kalender". The server lists every event once per person, however many of its tags the person has.
/// All-day events have `dayFrom`/`dayTo` (inclusive) and no `start`/`end`; the others the reverse.
nonisolated struct CalendarEvent: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let status: EventStatus
    let isAllDay: Bool
    let start: Date?
    let end: Date?
    let dayFrom: Date?
    let dayTo: Date?
    let place: String?
    /// Only the tags the person has herself.
    let tags: [EventTag]
    let occasion: EventOccasionRef?
    let children: [EventChild]

    enum CodingKeys: String, CodingKey {
        case id, status, tags
        case title = "titel", isAllDay = "ganztaegig", start = "beginn", end = "ende", dayFrom = "tagVon", dayTo = "tagBis"
        case place = "ort", occasion = "anlass", children = "kinder"
    }
}

/// Own registration of a leader for an event of the units. `open` is the state without an answer.
nonisolated enum EventOwnAnswer: String, Decodable, Sendable {
    case yes = "ja"
    case no = "nein"
    case open = "offen"
}

/// The event with the details of the unit page. `nil` fields: nothing matches the tag and the unit.
nonisolated struct CalendarEventDetail: Decodable, Equatable, Identifiable, Sendable {
    let event: CalendarEvent
    let meetingPoint: String?
    let endPlace: String?
    /// `HH:mm`.
    let endTime: String?
    let bring: String?
    /// Active and not yet started.
    let isParticipationOpen: Bool
    /// `nil`: the person leads no unit of the event.
    let ownRegistration: EventOwnAnswer?

    var id: UUID { event.id }

    private enum Keys: String, CodingKey {
        case meetingPoint = "treffpunkt", endPlace = "schlussOrt", endTime = "schlussZeit", bring = "mitnehmen"
        case isParticipationOpen = "teilnahmeOffen", ownRegistration = "eigeneAnmeldung"
    }

    init(from decoder: Decoder) throws {
        event = try CalendarEvent(from: decoder)
        let c = try decoder.container(keyedBy: Keys.self)
        meetingPoint = try c.decodeIfPresent(String.self, forKey: .meetingPoint)
        endPlace = try c.decodeIfPresent(String.self, forKey: .endPlace)
        endTime = try c.decodeIfPresent(String.self, forKey: .endTime)
        bring = try c.decodeIfPresent(String.self, forKey: .bring)
        isParticipationOpen = try c.decode(Bool.self, forKey: .isParticipationOpen)
        ownRegistration = try c.decodeIfPresent(EventOwnAnswer.self, forKey: .ownRegistration)
    }
}

/// One page of "Mein Kalender". `next` is opaque: the app only hands it back as `nach`, with the same period.
nonisolated struct CalendarEventPage: Decodable, Equatable, Sendable {
    let events: [CalendarEvent]
    let hasMore: Bool
    let next: String?

    enum CodingKeys: String, CodingKey { case events = "termine", hasMore = "weitere", next = "naechste" }

    /// This page followed by `page`; an event that is on both stays once.
    func appending(_ page: CalendarEventPage) -> CalendarEventPage {
        let known = Set(events.map(\.id))
        return CalendarEventPage(events: events + page.events.filter { !known.contains($0.id) }, hasMore: page.hasMore, next: page.next)
    }
}

// MARK: Personal calendar link (`/api/v1/ich/kalender-link`)

/// State of the own calendar link. The address itself is never in it.
nonisolated struct CalendarLinkStatus: Decodable, Equatable, Sendable {
    let isActive: Bool
    let createdAt: Date?
    /// Written by the feed at most once an hour, so it can be an hour behind.
    let lastFetchedAt: Date?
    /// The last four characters of the token, so the person recognises the link.
    let suffix: String?

    enum CodingKeys: String, CodingKey {
        case isActive = "aktiv", createdAt = "erstelltAm", lastFetchedAt = "zuletztAbgerufenAm", suffix = "endung"
    }
}

/// A new calendar link. **The link is a secret**: whoever has it reads the calendar of the person.
/// Never in logs, crash reports or widgets; show it once, only through the share sheet or the pasteboard on request.
/// The type prints no content (`description`), is not `Equatable` and has no coding to disk.
nonisolated struct CalendarLinkNew: Decodable, CustomStringConvertible, CustomDebugStringConvertible, Sendable {
    private let token: String
    /// `/ical/<token>.ics`: the app puts the base address of the API before it.
    private let path: String
    let createdAt: Date
    let suffix: String

    enum CodingKeys: String, CodingKey { case token, path = "pfad", createdAt = "erstelltAm", suffix = "endung" }

    /// The full address to share. Only the caller that created the link gets it; do not store it.
    func url(base: URL) -> URL? {
        URL(string: path, relativeTo: base)?.absoluteURL
    }

    var description: String { "CalendarLinkNew(…\(suffix))" }
    var debugDescription: String { description }
}

// MARK: Suggestions (`/api/v1/termin-vorschlaege`)

nonisolated struct EventSuggestionOptions: Decodable, Equatable, Sendable {
    let mayPropose: Bool
    /// Tags that can be chosen as category; empty if the person may not propose.
    let tags: [EventTag]

    enum CodingKeys: String, CodingKey { case mayPropose = "darfVorschlagen", tags }
}

nonisolated enum EventSuggestionStatus: String, Decodable, Sendable {
    case open = "offen"
    case approved = "freigegeben"
    case rejected = "abgelehnt"
    case enteredInCalendar = "in_outlook_eingetragen"
}

nonisolated struct EventSuggestion: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let status: EventSuggestionStatus
    let title: String
    let isAllDay: Bool
    let start: Date?
    let end: Date?
    let dayFrom: Date?
    let dayTo: Date?
    let place: String?
    let details: String?
    /// Note to the department lead, not part of the event.
    let note: String?
    let tags: [EventTag]
    /// Reason of a rejection.
    let reason: String?
    let decidedAt: Date?
    let createdAt: Date
    /// `nil` if the account of the person is deleted.
    let proposedBy: UUID?

    enum CodingKeys: String, CodingKey {
        case id, status, tags
        case title = "titel", isAllDay = "ganztaegig", start = "beginn", end = "ende", dayFrom = "tagVon", dayTo = "tagBis"
        case place = "ort", details = "beschreibung", note = "bemerkung", reason = "begruendung"
        case decidedAt = "entschiedenAm", createdAt = "erstelltAm", proposedBy = "vorgeschlagenVon"
    }
}

nonisolated struct EventSuggestionPage: Decodable, Equatable, Sendable {
    let suggestions: [EventSuggestion]
    let hasMore: Bool
    let next: UUID?

    enum CodingKeys: String, CodingKey { case suggestions = "vorschlaege", hasMore = "weitere", next = "naechste" }
}

/// Answer of `POST /api/v1/termin-vorschlaege`: the status is always `offen`.
nonisolated struct EventSuggestionCreated: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let status: EventSuggestionStatus
}

/// When a suggested event takes place. All-day: first and last day (Swiss calendar days). Timed: start and end with time zone.
nonisolated enum EventSuggestionTime: Equatable, Sendable {
    case allDay(from: Date, to: Date)
    case timed(start: Date, end: Date)
}

/// Body of a suggestion. Limits of the server: title 120, place 120, details 2000, note 1000 characters, 1 to 20 tags.
nonisolated struct EventSuggestionCreate: Encodable, Sendable {
    var title: String
    var time: EventSuggestionTime
    var place: String?
    var details: String?
    var note: String?
    var tagIds: [UUID]

    enum CodingKeys: String, CodingKey {
        case title = "titel", isAllDay = "ganztaegig", start = "beginn", end = "ende", dayFrom = "tagVon", dayTo = "tagBis"
        case place = "ort", details = "beschreibung", note = "bemerkung", tagIds
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(title, forKey: .title)
        switch time {
        case let .allDay(from, to):
            try c.encode(true, forKey: .isAllDay)
            try c.encode(DateFormats.calendarDayText(from), forKey: .dayFrom)
            try c.encode(DateFormats.calendarDayText(to), forKey: .dayTo)
        case let .timed(start, end):
            try c.encode(false, forKey: .isAllDay)
            try c.encode(DateFormats.timestampText(start), forKey: .start)
            try c.encode(DateFormats.timestampText(end), forKey: .end)
        }
        try c.encodeIfPresent(place, forKey: .place)
        try c.encodeIfPresent(details, forKey: .details)
        try c.encodeIfPresent(note, forKey: .note)
        try c.encode(tagIds.map { $0.uuidString.lowercased() }, forKey: .tagIds)
    }
}

// MARK: Rooms (`/api/v1/raeume`)

nonisolated struct RoomTeam: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
}

nonisolated struct Room: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let place: String?
    let details: String?
    let capacity: Int?
    let isActive: Bool
    /// The team that decides on requests; `nil`: the department lead decides.
    let team: RoomTeam?

    enum CodingKeys: String, CodingKey {
        case id, name, team
        case place = "ort", details = "beschreibung", capacity = "kapazitaet", isActive = "aktiv"
    }
}

/// `next` is opaque (the name of the last room).
nonisolated struct RoomPage: Decodable, Equatable, Sendable {
    let rooms: [Room]
    let hasMore: Bool
    let next: String?

    enum CodingKeys: String, CodingKey { case rooms = "raeume", hasMore = "weitere", next = "naechste" }
}

/// A confirmed request is the booking.
nonisolated enum RoomRequestStatus: String, Decodable, Sendable {
    case requested = "angefragt"
    case confirmed = "bestaetigt"
    case declined = "abgelehnt"
    case cancelled = "storniert"
}

nonisolated struct RoomRequest: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let roomId: UUID
    let roomName: String
    let start: Date
    let end: Date
    let purpose: String
    let status: RoomRequestStatus
    /// Reason of a rejection.
    let reason: String?
    let decidedAt: Date?
    let createdAt: Date
    /// Name of the requester; only in the list of open requests (`GET …/anfragen/offen`).
    let requesterName: String?

    enum CodingKeys: String, CodingKey {
        case id, status
        case roomId = "raumId", roomName = "raumName", start = "beginn", end = "ende", purpose = "zweck", reason = "begruendung"
        case decidedAt = "entschiedenAm", createdAt = "erstelltAm", requesterName = "vonName"
    }
}

nonisolated struct RoomRequestPage: Decodable, Equatable, Sendable {
    let requests: [RoomRequest]
    let hasMore: Bool
    let next: UUID?

    enum CodingKeys: String, CodingKey { case requests = "anfragen", hasMore = "weitere", next = "naechste" }
}

/// Answer of a new request or of a decision. `status` is `angefragt`, `bestaetigt` or `abgelehnt`.
nonisolated struct RoomRequestState: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let status: RoomRequestStatus
}

/// Body of a request. The start is in the future, the end after the start, at most 14 days; purpose one line, 1 to 200 characters,
/// no health data.
nonisolated struct RoomRequestCreate: Encodable, Sendable {
    var start: Date
    var end: Date
    var purpose: String

    enum CodingKeys: String, CodingKey { case start = "beginn", end = "ende", purpose = "zweck" }
}

/// Decision on a request. Rejecting needs a reason of 1 to 500 characters; accepting has none.
nonisolated enum RoomDecision: Encodable, Equatable, Sendable {
    case accept
    case decline(reason: String)

    private enum CodingKeys: String, CodingKey { case decision = "entscheid", reason = "begruendung" }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .accept:
            try c.encode("annehmen", forKey: .decision)
        case let .decline(reason):
            try c.encode("ablehnen", forKey: .decision)
            try c.encode(reason, forKey: .reason)
        }
    }
}

// MARK: Registration for an occasion (`/api/v1/anlaesse/{id}`)

/// Kind of a form field. A kind the server adds later decodes as `.unknown` (the app then cannot show the field).
nonisolated enum EventFieldKind: String, Decodable, Sendable {
    case text
    case yesNo = "ja_nein"
    case choice = "auswahl"
    case unknown

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = EventFieldKind(rawValue: value) ?? .unknown
    }
}

nonisolated struct EventField: Decodable, Equatable, Identifiable, Sendable {
    /// `[a-z0-9_]{1,40}`; key in the answers.
    let key: String
    let label: String
    let kind: EventFieldKind
    /// Only for `choice`.
    let options: [String]
    let isRequired: Bool

    var id: String { key }

    enum CodingKeys: String, CodingKey { case key = "schluessel", label = "beschriftung", kind = "typ", options = "optionen", isRequired = "pflicht" }
}

/// What the account already knows ("aus deinem Konto"). Shown, not editable. Never health data.
nonisolated struct EventAccountValue: Decodable, Equatable, Identifiable, Sendable {
    let key: String
    let label: String
    let value: String

    var id: String { key }

    enum CodingKeys: String, CodingKey { case key = "schluessel", label = "beschriftung", value = "wert" }
}

/// An answer: text, yes/no or the chosen option (as text).
nonisolated enum EventAnswerValue: Codable, Equatable, Sendable {
    case text(String)
    case bool(Bool)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let flag = try? c.decode(Bool.self) { self = .bool(flag) } else { self = .text(try c.decode(String.self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case let .text(value): try c.encode(value)
        case let .bool(value): try c.encode(value)
        }
    }
}

nonisolated enum EventRegistrationStatus: String, Decodable, Sendable {
    case registered = "angemeldet"
    case unregistered = "abgemeldet"
}

nonisolated struct EventRegistration: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let status: EventRegistrationStatus
    /// Empty when unregistered.
    let answers: [String: EventAnswerValue]
    let changedAt: Date

    enum CodingKeys: String, CodingKey { case id, status, answers = "antworten", changedAt = "geaendertAm" }
}

/// Who can be registered: a child (`childId`) or the person herself (`nil`).
nonisolated struct EventParticipant: Decodable, Equatable, Identifiable, Sendable {
    let childId: UUID?
    let name: String
    let account: [EventAccountValue]
    let registration: EventRegistration?

    var id: UUID? { childId }

    enum CodingKeys: String, CodingKey { case childId = "kindId", name, account = "konto", registration = "anmeldung" }
}

nonisolated enum EventRegistrationFor: String, Decodable, Sendable {
    case child = "kind"
    case person
}

/// The form of an occasion with the own registrations.
nonisolated struct EventRegistrationForm: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let eventId: UUID
    let title: String
    let isAllDay: Bool
    let start: Date?
    let end: Date?
    let dayFrom: Date?
    let dayTo: Date?
    /// Whether one can register now (allowed, deadline not over, event not cancelled or over).
    let isOpen: Bool
    let deadline: Date?
    let registrationFor: EventRegistrationFor
    let fields: [EventField]
    let participants: [EventParticipant]

    enum CodingKeys: String, CodingKey {
        case id, title = "titel", eventId = "terminId", isAllDay = "ganztaegig", start = "beginn", end = "ende"
        case dayFrom = "tagVon", dayTo = "tagBis", isOpen = "anmeldungOffen", deadline = "frist"
        case registrationFor = "anmeldungFuer", fields = "felder", participants = "teilnehmende"
    }
}

/// Body of `PUT …/anmeldung`. `childId` is required for `registrationFor == .child` and forbidden for `.person`.
nonisolated struct EventRegistrationBody: Encodable, Sendable {
    var childId: UUID?
    var answers: [String: EventAnswerValue]

    enum CodingKeys: String, CodingKey { case childId = "kindId", answers = "antworten" }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(childId?.uuidString.lowercased(), forKey: .childId)
        try c.encode(answers, forKey: .answers)
    }
}

/// One wrong answer of a 400 `ANTWORTEN_UNGUELTIG`: the key and why, never the value.
nonisolated struct EventAnswerError: Decodable, Equatable, Sendable {
    /// `UNBEKANNT`, `PFLICHT`, `TYP`, `OPTION`, `ZU_LANG`, `STEUERZEICHEN`.
    let code: String
    let key: String

    enum CodingKeys: String, CodingKey { case code, key = "schluessel" }
}

nonisolated struct EventAnswerErrorBody: Decodable, Sendable {
    let errors: [EventAnswerError]

    enum CodingKeys: String, CodingKey { case errors = "fehler" }
}
