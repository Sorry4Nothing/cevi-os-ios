import Foundation

/// A person's answer for a child or for themselves. `nil` where used means "open" (no answer yet).
nonisolated enum Answer: String, Codable, Sendable {
    case yes = "ja"
    case no = "nein"
}

nonisolated enum ProgramStatus: String, Decodable, Sendable {
    case active = "aktiv"
    case cancelled = "abgesagt"
    /// The calendar sync could not find the program any more; the leaders check it.
    case review = "pruefen"
}

nonisolated enum Visibility: String, Decodable, Sendable {
    case internalOnly = "intern"
    case leaders = "leitende"
    case parents = "eltern"
}

nonisolated struct UnitRef: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
}

/// One of the person's own children, with their answer for this program.
nonisolated struct ProgramChild: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let firstName: String
    let answer: Answer?

    enum CodingKeys: String, CodingKey {
        case id, firstName = "vorname", answer = "status"
    }
}

/// A program from the list (`GET /programme`) or the detail (`GET /programme/{id}`). Detail-only fields are `nil` in the list.
nonisolated struct Program: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let status: ProgramStatus
    let visibility: Visibility
    let isAllDay: Bool
    let start: Date?
    let end: Date?
    let dayFrom: Date?
    let dayTo: Date?
    let location: String?
    let units: [UnitRef]
    /// Only filled with leader view.
    let description: String?
    let children: [ProgramChild]

    // Detail only
    let meetingPoint: String?
    let closingPlace: String?
    /// `HH:mm`
    let closingTime: String?
    let bring: String?
    let isRegistrationOpen: Bool?
    /// The person's own registration as a leader. `nil` if the person is not a leader of an assigned unit.
    let ownRegistration: OwnRegistration?

    enum CodingKeys: String, CodingKey {
        case id, units = "stufen", visibility = "sichtbarkeit", status, start = "beginn", end = "ende"
        case title = "titel", isAllDay = "ganztaegig", dayFrom = "tagVon", dayTo = "tagBis"
        case location = "googleOrt", description = "googleBeschreibung", children = "kinder"
        case meetingPoint = "treffpunkt", closingPlace = "schlussOrt", closingTime = "schlussZeit"
        case bring = "mitnehmen", isRegistrationOpen = "teilnahmeOffen", ownRegistration = "eigeneAnmeldung"
    }
}

/// `eigeneAnmeldung`: `ja`, `nein` or `offen`.
nonisolated enum OwnRegistration: String, Decodable, Sendable {
    case yes = "ja"
    case no = "nein"
    case open = "offen"

    var answer: Answer? {
        switch self {
        case .yes: .yes
        case .no: .no
        case .open: nil
        }
    }
}

nonisolated struct ProgramList: Decodable, Sendable {
    let programs: [Program]

    enum CodingKeys: String, CodingKey { case programs = "programme" }
}

nonisolated struct Contact: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let ceviName: String?
    let imageURL: String?
    let phone: String?

    enum CodingKeys: String, CodingKey {
        case id, name, ceviName, imageURL = "bildUrl", phone = "telefon"
    }
}

nonisolated struct ContactList: Decodable, Sendable {
    let contacts: [Contact]

    enum CodingKeys: String, CodingKey { case contacts = "kontakte" }
}

/// Day logic for programs in Swiss calendar days.
nonisolated extension Program {
    private static var calendar: Calendar { DateFormats.calendar }

    /// First day of the program (start of day, Swiss time).
    var firstDay: Date? {
        if let dayFrom { return dayFrom }
        return start.map { Self.calendar.startOfDay(for: $0) }
    }

    /// Last day of the program, inclusive. A program ending exactly at midnight ends the day before.
    var lastDay: Date? {
        if let dayTo { return dayTo }
        guard let end, let start else { return firstDay }
        let effectiveEnd = end > start ? end.addingTimeInterval(-1) : end
        return Self.calendar.startOfDay(for: effectiveEnd)
    }

    /// All days from `firstDay` to `lastDay`, inclusive.
    var days: [Date] {
        guard let first = firstDay, let last = lastDay, first <= last else { return firstDay.map { [$0] } ?? [] }
        var result: [Date] = []
        var day = first
        while day <= last, result.count < 400 {
            result.append(day)
            guard let next = Self.calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    /// Whether the person can still answer for the children (detail only; the list does not know).
    var canAnswer: Bool { isRegistrationOpen ?? (status == .active) }
}
