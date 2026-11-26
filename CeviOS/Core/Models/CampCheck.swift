import Foundation

/// Stand of the camp check or of one checker. The server calculates it on every request and stores nothing.
nonisolated enum CampCheckState: String, Codable, Equatable, Sendable {
    case ready = "bereit"
    case notes = "hinweise"
    case open = "offen"
}

/// The checker an entry belongs to. A checker the server adds later decodes as `.unknown`.
nonisolated enum CampCheckerId: String, CampTolerantEnum, Equatable, Sendable {
    case tasks = "aufgaben"
    case milestones = "meilensteine"
    case packing = "packliste"
    case emergency = "notfall"
    case addressBook = "adressbuch"
    case own = "eigene"
    case unknown

    static var fallback: CampCheckerId { .unknown }
}

/// `open`: the camp is not ready. `note`: good to know.
nonisolated enum CampCheckSeverity: String, Codable, Equatable, Sendable {
    case open = "offen"
    case note = "hinweis"
}

/// One example behind a note: a task (deadline), a milestone (date) or an own point (no date).
nonisolated struct CampCheckExample: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let date: Date?
    /// Only for milestones and only with the right to all tasks.
    let openTasks: Int?

    enum CodingKeys: String, CodingKey { case id, title = "titel", date = "datum", openTasks = "offeneAufgaben" }
}

nonisolated struct CampCheckNote: Codable, Equatable, Sendable {
    /// Fixed key, for example `AUFGABEN_UEBERFAELLIG`.
    let code: String
    let severity: CampCheckSeverity
    let text: String
    /// Total behind the note; the examples are limited to five.
    let count: Int?
    let examples: [CampCheckExample]

    enum CodingKeys: String, CodingKey { case code, severity = "schwere", text, count = "anzahl", examples = "beispiele" }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decode(String.self, forKey: .code)
        severity = try c.decode(CampCheckSeverity.self, forKey: .severity)
        text = try c.decode(String.self, forKey: .text)
        count = try c.decodeIfPresent(Int.self, forKey: .count)
        examples = try c.decodeIfPresent([CampCheckExample].self, forKey: .examples) ?? []
    }

    init(code: String, severity: CampCheckSeverity, text: String, count: Int? = nil, examples: [CampCheckExample] = []) {
        self.code = code
        self.severity = severity
        self.text = text
        self.count = count
        self.examples = examples
    }
}

nonisolated struct CampChecker: Codable, Equatable, Identifiable, Sendable {
    let id: CampCheckerId
    let title: String
    let state: CampCheckState
    let notes: [CampCheckNote]

    enum CodingKeys: String, CodingKey { case id, title = "titel", state = "stand", notes = "hinweise" }
}

/// `GET /lager/{id}/check`. Only the checkers the role may read.
nonisolated struct CampCheck: Codable, Equatable, Sendable {
    let state: CampCheckState
    /// The day of the calculation (Zurich time).
    let date: Date
    let checkers: [CampChecker]

    enum CodingKeys: String, CodingKey { case state = "stand", date = "datum", checkers = "pruefer" }
}

/// An own point of the camp. `version` rises by one with every change.
nonisolated struct CampCheckPoint: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let version: Int
    let title: String
    let done: Bool
    let order: Int

    enum CodingKeys: String, CodingKey { case id, version, title = "titel", done = "erledigt", order = "reihenfolge" }
}

nonisolated struct CampCheckPoints: Codable, Equatable, Sendable {
    let points: [CampCheckPoint]

    enum CodingKeys: String, CodingKey { case points = "punkte" }
}

/// Without `order` the point goes to the end. Title 1 to 200 characters.
nonisolated struct CampCheckPointCreate: Encodable, Sendable {
    var title: String
    var order: Int?

    enum CodingKeys: String, CodingKey { case title = "titel", order = "reihenfolge" }
}

/// At least one field besides the version.
nonisolated struct CampCheckPointPatch: Encodable, Sendable {
    var version: Int
    var title: String?
    var done: Bool?
    var order: Int?

    enum CodingKeys: String, CodingKey { case version, title = "titel", done = "erledigt", order = "reihenfolge" }
}
