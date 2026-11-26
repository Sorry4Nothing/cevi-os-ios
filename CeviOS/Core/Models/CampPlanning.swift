import Foundation

// MARK: Portfolios (Ressorts)

nonisolated struct CampPortfolio: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let version: Int
    /// Short code, unique in the camp.
    let code: String
    let name: String
    let leaderId: UUID?
    let deputyId: UUID?
    let note: String?
    /// The app builds the tree from this; the list is flat.
    let parentId: UUID?
    let order: Int
    let leader: CampPersonRef?
    let deputy: CampPersonRef?

    enum CodingKeys: String, CodingKey {
        case id, version, name
        case code = "kuerzel", leaderId = "leitungPersonId", deputyId = "stvPersonId", note = "notiz"
        case parentId, order = "reihenfolge", leader = "leitung", deputy = "stv"
    }
}

nonisolated struct CampPortfolioPage: Decodable, Equatable, Sendable {
    let portfolios: [CampPortfolio]
    let next: UUID?

    enum CodingKeys: String, CodingKey { case portfolios = "ressorts", next = "naechster" }
}

nonisolated struct CampPortfolioCreate: Encodable, Sendable {
    var code: String
    var name: String
    var leaderId: UUID?
    var deputyId: UUID?
    var note: String?
    var parentId: UUID?
    var order: Int?

    enum CodingKeys: String, CodingKey {
        case name
        case code = "kuerzel", leaderId = "leitungPersonId", deputyId = "stvPersonId", note = "notiz"
        case parentId, order = "reihenfolge"
    }
}

/// Only the fields that are set change. `.clear` sends `null` (empties leader, deputy, note or parent).
nonisolated struct CampPortfolioPatch: Encodable, Sendable {
    let version: Int
    var code: String?
    var name: String?
    var leaderId: CampField<UUID>?
    var deputyId: CampField<UUID>?
    var note: CampField<String>?
    var parentId: CampField<UUID>?
    var order: Int?

    enum CodingKeys: String, CodingKey {
        case version, name
        case code = "kuerzel", leaderId = "leitungPersonId", deputyId = "stvPersonId", note = "notiz"
        case parentId, order = "reihenfolge"
    }
}

nonisolated struct CampPortfolioLink: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let version: Int
    let portfolioId: UUID
    let title: String
    /// Only `https`, checked by the server.
    let url: String

    enum CodingKeys: String, CodingKey { case id, version, portfolioId = "ressortId", title = "titel", url }
}

nonisolated struct CampPortfolioLinkPage: Decodable, Equatable, Sendable {
    let links: [CampPortfolioLink]
    let next: UUID?

    enum CodingKeys: String, CodingKey { case links, next = "naechster" }
}

nonisolated struct CampLinkCreate: Encodable, Sendable {
    let title: String
    let url: String

    enum CodingKeys: String, CodingKey { case title = "titel", url }
}

nonisolated struct CampLinkPatch: Encodable, Sendable {
    let version: Int
    var title: String?
    var url: String?

    enum CodingKeys: String, CodingKey { case version, title = "titel", url }
}

nonisolated struct CampPortfolioNote: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let version: Int
    let portfolioId: UUID
    let text: String
    let authorId: UUID?
    let createdAt: Date
    let author: CampPersonRef?

    enum CodingKeys: String, CodingKey {
        case id, version, text, portfolioId = "ressortId", authorId = "vonPersonId", createdAt = "erstelltAm", author = "von"
    }
}

nonisolated struct CampPortfolioNotePage: Decodable, Equatable, Sendable {
    let notes: [CampPortfolioNote]
    let next: UUID?

    enum CodingKeys: String, CodingKey { case notes = "notizen", next = "naechster" }
}

/// Create body of a note, and of a to-do text.
nonisolated struct CampTextBody: Encodable, Sendable {
    let text: String
}

nonisolated struct CampNotePatch: Encodable, Sendable {
    let version: Int
    let text: String
}

// MARK: Tasks (Aufgaben)

nonisolated enum CampTaskStatus: String, Codable, Sendable {
    case open = "offen"
    case running = "laeuft"
    case waiting = "wartet"
    case done = "erledigt"
    case nextMeeting = "naechster_hoeck"
}

/// Repeat interval: every week, every two weeks, every month.
nonisolated enum CampTaskRepeat: String, Codable, Sendable {
    case weekly = "w1"
    case biweekly = "w2"
    case monthly = "m1"
}

nonisolated struct CampTaskResponsible: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String?
    let ceviName: String?
    /// True if the person follows from the portfolio leader (no person set on the task).
    let automatic: Bool

    enum CodingKeys: String, CodingKey { case id, name, ceviName, automatic = "automatisch" }
}

nonisolated struct CampTaskPortfolioRef: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let code: String
    let name: String

    enum CodingKeys: String, CodingKey { case id, name, code = "kuerzel" }
}

nonisolated struct CampTask: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let version: Int
    let title: String
    let portfolioId: UUID?
    /// Sub-area of the portfolio.
    let part: String?
    let responsibleId: UUID?
    let status: CampTaskStatus
    let note: String?
    let due: Date?
    /// Relative deadline: `dueOffsetDays` days from the milestone.
    let dueMilestoneId: UUID?
    let dueOffsetDays: Int?
    let starred: Bool
    let ongoing: Bool
    let laterFrom: Date?
    let repeatEvery: CampTaskRepeat?
    let order: Int
    let source: String?
    let completedAt: Date?
    let responsible: CampTaskResponsible?
    let portfolio: CampTaskPortfolioRef?
    let supporters: [CampPersonRef]

    enum CodingKeys: String, CodingKey {
        case id, version, status
        case title = "titel", portfolioId = "ressortId", part = "teil", responsibleId = "verantwortlichPersonId"
        case note = "notiz", due = "frist", dueMilestoneId = "fristMeilensteinId", dueOffsetDays = "fristVersatzTage"
        case starred = "stern", ongoing = "laufend", laterFrom = "spaeterAb", repeatEvery = "wiederholung"
        case order = "reihenfolge", source = "quelle", completedAt = "erledigtAm"
        case responsible = "verantwortlich", portfolio = "ressort", supporters = "unterstuetzung"
    }
}

nonisolated struct CampTaskPage: Decodable, Equatable, Sendable {
    let tasks: [CampTask]
    let next: UUID?

    enum CodingKeys: String, CodingKey { case tasks = "aufgaben", next = "naechster" }
}

/// Filters of the task list; all optional. The team only ever sees its own tasks, whatever the filter says.
nonisolated struct CampTaskFilter: Sendable {
    var portfolioId: UUID?
    var personId: UUID?
    var status: CampTaskStatus?
    var overdue: Bool?
    var starred: Bool?
    var keyword: String?
    var dueFrom: Date?
    var dueTo: Date?

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let portfolioId { items.append(.init(name: "ressortId", value: portfolioId.uuidString.lowercased())) }
        if let personId { items.append(.init(name: "personId", value: personId.uuidString.lowercased())) }
        if let status { items.append(.init(name: "status", value: status.rawValue)) }
        if let overdue { items.append(.init(name: "ueberfaellig", value: String(overdue))) }
        if let starred { items.append(.init(name: "stern", value: String(starred))) }
        if let keyword { items.append(.init(name: "stichwort", value: keyword)) }
        if let dueFrom { items.append(.init(name: "fristVon", value: DateFormats.calendarDayText(dueFrom))) }
        if let dueTo { items.append(.init(name: "fristBis", value: DateFormats.calendarDayText(dueTo))) }
        return items
    }
}

nonisolated struct CampTaskCreate: Encodable, Sendable {
    var title: String
    var portfolioId: UUID?
    var part: String?
    var responsibleId: UUID?
    var supporterIds: [UUID]?
    var status: CampTaskStatus?
    var note: String?
    var due: CampCalendarDay?
    var dueMilestoneId: UUID?
    var dueOffsetDays: Int?
    var starred: Bool?
    var ongoing: Bool?
    var laterFrom: CampCalendarDay?
    var repeatEvery: CampTaskRepeat?
    var order: Int?

    enum CodingKeys: String, CodingKey {
        case status
        case title = "titel", portfolioId = "ressortId", part = "teil", responsibleId = "verantwortlichPersonId"
        case supporterIds = "unterstuetzungPersonIds", note = "notiz", due = "frist", dueMilestoneId = "fristMeilensteinId"
        case dueOffsetDays = "fristVersatzTage", starred = "stern", ongoing = "laufend", laterFrom = "spaeterAb"
        case repeatEvery = "wiederholung", order = "reihenfolge"
    }
}

/// `supporterIds` replaces the whole support. `.clear` sends `null`.
nonisolated struct CampTaskPatch: Encodable, Sendable {
    let version: Int
    var title: String?
    var portfolioId: CampField<UUID>?
    var part: CampField<String>?
    var responsibleId: CampField<UUID>?
    var supporterIds: [UUID]?
    var status: CampTaskStatus?
    var note: CampField<String>?
    var due: CampField<CampCalendarDay>?
    var dueMilestoneId: CampField<UUID>?
    var dueOffsetDays: CampField<Int>?
    var starred: Bool?
    var ongoing: Bool?
    var laterFrom: CampField<CampCalendarDay>?
    var repeatEvery: CampField<CampTaskRepeat>?
    var order: Int?

    enum CodingKeys: String, CodingKey {
        case version, status
        case title = "titel", portfolioId = "ressortId", part = "teil", responsibleId = "verantwortlichPersonId"
        case supporterIds = "unterstuetzungPersonIds", note = "notiz", due = "frist", dueMilestoneId = "fristMeilensteinId"
        case dueOffsetDays = "fristVersatzTage", starred = "stern", ongoing = "laufend", laterFrom = "spaeterAb"
        case repeatEvery = "wiederholung", order = "reihenfolge"
    }
}

/// `PUT …/status`: the team may do this on its own tasks, nothing else.
nonisolated struct CampTaskStatusBody: Encodable, Sendable {
    let version: Int
    let status: CampTaskStatus
}

nonisolated struct CampDuplicateTask: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let version: Int
    let title: String
    let status: CampTaskStatus

    enum CodingKeys: String, CodingKey { case id, version, status, title = "titel" }
}

nonisolated struct CampDuplicateGroup: Decodable, Equatable, Sendable {
    let portfolioId: UUID?
    let title: String
    let tasks: [CampDuplicateTask]

    enum CodingKeys: String, CodingKey { case portfolioId = "ressortId", title = "titel", tasks = "aufgaben" }
}

nonisolated struct CampTaskDuplicates: Decodable, Equatable, Sendable {
    let groups: [CampDuplicateGroup]

    enum CodingKeys: String, CodingKey { case groups = "gruppen" }
}

/// `POST …/zusammenfuehren`: the task of the path absorbs `withId`; the second one goes to the recycle bin.
nonisolated struct CampTaskMergeBody: Encodable, Sendable {
    let version: Int
    let withId: UUID
    let withVersion: Int

    enum CodingKeys: String, CodingKey { case version, withId = "mitId", withVersion = "mitVersion" }
}

nonisolated struct CampChecklistItem: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let version: Int
    let taskId: UUID
    let text: String
    let done: Bool
    let doneById: UUID?
    let order: Int
    /// Only in the details (name of the person who ticked it).
    let doneBy: CampPersonRef?

    enum CodingKeys: String, CodingKey {
        case id, version, text, taskId = "aufgabeId", done = "erledigt", doneById = "erledigtVonPersonId"
        case order = "reihenfolge", doneBy = "erledigtVon"
    }
}

nonisolated struct CampTaskLink: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let version: Int
    let taskId: UUID
    let title: String
    let url: String

    enum CodingKeys: String, CodingKey { case id, version, taskId = "aufgabeId", title = "titel", url }
}

/// Checklist, links and keywords of a task (at most 100, 30 and 30 entries, so no paging).
nonisolated struct CampTaskDetails: Decodable, Equatable, Sendable {
    let taskId: UUID
    let checklist: [CampChecklistItem]
    let links: [CampTaskLink]
    let keywords: [String]

    enum CodingKeys: String, CodingKey { case taskId = "aufgabeId", checklist = "checkliste", links, keywords = "stichworte" }
}

nonisolated struct CampChecklistCreate: Encodable, Sendable {
    let text: String
    var order: Int?

    enum CodingKeys: String, CodingKey { case text, order = "reihenfolge" }
}

nonisolated struct CampChecklistPatch: Encodable, Sendable {
    let version: Int
    var text: String?
    var done: Bool?

    enum CodingKeys: String, CodingKey { case version, text, done = "erledigt" }
}

nonisolated struct CampKeywordsBody: Encodable, Sendable {
    let version: Int
    let keywords: [String]

    enum CodingKeys: String, CodingKey { case version, keywords = "stichworte" }
}

/// History of a task as far as the change feed reaches (30 days). Earlier versions of the content are not available.
nonisolated struct CampTaskHistory: Decodable, Equatable, Sendable {
    let taskId: UUID
    let createdAt: Date
    let createdBy: CampPersonRef?
    let changedAt: Date
    let changedBy: CampPersonRef?
    let entries: [CampChange]
    /// Cursor for older entries (`vor`); `nil` at the end.
    let next: Int?

    enum CodingKeys: String, CodingKey {
        case taskId = "aufgabeId", createdAt = "erstelltAm", createdBy = "erstelltVon"
        case changedAt = "geaendertAm", changedBy = "geaendertVon", entries = "eintraege", next = "naechster"
    }
}

// MARK: Quick entry (Schnelleingabe)

/// Result of matching `@Person` or `#Ressort` of a line.
nonisolated enum CampMatchStatus: String, Decodable, Sendable {
    case found = "gefunden"
    case ambiguous = "mehrdeutig"
    case unknown = "unbekannt"
}

nonisolated struct CampSuggestedPerson: Decodable, Equatable, Sendable {
    let status: CampMatchStatus
    /// The text typed after `@`.
    let text: String
    let candidates: [CampPersonRef]

    enum CodingKeys: String, CodingKey { case status, text, candidates = "kandidaten" }
}

nonisolated struct CampSuggestedPortfolio: Decodable, Equatable, Sendable {
    let status: CampMatchStatus
    /// The text typed after `#`.
    let text: String
    let candidates: [CampTaskPortfolioRef]

    enum CodingKeys: String, CodingKey { case status, text, candidates = "kandidaten" }
}

nonisolated struct CampSuggestedDeadline: Decodable, Equatable, Sendable {
    let date: Date
    let text: String

    enum CodingKeys: String, CodingKey { case date = "datum", text }
}

nonisolated enum CampSuggestionHint: String, Decodable, Sendable {
    case titleMissing = "TITEL_FEHLT"
    case titleTooLong = "TITEL_ZU_LANG"
    case invalidDate = "DATUM_UNGUELTIG"
    case unknown

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = CampSuggestionHint(rawValue: value) ?? .unknown
    }
}

/// A line of the quick entry as the server reads it. Nothing is saved yet: the app shows the proposal, the person
/// confirms (`CampTaskCreate(confirming:)`, then `createCampTask`).
nonisolated struct CampTaskSuggestion: Decodable, Equatable, Sendable {
    let line: String
    let title: String
    let person: CampSuggestedPerson?
    let portfolio: CampSuggestedPortfolio?
    let deadline: CampSuggestedDeadline?
    /// A suggestion with hints cannot be confirmed as it is.
    let hints: [CampSuggestionHint]

    enum CodingKeys: String, CodingKey {
        case title = "titel", line = "zeile", person, portfolio = "ressort", deadline = "frist", hints = "hinweise"
    }

    /// The only match of a name, if there is exactly one.
    var matchedPersonId: UUID? { person?.status == .found ? person?.candidates.first?.id : nil }
    var matchedPortfolioId: UUID? { portfolio?.status == .found ? portfolio?.candidates.first?.id : nil }
}

nonisolated struct CampTaskSuggestions: Decodable, Equatable, Sendable {
    let suggestions: [CampTaskSuggestion]

    enum CodingKeys: String, CodingKey { case suggestions = "vorschlaege" }
}

nonisolated struct CampQuickEntryBody: Encodable, Sendable {
    /// At most 500 characters and 20 lines, one task per line.
    let text: String
}

extension CampTaskCreate {
    /// The confirmation of a suggestion. `person` and `portfolio` are the choices of the person; without a choice
    /// the single match is taken, an ambiguous or unknown name stays empty.
    init(confirming suggestion: CampTaskSuggestion, person: UUID? = nil, portfolio: UUID? = nil) {
        self.init(title: suggestion.title)
        responsibleId = person ?? suggestion.matchedPersonId
        portfolioId = portfolio ?? suggestion.matchedPortfolioId
        due = suggestion.deadline.map { CampCalendarDay($0.date) }
    }
}

// MARK: Schedule (Zeitplan)

nonisolated struct CampMilestone: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let version: Int
    let title: String
    let date: Date
    /// Free kind, for example `frist`.
    let kind: String?

    enum CodingKeys: String, CodingKey { case id, version, title = "titel", date = "datum", kind = "art" }
}

nonisolated struct CampDay: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let version: Int
    let date: Date
    let label: String?

    enum CodingKeys: String, CodingKey { case id, version, date = "datum", label }
}

nonisolated struct CampDaySection: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let version: Int
    let name: String
    /// Free text, for example `08:00–12:00`.
    let time: String?
    let order: Int

    enum CodingKeys: String, CodingKey { case id, version, name, time = "zeit", order = "reihenfolge" }
}

nonisolated struct CampSchedule: Decodable, Equatable, Sendable {
    let milestones: [CampMilestone]
    let campDays: [CampDay]
    let sections: [CampDaySection]

    enum CodingKeys: String, CodingKey { case milestones = "meilensteine", campDays = "lagertage", sections = "tagesabschnitte" }
}

/// `GET …/zeitplan/vorschlag`: camp days and day sections the server would create. Nothing is saved yet.
nonisolated struct CampScheduleProposal: Decodable, Equatable, Sendable {
    nonisolated struct ProposedDay: Decodable, Equatable, Sendable {
        let date: Date
        enum CodingKeys: String, CodingKey { case date = "datum" }
    }

    nonisolated struct ProposedSection: Decodable, Equatable, Sendable {
        let name: String
        let order: Int
        enum CodingKeys: String, CodingKey { case name, order = "reihenfolge" }
    }

    let campDays: [ProposedDay]
    let sections: [ProposedSection]

    enum CodingKeys: String, CodingKey { case campDays = "lagertage", sections = "tagesabschnitte" }
}

/// `POST …/zeitplan/uebernehmen`: what the person confirmed. What exists already is skipped.
nonisolated struct CampScheduleAdopt: Encodable, Sendable {
    nonisolated struct Day: Encodable, Sendable {
        let date: CampCalendarDay
        var label: String?
        enum CodingKeys: String, CodingKey { case date = "datum", label }
    }

    nonisolated struct Section: Encodable, Sendable {
        let name: String
        var time: String?
        var order: Int?
        enum CodingKeys: String, CodingKey { case name, time = "zeit", order = "reihenfolge" }
    }

    var campDays: [Day]?
    var sections: [Section]?

    enum CodingKeys: String, CodingKey { case campDays = "lagertage", sections = "tagesabschnitte" }
}

/// Only what is new; the rows that existed are not listed.
nonisolated struct CampScheduleAdopted: Decodable, Equatable, Sendable {
    let campDays: [CampDay]
    let sections: [CampDaySection]

    enum CodingKeys: String, CodingKey { case campDays = "lagertage", sections = "tagesabschnitte" }
}

nonisolated struct CampMilestoneCreate: Encodable, Sendable {
    let title: String
    let date: CampCalendarDay
    var kind: String?

    enum CodingKeys: String, CodingKey { case title = "titel", date = "datum", kind = "art" }
}

/// The date is not changed here, but by moving (`CampMilestoneMoveBody`), so that the deadlines follow.
nonisolated struct CampMilestonePatch: Encodable, Sendable {
    let version: Int
    var title: String?
    var kind: CampField<String>?

    enum CodingKeys: String, CodingKey { case version, title = "titel", kind = "art" }
}

/// Both steps of moving a milestone use this body. `dryRun` true: preview, nothing is written. `dryRun` false:
/// confirmation with the tasks and versions of the preview (an empty list if no task hangs on the milestone).
nonisolated struct CampMilestoneMoveBody: Encodable, Sendable {
    let dryRun: Bool
    let date: CampCalendarDay
    let version: Int
    var tasks: [CampVersionRef]?

    enum CodingKeys: String, CodingKey { case dryRun = "trocken", date = "datum", version, tasks = "aufgaben" }
}

nonisolated struct CampMilestoneMove: Decodable, Equatable, Sendable {
    nonisolated struct Milestone: Decodable, Equatable, Identifiable, Sendable {
        let id: UUID
        let version: Int
        let oldDate: Date
        let newDate: Date
        enum CodingKeys: String, CodingKey { case id, version, oldDate = "datumAlt", newDate = "datumNeu" }
    }

    nonisolated struct Task: Decodable, Equatable, Identifiable, Sendable {
        let id: UUID
        let version: Int
        let title: String
        let status: CampTaskStatus
        let oldDue: Date
        let newDue: Date
        enum CodingKeys: String, CodingKey { case id, version, status, title = "titel", oldDue = "fristAlt", newDue = "fristNeu" }
    }

    let dryRun: Bool
    let milestone: Milestone
    /// The tasks whose deadline moves with the milestone.
    let tasks: [Task]

    enum CodingKeys: String, CodingKey { case dryRun = "trocken", milestone = "meilenstein", tasks = "aufgaben" }

    /// The tasks with their versions, as the confirmation needs them.
    var taskRefs: [CampVersionRef] { tasks.map { CampVersionRef(id: $0.id, version: $0.version) } }
}

nonisolated struct CampDayCreate: Encodable, Sendable {
    let date: CampCalendarDay
    var label: String?

    enum CodingKeys: String, CodingKey { case date = "datum", label }
}

nonisolated struct CampDayPatch: Encodable, Sendable {
    let version: Int
    var date: CampCalendarDay?
    var label: CampField<String>?

    enum CodingKeys: String, CodingKey { case version, date = "datum", label }
}

nonisolated struct CampSectionCreate: Encodable, Sendable {
    let name: String
    var time: String?
    var order: Int?

    enum CodingKeys: String, CodingKey { case name, time = "zeit", order = "reihenfolge" }
}

nonisolated struct CampSectionPatch: Encodable, Sendable {
    let version: Int
    var name: String?
    var time: CampField<String>?
    var order: Int?

    enum CodingKeys: String, CodingKey { case version, name, time = "zeit", order = "reihenfolge" }
}

// MARK: Private to-dos

/// A to-do only the person sees. No version: the server does not check one.
nonisolated struct CampTodo: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let text: String
    let done: Bool
    let order: Int

    enum CodingKeys: String, CodingKey { case id, text, done = "erledigt", order = "reihenfolge" }
}

nonisolated struct CampTodoList: Decodable, Equatable, Sendable {
    let todos: [CampTodo]
}

nonisolated struct CampTodoCreate: Encodable, Sendable {
    let text: String
    var order: Int?

    enum CodingKeys: String, CodingKey { case text, order = "reihenfolge" }
}

nonisolated struct CampTodoPatch: Encodable, Sendable {
    var text: String?
    var done: Bool?
    var order: Int?

    enum CodingKeys: String, CodingKey { case text, done = "erledigt", order = "reihenfolge" }
}

// MARK: Templates

nonisolated enum CampTemplateKind: String, Decodable, Sendable {
    case tasks = "aufgaben"
    case packingList = "packliste"
}

/// A template to choose for `applyCampTemplate` (`GET …/vorlagen`): never the content.
nonisolated struct CampTemplateEntry: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let kind: CampTemplateKind
    let name: String
    /// Number of tasks or packing list items.
    let count: Int

    enum CodingKeys: String, CodingKey { case id, kind = "art", name, count = "anzahl" }
}

nonisolated struct CampTemplateList: Decodable, Sendable {
    let templates: [CampTemplateEntry]

    enum CodingKeys: String, CodingKey { case templates = "vorlagen" }
}

/// `POST …/vorlagen/{id}/anwenden`. With `dryRun` the list shows what would be created; without, what was created.
nonisolated struct CampTemplateApplication: Decodable, Equatable, Sendable {
    nonisolated struct Task: Decodable, Equatable, Sendable {
        let title: String
        let due: Date?
        enum CodingKeys: String, CodingKey { case title = "titel", due = "frist" }
    }

    nonisolated struct PackingItem: Decodable, Equatable, Sendable {
        let section: String
        let text: String
        let campLeaderOnly: Bool
        enum CodingKeys: String, CodingKey { case section = "abschnitt", text, campLeaderOnly = "nurLagerleitung" }
    }

    let dryRun: Bool
    let kind: CampTemplateKind
    /// Only with a task template.
    let tasks: [Task]?
    /// Only with a packing list template.
    let items: [PackingItem]?

    enum CodingKeys: String, CodingKey { case dryRun = "trocken", kind = "art", tasks = "aufgaben", items = "punkte" }
}

// MARK: Start of the camp lead

nonisolated struct CampStart: Decodable, Equatable, Sendable {
    nonisolated struct Countdown: Decodable, Equatable, Sendable {
        let from: Date
        let to: Date
        /// Negative once the camp has begun or ended.
        let daysUntilStart: Int
        let daysUntilEnd: Int

        enum CodingKeys: String, CodingKey { case from = "von", to = "bis", daysUntilStart = "tageBisBeginn", daysUntilEnd = "tageBisEnde" }
    }

    nonisolated struct TaskProgress: Decodable, Equatable, Sendable {
        let total: Int
        let done: Int
        let overdue: Int

        enum CodingKeys: String, CodingKey { case total = "gesamt", done = "erledigt", overdue = "ueberfaellig" }
    }

    nonisolated struct MilestoneProgress: Decodable, Equatable, Sendable {
        let total: Int
        let past: Int
        let next: CampMilestone?

        enum CodingKeys: String, CodingKey { case total = "gesamt", past = "vergangen", next = "naechster" }
    }

    nonisolated struct Progress: Decodable, Equatable, Sendable {
        /// `nil`: the role may not read the tasks.
        let tasks: TaskProgress?
        let milestones: MilestoneProgress?

        enum CodingKeys: String, CodingKey { case tasks = "aufgaben", milestones = "meilensteine" }
    }

    let today: Date
    let countdown: Countdown
    let progress: Progress
    let overdue: [CampTask]?

    enum CodingKeys: String, CodingKey { case today = "heute", countdown, progress = "fortschritt", overdue = "ueberfaellig" }
}

// MARK: Decisions

nonisolated struct CampDecision: Decodable, Equatable, Identifiable, Sendable {
    nonisolated struct Meeting: Decodable, Equatable, Identifiable, Sendable {
        let id: UUID
        let date: Date
        let title: String
        enum CodingKeys: String, CodingKey { case id, date = "datum", title = "titel" }
    }

    let id: UUID
    let title: String
    let decision: String
    let taskId: UUID?
    let meeting: Meeting

    enum CodingKeys: String, CodingKey { case id, title = "titel", decision = "entscheid", taskId = "aufgabeId", meeting = "hoeck" }
}

nonisolated struct CampDecisionPage: Decodable, Equatable, Sendable {
    let decisions: [CampDecision]
    let next: UUID?

    enum CodingKeys: String, CodingKey { case decisions = "entscheide", next = "naechster" }
}
