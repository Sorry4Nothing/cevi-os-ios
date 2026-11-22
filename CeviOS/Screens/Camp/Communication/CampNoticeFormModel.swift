import SwiftUI

/// L17: a new notice, with a poll if there are options.
@MainActor @Observable
final class CampNoticeFormModel {
    let active: ActiveCamp
    @ObservationIgnored var now: () -> Date = { Date() }
    var title = ""
    var text = ""
    /// Empty: for everybody.
    var roles: Set<CampNoticeRole> = []
    var options: [String] = ["", ""]
    var multiple = false
    var important = false
    var pinned = false
    var visibleUntil: Date?
    private(set) var isSaving = false
    /// The server refused the input (400), or the poll is incomplete: the field is named.
    private(set) var inputError: String?
    /// Saving failed; the input stays.
    private(set) var saveError: String?
    private(set) var isDone = false
    /// The notice exists but its poll does not (a retry makes only the poll).
    @ObservationIgnored private var createdNotice: CampNotice?

    init(active: ActiveCamp) { self.active = active }

    var canWrite: Bool { CampCommsRights(role: active.role, readOnly: active.isReadOnly).editsNotices }
    /// Options the person filled in.
    var filledOptions: [String] { options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
    var hasPoll: Bool { !filledOptions.isEmpty }

    func setPreview(inputError: String? = nil, saveError: String? = nil, saving: Bool = false) {
        self.inputError = inputError
        self.saveError = saveError
        isSaving = saving
    }

    func addOption() { if options.count < 10 { options.append("") } }
    func removeOption(at index: Int) { if options.indices.contains(index), options.count > 2 { options.remove(at: index) } }

    /// The poll needs two to ten different options (the server checks again).
    var pollProblem: String? {
        guard hasPoll else { return nil }
        let lowered = Set(filledOptions.map { $0.lowercased() })
        if lowered.count < 2 { return String(localized: "Eine Umfrage braucht mindestens zwei Optionen.") }
        if lowered.count != filledOptions.count { return String(localized: "Jede Option darf nur einmal vorkommen.") }
        return nil
    }

    /// Returns true if the notice (and its poll) is on the board.
    func publish() async -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        inputError = nil
        saveError = nil
        guard canWrite, let client = active.client, let campId = active.camp?.id else { return false }
        guard !trimmed.isEmpty else { inputError = String(localized: "Gib der Mitteilung einen Titel."); return false }
        if let problem = pollProblem { inputError = problem; return false }
        isSaving = true
        defer { isSaving = false }
        if createdNotice == nil {
            var body = CampNoticeCreate(title: trimmed)
            body.text = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
            body.important = important
            body.pinned = pinned
            if let visibleUntil { body.visibleUntil = DateFormats.calendar.date(byAdding: .day, value: 1, to: DateFormats.calendar.startOfDay(for: visibleUntil)) }
            if !roles.isEmpty { body.recipients = CampNoticeTarget(roles: roles.sorted { $0.rawValue < $1.rawValue }) }
            switch await CampCommsWrite.run({ try await client.createCampNotice(campId: campId, body) }) {
            case .done(let notice): createdNotice = notice
            case .invalid(let text): inputError = text; return false
            case .failed(let text): saveError = text; return false
            }
        }
        if hasPoll, let notice = createdNotice {
            let body = CampPollCreate(options: filledOptions, multiple: multiple)
            switch await CampCommsWrite.run({ try await client.createCampPoll(campId: campId, noticeId: notice.id, body) }) {
            case .done: break
            case .invalid(let text): inputError = text; return false
            case .failed(let text): saveError = text; return false
            }
        }
        isDone = true
        return true
    }
}
