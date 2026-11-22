import Foundation

/// L2 (camp lead) and L3 (team): countdown, progress and what is meant for the person.
@MainActor @Observable
final class CampStartModel {
    /// A meeting in either shape the server answers.
    struct MeetingInfo: Equatable, Identifiable {
        let id: UUID
        let date: Date
        let time: String?
        let title: String
        let place: String?
    }

    let active: ActiveCamp
    @ObservationIgnored var now: () -> Date = { Date() }
    private(set) var phase: CampPhase = .loading
    private(set) var start: CampStart?
    private(set) var myWeek: CampMyWeek?
    /// The last load failed without network; what is shown is the stand of `loadedAt`.
    private(set) var isOffline = false
    private(set) var loadedAt: Date?

    init(active: ActiveCamp) { self.active = active }

    /// Leads see the start page of the camp lead (L2); everyone else the team's (L3).
    var isLead: Bool { active.role == .campLeader || active.role == .leader }
    var canCreate: Bool { CampTaskRights(role: active.role, readOnly: active.isReadOnly, personId: nil).canCreate }
    var ownTasks: [CampTask] { (myWeek?.tasks ?? []).filter { $0.status != .done } }
    var shifts: [CampOwnShift] { myWeek?.shifts ?? [] }
    var nextMeeting: MeetingInfo? {
        myWeek?.meetings?.compactMap { view -> MeetingInfo? in
            switch view {
            case .full(let m): MeetingInfo(id: m.id, date: m.date, time: m.time, title: m.title, place: m.place)
            case .team(let m): MeetingInfo(id: m.id, date: m.date, time: m.time, title: m.title, place: m.place)
            }
        }.sorted { $0.date < $1.date }.first
    }

    /// Share of done tasks, 0 to 100; `nil` if the role may not read the tasks or there are none.
    var percentDone: Int? {
        guard let tasks = start?.progress.tasks, tasks.total > 0 else { return nil }
        return Int((Double(tasks.done) / Double(tasks.total) * 100).rounded())
    }

    var countdownTitle: String {
        guard let countdown = start?.countdown else { return "" }
        switch (countdown.daysUntilStart, countdown.daysUntilEnd) {
        case (1..., _): return countdown.daysUntilStart == 1 ? String(localized: "Noch 1 Tag bis zum Lager") : String(localized: "Noch \(countdown.daysUntilStart) Tage bis zum Lager")
        case (0, _): return String(localized: "Das Lager beginnt heute")
        case (_, 0...): return String(localized: "Das Lager läuft")
        default: return String(localized: "Das Lager ist vorbei")
        }
    }

    func setPreview(phase: CampPhase, start: CampStart?, myWeek: CampMyWeek? = nil, offline: Bool = false) {
        self.phase = phase
        self.start = start
        self.myWeek = myWeek
        isOffline = offline
        if offline { loadedAt = now() }
    }

    func load() async {
        guard let client = active.client, let campId = active.camp?.id else { return }
        do {
            start = try await client.campStart(campId: campId)
            // «Für dich» is optional: 403 without a readable part, any other failure leaves the page without it.
            myWeek = try? await client.campMyWeek(campId: campId)
            phase = .loaded
            isOffline = false
            loadedAt = now()
        } catch is CancellationError {
        } catch {
            let failure = CampPhase(error: error)
            if start != nil, case .failed(.offline?, _) = failure { isOffline = true } else { phase = failure }
        }
    }
}
