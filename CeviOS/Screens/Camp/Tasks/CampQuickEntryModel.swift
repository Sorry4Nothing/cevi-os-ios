import Foundation

/// L8 quick entry and L10 duplicate hint. Step 1 only suggests; the person confirms, then the tasks are created.
@MainActor @Observable
final class CampQuickEntryModel {
    /// A similar open task, found before creating.
    struct Duplicate: Equatable {
        let title: String
        let existing: CampDuplicateTask
    }

    let active: ActiveCamp
    var text = ""
    private(set) var suggestions: [CampTaskSuggestion] = []
    /// Candidate the person picked for an ambiguous or unknown name, per line.
    private(set) var personChoice: [Int: UUID] = [:]
    /// Portfolio the person confirmed, per line. A proposal alone is never applied.
    private(set) var portfolioChoice: [Int: UUID] = [:]
    private(set) var duplicate: Duplicate?
    private(set) var isSaving = false
    private(set) var error: String?
    private(set) var created: [CampTask] = []
    private(set) var isDone = false
    @ObservationIgnored private var queue: [Int] = []

    init(active: ActiveCamp) { self.active = active }

    var canCreate: Bool { CampTaskRights(role: active.role, readOnly: active.isReadOnly, personId: nil).canCreate }
    var canSubmit: Bool { canCreate && !isSaving && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !blocked }
    /// A line without a usable title or with an invalid date cannot be created.
    var blocked: Bool { suggestions.contains { $0.title.isEmpty || !$0.hints.isEmpty } }

    /// A calm sentence for the first hint of a line (L8 Eingabefehler).
    func hint(for suggestion: CampTaskSuggestion) -> String? {
        if suggestion.hints.contains(.titleMissing) { return String(localized: "Gib der Aufgabe einen Titel.") }
        if suggestion.hints.contains(.titleTooLong) { return String(localized: "Der Titel ist zu lang. Kürze ihn.") }
        if suggestion.hints.contains(.invalidDate) { return String(localized: "Das Datum ist ungültig.") }
        if let person = suggestion.person, person.status != .found, personChoice[index(of: suggestion)] == nil {
            let name = person.text
            if let first = person.candidates.first, let label = CampTaskText.personName(name: first.name, ceviName: first.ceviName) {
                return String(localized: "Ich habe @\(name) nicht gefunden. Meintest du @\(label)?")
            }
            return String(localized: "Ich habe @\(name) nicht gefunden. Die Aufgabe bleibt ohne Verantwortliche.")
        }
        return nil
    }

    func index(of suggestion: CampTaskSuggestion) -> Int { suggestions.firstIndex(of: suggestion) ?? 0 }

    func choosePerson(_ id: UUID, line: Int) { personChoice[line] = id }
    func togglePortfolio(_ id: UUID, line: Int) { portfolioChoice[line] = portfolioChoice[line] == id ? nil : id }

    func setPreview(suggestions: [CampTaskSuggestion], duplicate: Duplicate? = nil, saving: Bool = false, error: String? = nil) {
        self.suggestions = suggestions
        self.duplicate = duplicate
        isSaving = saving
        self.error = error
    }

    /// Step 1. Nothing is saved. An empty text clears the suggestions.
    func suggest() async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let client = active.client, let campId = active.camp?.id, !trimmed.isEmpty else { suggestions = []; return }
        do {
            let result = try await client.suggestCampTasks(campId: campId, text: trimmed)
            suggestions = result
            // Lines moved or changed: confirmations of the old lines do not carry over.
            personChoice = [:]
            portfolioChoice = [:]
            error = nil
        } catch is CancellationError {
        } catch let failure as APIError {
            error = failure.kind == .network ? String(localized: "Ohne Netz. Die Vorschläge kommen, sobald du wieder Netz hast.") : failure.displayText
        } catch { self.error = APIError.network.displayText }
    }

    /// «Erfassen»: goes through the lines; stops at a similar task and waits for the person (L10).
    func submit() async {
        guard canSubmit else { return }
        if suggestions.isEmpty { await suggest() }
        guard !suggestions.isEmpty, !blocked else { return }
        queue = Array(suggestions.indices)
        created = []
        error = nil
        await proceed()
    }

    /// «Beide behalten».
    func keepBoth() async {
        guard duplicate != nil, let line = queue.first else { return }
        duplicate = nil
        _ = await create(line)
        queue.removeFirst()
        await proceed()
    }

    /// «Zusammenführen»: the existing task absorbs the new one.
    func merge() async {
        guard let duplicate, let line = queue.first, let client = active.client, let campId = active.camp?.id else { return }
        guard let new = await create(line) else { return }
        self.duplicate = nil
        do {
            let merged = try await BusyState.shared.track {
                try await client.mergeCampTasks(campId: campId, taskId: duplicate.existing.id, version: duplicate.existing.version, withId: new.id, withVersion: new.version)
            }
            created.removeAll { $0.id == new.id }
            created.append(merged)
        } catch let failure as APIError {
            error = String(localized: "Die Aufgabe ist angelegt, aber das Zusammenführen hat nicht geklappt.") + " " + CampRules.writeError(failure)
        } catch { self.error = APIError.network.displayText }
        queue.removeFirst()
        await proceed()
    }

    // MARK: Private

    private func proceed() async {
        guard let client = active.client, let campId = active.camp?.id else { return }
        while let line = queue.first {
            let suggestion = suggestions[line]
            let portfolio = portfolioChoice[line]
            // The duplicate check is a help: if it fails, the task is created all the same.
            if let found = try? await client.campTaskDuplicates(campId: campId, title: suggestion.title, portfolioId: portfolio),
               let existing = found.groups.first?.tasks.first {
                duplicate = Duplicate(title: suggestion.title, existing: existing)
                return
            }
            guard await create(line) != nil else { return }
            queue.removeFirst()
        }
        isDone = error == nil
    }

    private func create(_ line: Int) async -> CampTask? {
        guard let client = active.client, let campId = active.camp?.id else { return nil }
        let suggestion = suggestions[line]
        var body = CampTaskCreate(confirming: suggestion, person: personChoice[line])
        body.portfolioId = portfolioChoice[line]
        isSaving = true
        defer { isSaving = false }
        do {
            let task = try await BusyState.shared.track { try await client.createCampTask(campId: campId, body) }
            created.append(task)
            return task
        } catch let failure as APIError {
            error = CampRules.writeError(failure)
        } catch { self.error = APIError.network.displayText }
        return nil
    }
}
