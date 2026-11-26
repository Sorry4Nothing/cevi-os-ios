import Foundation

/// What the app hands to the widgets: a redacted snapshot, written by the app, read by the widget extension.
///
/// Privacy (SR-xx data minimisation): the model has NO field for names of children or other people, chat contents,
/// phone numbers or addresses. What does not exist here cannot leak; `WidgetSnapshotTests` pins the field list.
nonisolated struct WidgetSnapshot: Codable, Equatable, Sendable {
    /// Raised when the layout of the file changes; the widget treats other versions as «never opened».
    static let currentVersion = 1

    enum Session: String, Codable, Sendable { case signedIn, signedOut }
    enum Status: String, Codable, Sendable { case ok, offline, failed }

    var version = WidgetSnapshot.currentVersion
    var session: Session
    /// Last successful refresh («Stand»).
    var updatedAt: Date
    /// The last refresh had no network; the data is from `updatedAt`.
    var status: Status = .ok
    /// The app lock is on: the widgets show only the redacted form (also with an unlocked device).
    var hidesContent = false
    var units: [WidgetUnit] = []
    var events: [WidgetEvent] = []
    var camps: [WidgetCamp] = []
    var chat: WidgetChat?

    /// Marker without any data (after sign-out, session end, or before sign-in).
    static func signedOut(at date: Date = .now) -> WidgetSnapshot { WidgetSnapshot(session: .signedOut, updatedAt: date) }
}

nonisolated struct WidgetProgram: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let start: Date
    let end: Date?
    let isAllDay: Bool
    /// First line of the meeting point without lines that hold numbers; only W1 on the Home Screen shows it.
    let place: String?
}

/// A unit (Stufe) of the person's children (or of the leader) with the next programs. Only the unit name, no child names.
nonisolated struct WidgetUnit: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    /// `true`: the unit of a child of the parent; `false`: a unit the person leads.
    let isChildUnit: Bool
    /// The next program and up to two after it.
    let programs: [WidgetProgram]
    /// How many children have not answered for the next program (a number, no names).
    let openAnswers: Int
}

nonisolated struct WidgetEvent: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let start: Date
    let isAllDay: Bool
    /// Names of the groups (unit, team); at most two.
    let groups: [String]
}

nonisolated struct WidgetTask: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let due: Date?
    let isOverdue: Bool
}

nonisolated struct WidgetDuty: Codable, Equatable, Sendable {
    /// Name of the duty («Küche»), no person.
    let name: String
    /// «07:00–10:00» or `nil`.
    let time: String?
}

nonisolated struct WidgetCamp: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let from: Date
    let to: Date
    let duty: WidgetDuty?
    /// Titles of the «Wichtig» blocks of today (free text of the camp leaders; shortened).
    let important: [String]
    let todosOpen: Int
    let todosTotal: Int
    let overdueCount: Int
    /// Next open own tasks, at most three, overdue first.
    let tasks: [WidgetTask]
    /// Open tasks due later / own tasks done this week; `nil` where the role may not read them.
    let laterCount: Int?
    let doneThisWeek: Int?
}

nonisolated struct WidgetChat: Codable, Equatable, Sendable {
    /// Total unread messages and the number of chats they sit in. Numbers only.
    let unread: Int
    let chats: Int
}
