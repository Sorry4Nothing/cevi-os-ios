import SwiftUI

/// L19: the bell of the camp (tab «Neu») and the switches per kind (tab «Einstellungen»).
@MainActor @Observable
final class CampNotificationsModel {
    enum Tab: Hashable { case new, settings }

    let active: ActiveCamp
    @ObservationIgnored var now: () -> Date = { Date() }
    var tab: Tab = .new
    private(set) var phase: CampPhase = .loading
    private(set) var entries: [CampNotification] = []
    private(set) var settings: [CampNotificationSetting] = []
    private(set) var settingsPhase: CampPhase = .loading
    private(set) var staleSince: Date?
    private(set) var error: String?

    init(active: ActiveCamp) { self.active = active }

    var unread: [CampNotification] { entries.filter { !$0.isRead } }
    var read: [CampNotification] { entries.filter(\.isRead) }

    func setPreview(phase: CampPhase, entries: [CampNotification], settings: [CampNotificationSetting] = [], offline: Bool = false, error: String? = nil) {
        self.phase = phase
        self.entries = entries
        self.settings = settings
        settingsPhase = .loaded
        self.error = error
        staleSince = offline ? now() : nil
    }

    func load() async {
        guard let client = active.client, let campId = active.camp?.id else { return }
        do {
            var all: [CampNotification] = []
            var cursor: UUID?
            repeat {
                let page = try await client.campNotifications(campId: campId, after: cursor, limit: 100)
                all += page.entries
                cursor = page.next
            } while cursor != nil && all.count < 500
            entries = all
            phase = .loaded
            staleSince = nil
            error = nil
        } catch is CancellationError {
        } catch {
            let failure = CampPhase(error: error)
            if entries.isEmpty { phase = failure } else {
                self.error = failure.failureText
                if case .failed(.offline?, _) = failure { staleSince = staleSince ?? now() }
            }
        }
    }

    func loadSettings() async {
        guard let client = active.client else { return }
        do {
            settings = try await client.campNotificationSettings().kinds
            settingsPhase = .loaded
        } catch is CancellationError {
        } catch {
            if settings.isEmpty { settingsPhase = CampPhase(error: error) } else { self.error = CampPhase(error: error).failureText }
        }
    }

    // MARK: Text

    /// Rows carry kind, object and time, no text and no names: the text comes from the kind.
    static func title(_ kind: CampNotificationKind) -> String {
        switch kind {
        case .taskAssigned: String(localized: "Zuteilung")
        case .taskChanged: String(localized: "Aufgabe geändert")
        case .mention: String(localized: "Erwähnung")
        case .deadline: String(localized: "Frist")
        case .importantNotice: String(localized: "Mitteilung")
        case .feedbackReply: String(localized: "Antwort auf Feedback")
        case .shiftSwapRequest, .shiftSwapDecision: String(localized: "Diensttausch")
        case .attendanceRequest: String(localized: "Anwesenheit")
        case .addressBookCleanup: String(localized: "Adressbuch")
        case .unknown: String(localized: "Neuigkeit")
        }
    }

    static func message(_ kind: CampNotificationKind) -> String {
        switch kind {
        case .taskAssigned: String(localized: "Dir wurde eine Aufgabe zugeteilt.")
        case .taskChanged: String(localized: "Eine Aufgabe von dir wurde geändert.")
        case .mention: String(localized: "Jemand hat dich erwähnt.")
        case .deadline: String(localized: "Eine Aufgabe von dir ist bald fällig.")
        case .importantNotice: String(localized: "Es gibt eine wichtige Mitteilung auf der Pinnwand.")
        case .feedbackReply: String(localized: "Die Lagerleitung hat geantwortet.")
        case .shiftSwapRequest: String(localized: "Jemand möchte einen Dienst mit dir tauschen.")
        case .shiftSwapDecision: String(localized: "Ein Diensttausch wurde entschieden.")
        case .attendanceRequest: String(localized: "Eine Anfrage zur Anwesenheit wartet.")
        case .addressBookCleanup: String(localized: "Das Adressbuch wird bald aufgeräumt.")
        case .unknown: String(localized: "Es gibt etwas Neues im Lager.")
        }
    }

    static func symbol(_ kind: CampNotificationKind) -> String {
        switch kind {
        case .taskAssigned: "person.crop.circle"
        case .taskChanged: "pencil.circle"
        case .mention: "bubble.left"
        case .deadline: "clock"
        case .importantNotice: "megaphone"
        case .feedbackReply: "tray"
        case .shiftSwapRequest, .shiftSwapDecision: "arrow.left.arrow.right"
        case .attendanceRequest: "calendar.badge.checkmark"
        case .addressBookCleanup: "book.closed"
        case .unknown: "bell"
        }
    }

    /// «vor 10 Min.», «gestern».
    func when(_ date: Date) -> String { date.formatted(.relative(presentation: .named).locale(Locale(identifier: "de_CH"))) }

    // MARK: Actions

    func markRead(_ notification: CampNotification) async { await mark([notification.id]) }

    func markAllRead() async { await mark(nil) }

    private func mark(_ ids: [UUID]?) async {
        guard let client = active.client, let campId = active.camp?.id else { return }
        switch await CampCommsWrite.run({ try await client.markCampNotificationsRead(campId: campId, ids: ids) }) {
        case .done: error = nil; await load()
        case .invalid(let text), .failed(let text): error = text
        }
    }

    /// The switch shows at once and goes back if the server refuses.
    func set(_ kind: CampNotificationKind, enabled: Bool) async {
        guard let index = settings.firstIndex(where: { $0.kind == kind }), let client = active.client else { return }
        settings[index].enabled = enabled
        switch await CampCommsWrite.run({ try await client.setCampNotificationSettings([CampNotificationSetting(kind: kind, enabled: enabled)]) }) {
        case .done: error = nil
        case .invalid(let text), .failed(let text):
            if let back = settings.firstIndex(where: { $0.kind == kind }) { settings[back].enabled = !enabled }
            error = text
        }
    }
}
