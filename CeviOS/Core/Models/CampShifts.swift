import Foundation

// Names of participants in shifts are only for screens of the camp members, never for widgets, logs or notifications.

// MARK: Shift plan (Schichtplan)

/// A duty (for example kitchen). It belongs to a day section and applies on every camp day.
nonisolated struct CampDuty: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let version: Int
    let name: String
    let description: String?
    /// People per day the suggestion fills at least (1 to 20).
    let minStaff: Int
    /// Night watch.
    let night: Bool
    let sectionId: UUID
    let order: Int

    enum CodingKeys: String, CodingKey {
        case id, version, name, night = "nacht"
        case description = "beschreibung", minStaff = "mindestbesetzung", sectionId = "tagesabschnittId", order = "reihenfolge"
    }
}

/// One person on one duty on one day. Exactly one of `personId` and `participantId` is set.
nonisolated struct CampShift: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let version: Int
    let dutyId: UUID
    let dayId: UUID
    let date: Date
    let sectionId: UUID
    let personId: UUID?
    let participantId: UUID?
    /// For participants first name, last name and level, never the Cevi name.
    let name: String
    let ceviName: String?
    let level: String?

    enum CodingKeys: String, CodingKey {
        case id, version, name, ceviName, personId
        case dutyId = "dienstId", dayId = "lagertagId", date = "datum", sectionId = "tagesabschnittId"
        case participantId = "teilnehmerId", level = "stufe"
    }
}

nonisolated struct CampShiftStats: Decodable, Equatable, Sendable {
    let personId: UUID?
    let participantId: UUID?
    let name: String
    let count: Int
    let nightShifts: Int

    enum CodingKeys: String, CodingKey { case personId, participantId = "teilnehmerId", name, count = "anzahl", nightShifts = "nachtwachen" }
}

nonisolated struct CampShiftPlan: Decodable, Equatable, Sendable {
    let duties: [CampDuty]
    let shifts: [CampShift]
    let statistics: [CampShiftStats]

    enum CodingKeys: String, CodingKey { case duties = "dienste", shifts = "schichten", statistics = "statistik" }

    /// Open places of a duty on a day: `minStaff` minus the shifts there (never below 0).
    func freePlaces(duty: CampDuty, dayId: UUID) -> Int {
        max(0, duty.minStaff - shifts.filter { $0.dutyId == duty.id && $0.dayId == dayId }.count)
    }

    /// One whole German sentence per duty and day, in the order of the sections, then days, then duties, for a screen reader
    /// that reads the plan as a list. Duties of unknown sections are left out.
    func sentences(days: [CampDay], sections: [CampDaySection]) -> [String] {
        let orderedSections = sections.sorted { $0.order < $1.order }
        return days.sorted { $0.date < $1.date }.flatMap { day in
            orderedSections.flatMap { section in
                duties.filter { $0.sectionId == section.id }.sorted { ($0.order, $0.name) < ($1.order, $1.name) }.map { duty in
                    CampShiftText.sentence(
                        duty: duty.name, date: day.date, section: section.name,
                        people: shifts.filter { $0.dutyId == duty.id && $0.dayId == day.id }.map(\.name),
                        free: freePlaces(duty: duty, dayId: day.id)
                    )
                }
            }
        }
    }
}

/// Builds the sentence a screen reader says for a shift row.
nonisolated enum CampShiftText {
    /// "Küche, Montag Vormittag, Pat Muster, noch ein Platz frei". Several people are joined with «und», without
    /// people and without free places only duty, day and section remain.
    static func sentence(duty: String, date: Date, section: String, people: [String], free: Int) -> String {
        var parts = [duty, "\(weekday(date)) \(section)"]
        if !people.isEmpty { parts.append(list(people)) }
        switch free {
        case ..<1: break
        case 1: parts.append("noch ein Platz frei")
        default: parts.append("noch \(free) Plätze frei")
        }
        return parts.joined(separator: ", ")
    }

    private static func weekday(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: Locale(identifier: "de_CH"), calendar: DateFormats.calendar, timeZone: DateFormats.timeZone).weekday(.wide))
    }

    private static func list(_ names: [String]) -> String {
        guard names.count > 1, let last = names.last else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " und " + last
    }
}

nonisolated struct CampDutyCreate: Encodable, Sendable {
    var name: String
    var description: String?
    var minStaff: Int?
    var night: Bool?
    var sectionId: UUID
    var order: Int?

    enum CodingKeys: String, CodingKey {
        case name, night = "nacht"
        case description = "beschreibung", minStaff = "mindestbesetzung", sectionId = "tagesabschnittId", order = "reihenfolge"
    }
}

/// The section of a duty does not change after creating.
nonisolated struct CampDutyPatch: Encodable, Sendable {
    let version: Int
    var name: String?
    var description: CampField<String>?
    var minStaff: Int?
    var night: Bool?
    var order: Int?

    enum CodingKeys: String, CodingKey {
        case version, name, night = "nacht", description = "beschreibung", minStaff = "mindestbesetzung", order = "reihenfolge"
    }
}

/// Sets the staff of a duty on a day to exactly these people (at most 50 together); empty lists clear the day.
nonisolated struct CampShiftStaff: Encodable, Sendable {
    let dayId: UUID
    let dutyId: UUID
    var personIds: [UUID]?
    var participantIds: [UUID]?

    enum CodingKeys: String, CodingKey { case dayId = "lagertagId", dutyId = "dienstId", personIds, participantIds = "teilnehmerIds" }
}

// MARK: Suggestion "fill empty duties" and its confirmation

/// What the suggestion may use. The confirmation must send the same options as the suggestion.
nonisolated struct CampShiftOptions: Equatable, Sendable {
    /// `nil`: all camp days.
    var dayIds: [UUID]?
    /// `true`: only people marked present; `false`: also those still open.
    var onlyPresent = true
    /// Also place participants, not only members.
    var withParticipants = false
}

nonisolated struct CampShiftProposalBody: Encodable, Sendable {
    let confirm: Bool
    let seed: Int?
    let options: CampShiftOptions

    enum CodingKeys: String, CodingKey { case confirm = "uebernehmen", seed, dayIds = "lagertagIds", onlyPresent = "nurAnwesende", withParticipants = "mitTeilnehmenden" }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(confirm, forKey: .confirm)
        try c.encodeIfPresent(seed, forKey: .seed)
        try c.encodeIfPresent(options.dayIds, forKey: .dayIds)
        try c.encode(options.onlyPresent, forKey: .onlyPresent)
        try c.encode(options.withParticipants, forKey: .withParticipants)
    }
}

nonisolated struct CampShiftSuggestion: Decodable, Equatable, Sendable {
    let dayId: UUID
    let date: Date
    let dutyId: UUID
    let sectionId: UUID
    let personId: UUID?
    let participantId: UUID?
    let name: String

    enum CodingKeys: String, CodingKey {
        case name, personId, dayId = "lagertagId", date = "datum", dutyId = "dienstId", sectionId = "tagesabschnittId", participantId = "teilnehmerId"
    }
}

/// A place the suggestion could not fill.
nonisolated struct CampShiftUnfilled: Decodable, Equatable, Sendable {
    let dayId: UUID
    let dutyId: UUID
    let missing: Int

    enum CodingKeys: String, CodingKey { case dayId = "lagertagId", dutyId = "dienstId", missing = "fehlend" }
}

nonisolated struct CampShiftProposalStats: Decodable, Equatable, Sendable {
    let personId: UUID?
    let participantId: UUID?
    let name: String
    let before: Int
    let added: Int
    let total: Int
    let nightShifts: Int

    enum CodingKeys: String, CodingKey {
        case name, personId, participantId = "teilnehmerId", before = "vorher", added = "neu", total = "gesamt", nightShifts = "nachtwachen"
    }
}

/// The suggestion (`preview` true, nothing written) or the confirmed result (`changed` set). Confirm with
/// `confirmCampShifts` and the same options: the same `seed` gives the same suggestion while the plan did not change.
nonisolated struct CampShiftProposal: Decodable, Equatable, Sendable {
    let preview: Bool
    let seed: Int
    /// The run was cut at 2000 shifts.
    let truncated: Bool
    let shifts: [CampShiftSuggestion]
    let unfilled: [CampShiftUnfilled]
    let statistics: [CampShiftProposalStats]
    let changed: Int?

    enum CodingKeys: String, CodingKey {
        case preview = "vorschau", seed, truncated = "gekuerzt", shifts = "schichten", unfilled = "unbesetzt"
        case statistics = "statistik", changed = "geaendert"
    }
}

// MARK: Shift swaps (Diensttausch)

nonisolated enum CampSwapStatus: String, Codable, Sendable {
    case open = "offen"
    case accepted = "angenommen"
    case rejected = "abgelehnt"
    case withdrawn = "zurueckgezogen"
}

nonisolated enum CampSwapDecision: String, Encodable, Sendable {
    case accepted = "angenommen"
    case rejected = "abgelehnt"
}

nonisolated struct CampShiftSwap: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let version: Int
    /// The person who asks.
    let fromPersonId: UUID
    let shiftId: UUID
    /// The person asked, or `nil` if the request is open to whoever takes it.
    let withPersonId: UUID?
    let withShiftId: UUID?
    let note: String?
    let status: CampSwapStatus
    let decidedBy: UUID?
    let decidedAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, version, status
        case fromPersonId = "vonPersonId", shiftId = "schichtId", withPersonId = "mitPersonId", withShiftId = "mitSchichtId"
        case note = "notiz", decidedBy = "entschiedenVon", decidedAt = "entschiedenAm", createdAt = "erstelltAm"
    }
}

nonisolated struct CampShiftSwapPage: Decodable, Equatable, Sendable {
    let swaps: [CampShiftSwap]
    let next: UUID?

    enum CodingKeys: String, CodingKey { case swaps = "tausche", next = "naechster" }
}

nonisolated struct CampShiftSwapList: Decodable, Equatable, Sendable {
    let swaps: [CampShiftSwap]

    enum CodingKeys: String, CodingKey { case swaps = "tausche" }
}

nonisolated struct CampShiftSwapCreate: Encodable, Sendable {
    var shiftId: UUID
    var withShiftId: UUID?
    var withPersonId: UUID?
    var note: String?

    enum CodingKeys: String, CodingKey { case shiftId = "schichtId", withShiftId = "mitSchichtId", withPersonId = "mitPersonId", note = "notiz" }
}

nonisolated struct CampShiftSwapDecide: Encodable, Sendable {
    let decision: CampSwapDecision
    let version: Int
    var withPersonId: UUID?

    enum CodingKeys: String, CodingKey { case decision = "entscheid", version, withPersonId = "mitPersonId" }
}

nonisolated struct CampShiftSwapWithdraw: Encodable, Sendable {
    let version: Int
}
