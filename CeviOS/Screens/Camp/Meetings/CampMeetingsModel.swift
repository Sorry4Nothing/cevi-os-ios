import SwiftUI

/// L11: the meetings (Höcks) of the camp. Leads see all of them; the team sees the team meetings in the short form.
@MainActor @Observable
final class CampMeetingsModel {
    /// A meeting in either shape the server answers.
    struct Row: Equatable, Identifiable {
        let id: UUID
        let version: Int
        let kind: CampMeetingKind?
        let date: Date
        let time: String?
        let title: String
        let place: String?
        let agendaCount: Int?
        let protocolId: UUID?
    }

    /// The fields of the form «Neuer Hoeck».
    struct Draft: Equatable {
        var title = ""
        var kind: CampMeetingKind = .campLeadership
        var date = Date()
        var time = ""
        var place = ""
    }

    let active: ActiveCamp
    @ObservationIgnored var now: () -> Date = { Date() }
    private(set) var phase: CampPhase = .loading
    private(set) var rows: [Row] = []
    private(set) var staleSince: Date?
    private(set) var error: String?
    private(set) var inputError: String?

    init(active: ActiveCamp) { self.active = active }

    var rights: CampCommsRights { CampCommsRights(role: active.role, readOnly: active.isReadOnly) }
    private var today: Date { DateFormats.calendar.startOfDay(for: now()) }
    var upcoming: [Row] { rows.filter { $0.date >= today }.sorted { ($0.date, $0.time ?? "") < ($1.date, $1.time ?? "") } }
    var past: [Row] { rows.filter { $0.date < today }.sorted { ($0.date, $0.time ?? "") > ($1.date, $1.time ?? "") } }
    /// The newest meeting, the template of «Wie der letzte».
    var latest: Row? { rows.max { ($0.date, $0.time ?? "") < ($1.date, $1.time ?? "") } }

    func setPreview(phase: CampPhase, rows: [Row], offline: Bool = false, error: String? = nil) {
        self.phase = phase
        self.rows = rows
        self.error = error
        staleSince = offline ? now() : nil
    }

    func load() async {
        guard let client = active.client, let campId = active.camp?.id else { return }
        do {
            var all: [Row] = []
            var cursor: UUID?
            repeat {
                let page = try await client.campMeetings(campId: campId, after: cursor, limit: 100)
                all += page.meetings.map(Self.row)
                cursor = page.next
            } while cursor != nil && all.count < 1000
            rows = all
            phase = .loaded
            staleSince = nil
            error = nil
        } catch is CancellationError {
        } catch {
            let failure = CampPhase(error: error)
            if rows.isEmpty { phase = failure } else {
                self.error = failure.failureText
                if case .failed(.offline?, _) = failure { staleSince = staleSince ?? now() }
            }
        }
    }

    static func row(_ view: CampMeetingView<CampMeetingSummary>) -> Row {
        switch view {
        case .full(let m): Row(id: m.id, version: m.version, kind: m.kind, date: m.date, time: m.time, title: m.title, place: m.place, agendaCount: m.agendaCount, protocolId: m.protocolId)
        case .team(let m): Row(id: m.id, version: m.version, kind: nil, date: m.date, time: m.time, title: m.title, place: m.place, agendaCount: nil, protocolId: nil)
        }
    }

    /// «Wie der letzte»: the fields of the newest meeting, one week later.
    func draftLikeLatest() -> Draft? {
        guard let latest else { return nil }
        let next = DateFormats.calendar.date(byAdding: .day, value: 7, to: latest.date) ?? latest.date
        return Draft(title: latest.title, kind: latest.kind ?? .campLeadership, date: next, time: latest.time ?? "", place: latest.place ?? "")
    }

    /// `HH:MM` or empty.
    static func isValid(time: String) -> Bool {
        time.isEmpty || time.wholeMatch(of: /([01][0-9]|2[0-3]):[0-5][0-9]/) != nil
    }

    /// Returns true if the meeting was created.
    func create(_ draft: Draft) async -> Bool {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        inputError = nil
        guard rights.editsMeetings, let client = active.client, let campId = active.camp?.id else { return false }
        guard !title.isEmpty else { inputError = String(localized: "Gib dem Hoeck einen Titel."); return false }
        guard Self.isValid(time: draft.time) else { inputError = String(localized: "Die Zeit hat die Form 19:30."); return false }
        let body = CampMeetingCreate(title: title, kind: draft.kind, date: CampCalendarDay(draft.date), time: draft.time.isEmpty ? nil : draft.time,
                                     place: draft.place.isEmpty ? nil : draft.place, guests: nil)
        switch await CampCommsWrite.run({ try await client.createCampMeeting(campId: campId, body) }) {
        case .done: await load(); return true
        case .invalid(let text): inputError = text
        case .failed(let text): inputError = text
        }
        return false
    }

    func delete(_ row: Row) async {
        guard rights.editsMeetings, let client = active.client, let campId = active.camp?.id else { return }
        switch await CampCommsWrite.run(as: CampMeeting.self, { try await client.deleteCampMeeting(campId: campId, meetingId: row.id, version: row.version) }) {
        case .done: rows.removeAll { $0.id == row.id }; error = nil
        case .conflict: error = String(localized: "Jemand hat diesen Hoeck gerade geändert. Die Liste wird neu geladen."); await load()
        case .invalid(let text), .failed(let text): error = text
        }
    }
}
