import SwiftUI

/// L13: the protocol of a meeting. The API has a row with a link to a file, not sections of text (`docs/lager.md`): the screen shows
/// the row (title, kind, date), the attendees, the agenda with its texts and decisions, and the resolutions (Beschlüsse).
@MainActor @Observable
final class CampProtocolModel {
    /// Someone else changed the protocol row (409 `VERSION_KONFLIKT`).
    struct Conflict: Identifiable {
        let id = UUID()
        let current: CampProtocol
        let mine: Draft

        var fields: [CampConflictField] {
            [CampConflictField(label: String(localized: "Titel"), mine: mine.title, current: current.title),
             CampConflictField(label: String(localized: "Art"), mine: CampProtocolModel.kindName(mine.kind), current: CampProtocolModel.kindName(current.kind)),
             CampConflictField(label: String(localized: "Datum"), mine: CampCommsText.day(mine.date), current: CampCommsText.day(current.date))]
        }
    }

    struct Draft: Equatable {
        var title: String
        var kind: CampProtocolKind
        var date: Date
    }

    let active: ActiveCamp
    let meetingId: UUID
    @ObservationIgnored var now: () -> Date = { Date() }
    private(set) var phase: CampPhase = .loading
    private(set) var meeting: CampMeeting?
    private(set) var minutes: CampProtocol?
    private(set) var resolutions: [CampResolution] = []
    private(set) var staleSince: Date?
    private(set) var error: String?
    /// The last save failed; the input is still in `draft`.
    private(set) var saveFailed = false
    private(set) var savedNotice: String?
    var draft = Draft(title: "", kind: .meeting, date: Date())
    var conflict: Conflict?

    init(active: ActiveCamp, meetingId: UUID) {
        self.active = active
        self.meetingId = meetingId
    }

    var rights: CampCommsRights { CampCommsRights(role: active.role, readOnly: active.isReadOnly) }
    var canEdit: Bool { rights.editsProtocols }
    var attendees: [CampPersonRef] { meeting?.attendees ?? [] }
    var agenda: [CampAgendaItem] { (meeting?.agenda ?? []).sorted { $0.order < $1.order } }
    var isDirty: Bool { minutes.map { draft != Self.draft(of: $0) } ?? false }

    static func kindName(_ kind: CampProtocolKind) -> String {
        switch kind {
        case .meeting: String(localized: "Sitzung")
        case .note: String(localized: "Notiz")
        case .contact: String(localized: "Kontakt")
        case .idea: String(localized: "Idee")
        }
    }

    static func draft(of row: CampProtocol) -> Draft { Draft(title: row.title, kind: row.kind, date: row.date) }

    func setPreview(phase: CampPhase, meeting: CampMeeting?, minutes: CampProtocol?, resolutions: [CampResolution], offline: Bool = false,
                    error: String? = nil, saveFailed: Bool = false) {
        self.phase = phase
        self.meeting = meeting
        self.minutes = minutes
        self.resolutions = resolutions
        self.error = error
        self.saveFailed = saveFailed
        staleSince = offline ? now() : nil
        if let minutes { draft = Self.draft(of: minutes) }
    }

    func load() async {
        guard rights.readsProtocols, let client = active.client, let campId = active.camp?.id else {
            if !rights.readsProtocols { phase = .failed(state: .noAccess, text: "") }
            return
        }
        do {
            guard case .full(let full) = try await client.campMeeting(campId: campId, meetingId: meetingId) else {
                phase = .failed(state: .noAccess, text: "")
                return
            }
            meeting = full
            if let id = full.protocolId {
                let row = try await client.campProtocol(campId: campId, protocolId: id)
                if minutes?.version != row.version || !isDirty { draft = Self.draft(of: row) }
                minutes = row
            }
            resolutions = try await client.campResolutions(campId: campId, meetingId: meetingId).resolutions
            phase = .loaded
            staleSince = nil
            error = nil
        } catch is CancellationError {
        } catch {
            let failure = CampPhase(error: error)
            if meeting == nil { phase = failure } else {
                self.error = failure.failureText
                if case .failed(.offline?, _) = failure { staleSince = staleSince ?? now() }
            }
        }
    }

    /// «Speichern»: the row with its title, kind and date.
    func save() async {
        guard canEdit, let minutes, isDirty, let client = active.client, let campId = active.camp?.id else { return }
        let mine = draft
        let outcome = await send(mine, version: minutes.version, client: client, campId: campId, id: minutes.id)
        switch outcome {
        case .done(let row):
            self.minutes = row
            draft = Self.draft(of: row)
            saveFailed = false
            error = nil
            savedNotice = String(localized: "Gespeichert.")
            AccessibilityNotification.Announcement(String(localized: "Gespeichert.")).post()
        case .conflict(let current): conflict = Conflict(current: current, mine: mine); saveFailed = false
        case .invalid(let text): error = text; saveFailed = true
        case .failed(let text): error = text; saveFailed = true
        }
    }

    private func send(_ mine: Draft, version: Int, client: APIClient, campId: UUID, id: UUID) async -> CampWriteOutcome<CampProtocol, CampProtocol> {
        var patch = CampProtocolPatch(version: version)
        patch.title = mine.title.trimmingCharacters(in: .whitespacesAndNewlines)
        patch.kind = mine.kind
        patch.date = CampCalendarDay(mine.date)
        return await CampCommsWrite.run(as: CampProtocol.self) { try await client.updateCampProtocol(campId: campId, protocolId: id, patch) }
    }

    /// U7: «Meine behalten» sends the same change on the version the server holds now; «Aktuelle übernehmen» drops the own input.
    func resolve(_ choice: CampConflictChoice) async {
        guard let pending = conflict, let client = active.client, let campId = active.camp?.id else { return }
        conflict = nil
        switch choice {
        case .keepCurrent:
            minutes = pending.current
            draft = Self.draft(of: pending.current)
        case .keepMine, .merge:
            switch await send(pending.mine, version: pending.current.version, client: client, campId: campId, id: pending.current.id) {
            case .done(let row): minutes = row; draft = Self.draft(of: row); error = nil
            case .conflict(let current): conflict = Conflict(current: current, mine: pending.mine)
            case .invalid(let text), .failed(let text): error = text; saveFailed = true
            }
        }
    }

    // MARK: Resolutions

    /// Returns true if saved. `resolution` `nil` adds a new one for this meeting.
    func saveResolution(_ text: String, resolution: CampResolution?) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canEdit, !trimmed.isEmpty, let client = active.client, let campId = active.camp?.id else { return false }
        if let resolution {
            var patch = CampResolutionPatch(version: resolution.version)
            patch.text = trimmed
            switch await CampCommsWrite.run(as: CampResolution.self, { try await client.updateCampResolution(campId: campId, resolutionId: resolution.id, patch) }) {
            case .done: await load(); return true
            case .conflict: error = String(localized: "Jemand hat diesen Beschluss gerade geändert. Er wird neu geladen."); await load()
            case .invalid(let text), .failed(let text): error = text
            }
        } else {
            let body = CampResolutionCreate(text: trimmed, protocolId: minutes?.id, meetingId: meetingId)
            switch await CampCommsWrite.run({ try await client.createCampResolution(campId: campId, body) }) {
            case .done: await load(); return true
            case .invalid(let text), .failed(let text): error = text
            }
        }
        return false
    }

    func deleteResolution(_ resolution: CampResolution) async {
        guard canEdit, let client = active.client, let campId = active.camp?.id else { return }
        switch await CampCommsWrite.run(as: CampResolution.self, { try await client.deleteCampResolution(campId: campId, resolutionId: resolution.id, version: resolution.version) }) {
        case .done: await load()
        case .conflict: error = String(localized: "Jemand hat diesen Beschluss gerade geändert. Er wird neu geladen."); await load()
        case .invalid(let text), .failed(let text): error = text
        }
    }
}
