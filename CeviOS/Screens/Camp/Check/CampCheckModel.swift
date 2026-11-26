import SwiftUI

/// What the role may do in the camp check. The defaults of the rights matrix (`docs/lager.md`): `check.lesen` for the camp leadership,
/// the leadership and read-only members; writing needs `zeitplan.bearbeiten` as well (camp leadership). Without a rights list
/// in the answer the app follows the role; the server decides again.
nonisolated struct CampCheckRights: Equatable, Sendable {
    let role: CampRole?
    /// The camp is completed or archived.
    let readOnly: Bool

    var reads: Bool { role == .campLeader || role == .leader || role == .readOnly }
    var edits: Bool { !readOnly && role == .campLeader }
}

/// L1a: «Sind wir bereit?» with the own points. Writes go out at once; without network they fail visibly
/// («Nochmals versuchen»), nothing is repeated silently.
@MainActor @Observable
final class CampCheckModel: CampRosterModel {
    /// Someone changed the point at the same time (409 `VERSION_KONFLIKT`).
    struct Conflict: Identifiable {
        let id = UUID()
        let current: CampCheckPoint
        let mineTitle: String
        let mineDone: Bool

        var fields: [CampConflictField] {
            [CampConflictField(label: String(localized: "Punkt"), mine: mineTitle, current: current.title),
             CampConflictField(label: String(localized: "Erledigt"), mine: CampCheckModel.yesNo(mineDone), current: CampCheckModel.yesNo(current.done))]
        }
    }

    nonisolated static let maxTitle = 200
    nonisolated static let maxPoints = 100

    var check: CampCheck?
    var points: [CampCheckPoint] = []
    var conflict: Conflict?
    /// The last write failed: «Nochmals versuchen» repeats it on the person's tap.
    private(set) var canRetry = false
    @ObservationIgnored private var retryAction: (@MainActor () async -> Void)?

    var checkRights: CampCheckRights { CampCheckRights(role: active.role, readOnly: active.isReadOnly) }
    var canEdit: Bool { checkRights.edits }
    var canAddPoint: Bool { canEdit && points.count < Self.maxPoints }

    nonisolated static func yesNo(_ value: Bool) -> String { value ? String(localized: "Ja") : String(localized: "Nein") }

    override func load() async {
        guard let client = active.client, let campId = active.camp?.id else { return }
        do {
            async let result = client.campCheck(campId: campId)
            async let own = client.campCheckPoints(campId: campId)
            let (loadedCheck, loadedPoints) = try await (result, own)
            check = loadedCheck
            points = loadedPoints.points.sorted { $0.order < $1.order }
            loaded()
        } catch is CancellationError {
        } catch {
            failLoad(error, hasContent: check != nil)
        }
    }

    // MARK: Writing

    /// «Punkt hinzufügen». `true` when it was written; the sheet then closes.
    func add(title: String) async -> Bool {
        guard canEdit, let (client, campId) = target else { return false }
        guard let text = Self.validTitle(title) else { error = Self.titleError(title); return false }
        guard points.count < Self.maxPoints else { error = String(localized: "Du hast schon 100 eigene Punkte."); return false }
        switch await CampCommsWrite.run({ try await client.createCampCheckPoint(campId: campId, CampCheckPointCreate(title: text)) }) {
        case .done:
            succeeded()
            await load()
            show(Notice(title: String(localized: "Punkt hinzugefügt."), message: nil))
            return true
        case .invalid(let text), .failed(let text):
            failed(text) { [weak self] in _ = await self?.add(title: title) }
            return false
        }
    }

    func toggle(_ point: CampCheckPoint) async {
        await patch(point, title: nil, done: !point.done)
    }

    /// `true` when it was written (or nothing changed); the sheet then closes.
    func rename(_ point: CampCheckPoint, to title: String) async -> Bool {
        guard canEdit else { return false }
        guard let text = Self.validTitle(title) else { error = Self.titleError(title); return false }
        guard text != point.title else { return true }
        return await patch(point, title: text, done: nil)
    }

    func delete(_ point: CampCheckPoint) async {
        guard canEdit, let (client, campId) = target else { return }
        switch await CampCommsWrite.run(as: CampCheckPoint.self, { try await client.deleteCampCheckPoint(campId: campId, pointId: point.id, version: point.version) }) {
        case .done:
            succeeded()
            await load()
            show(Notice(title: String(localized: "Punkt gelöscht."), message: nil))
        case .conflict:
            succeeded()
            error = String(localized: "Jemand hat diesen Punkt gerade geändert. Die Liste wird neu geladen.")
            await load()
        case .invalid(let text), .failed(let text):
            failed(text) { [weak self] in await self?.delete(point) }
        }
    }

    @discardableResult
    private func patch(_ point: CampCheckPoint, title: String?, done: Bool?) async -> Bool {
        guard canEdit, let (client, campId) = target else { return false }
        let body = CampCheckPointPatch(version: point.version, title: title, done: done)
        switch await CampCommsWrite.run(as: CampCheckPoint.self, { try await client.updateCampCheckPoint(campId: campId, pointId: point.id, body) }) {
        case .done:
            succeeded()
            await load()
            return true
        case .conflict(let current):
            succeeded()
            conflict = Conflict(current: current, mineTitle: title ?? point.title, mineDone: done ?? point.done)
            return false
        case .invalid(let text), .failed(let text):
            failed(text) { [weak self] in await self?.patch(point, title: title, done: done) }
            return false
        }
    }

    /// U7: «Meine behalten» sends the same change on the version the server holds now; «Aktuelle übernehmen» drops it.
    func resolve(_ choice: CampConflictChoice) async {
        guard let pending = conflict else { return }
        conflict = nil
        switch choice {
        case .keepCurrent:
            await load()
        case .keepMine, .merge:
            await patch(pending.current, title: pending.mineTitle, done: pending.mineDone)
        }
    }

    #if DEBUG
    /// Only for previews: shows the retry button.
    func simulateFailure() { canRetry = true }
    #endif

    /// The tap on «Nochmals versuchen».
    func retry() async {
        guard let action = retryAction else { return }
        retryAction = nil
        canRetry = false
        await action()
    }

    private var target: (APIClient, UUID)? {
        guard let client = active.client, let campId = active.camp?.id else { return nil }
        return (client, campId)
    }

    private func succeeded() {
        error = nil
        retryAction = nil
        canRetry = false
    }

    private func failed(_ text: String, retry: @escaping @MainActor () async -> Void) {
        error = text
        retryAction = retry
        canRetry = true
    }

    // MARK: Texts

    /// The trimmed title if it has 1 to 200 characters.
    nonisolated static func validTitle(_ title: String) -> String? {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return (1...maxTitle).contains(text.count) ? text : nil
    }

    nonisolated static func titleError(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? String(localized: "Gib einen Punkt ein.")
            : String(localized: "Der Punkt ist zu lang (höchstens 200 Zeichen).")
    }

    nonisolated static func stateName(_ state: CampCheckState) -> String {
        switch state {
        case .ready: String(localized: "Bereit")
        case .notes: String(localized: "Hinweise")
        case .open: String(localized: "Offen")
        }
    }

    nonisolated static func headline(_ state: CampCheckState) -> String {
        switch state {
        case .ready: String(localized: "Das Lager ist bereit.")
        case .notes: String(localized: "Es gibt Hinweise.")
        case .open: String(localized: "Es ist noch etwas offen.")
        }
    }

    /// «Frist 12. Juli» for a dated example; with open tasks «3 offene Aufgaben».
    nonisolated static func detail(_ example: CampCheckExample) -> String? {
        var parts: [String] = []
        if let date = example.date { parts.append(CampCommsText.day(date)) }
        if let tasks = example.openTasks, tasks > 0 { parts.append(tasks == 1 ? String(localized: "1 offene Aufgabe") : String(localized: "\(tasks) offene Aufgaben")) }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
