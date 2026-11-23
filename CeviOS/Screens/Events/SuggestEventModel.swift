import SwiftUI

/// K1 Termin vorschlagen: the form, its checks and the result. Kept in memory only.
@MainActor @Observable
final class SuggestEventModel {
    enum Phase: Equatable {
        case loading
        /// `darfVorschlagen` is false.
        case noRight
        case ready
        case failed(text: String, isOffline: Bool)
    }

    struct Errors: Equatable {
        var title: String?
        var tags: String?
        var time: String?

        var isEmpty: Bool { title == nil && tags == nil && time == nil }
    }

    /// What was sent, for the summary after sending.
    struct Sent: Equatable {
        let id: UUID
        let title: String
        let start: Date
        let end: Date
        let place: String?
        let groups: [String]
    }

    private(set) var phase: Phase = .loading
    private(set) var tags: [EventTag] = []
    private(set) var errors = Errors()
    private(set) var sent: Sent?
    let action = ActionState()
    /// Set when sending failed for a reason the fields do not explain (K1 «Fehler beim Speichern»).
    var saveError: String? { action.error }

    var title = ""
    var place = ""
    var details = ""
    var date: Date
    var start: Date
    var end: Date
    var selectedTags: Set<UUID> = []

    init(now: Date = .now) {
        let day = DateFormats.calendar.date(byAdding: .day, value: 1, to: DateFormats.calendar.startOfDay(for: now)) ?? now
        date = day
        start = day.addingTimeInterval(18 * 3600)
        end = day.addingTimeInterval(20 * 3600)
    }

    var summaryText: String? {
        sent.map { EventFormat.range(start: $0.start, end: $0.end) }
    }

    func load(client: APIClient?) async {
        guard let client else { return }
        do {
            let options = try await client.eventSuggestionOptions()
            tags = options.tags
            phase = options.mayPropose ? .ready : .noRight
        } catch is CancellationError {
        } catch let error as APIError {
            phase = error.kind == .forbidden ? .noRight : .failed(text: error.displayText, isOffline: error.kind == .network)
        } catch {
            phase = .failed(text: APIError.network.displayText, isOffline: true)
        }
    }

    func toggle(_ tag: EventTag) {
        if selectedTags.contains(tag.id) { selectedTags.remove(tag.id) } else { selectedTags.insert(tag.id) }
        if errors.tags != nil, !selectedTags.isEmpty { errors.tags = nil }
    }

    /// Fields the server would refuse, found before sending.
    nonisolated static func validate(title: String, tagCount: Int, start: Date, end: Date, now: Date = .now) -> Errors {
        var errors = Errors()
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errors.title = String(localized: "Gib einen Titel ein.") }
        if tagCount == 0 { errors.tags = String(localized: "Wähle mindestens eine Gruppe.") }
        if end <= start {
            errors.time = String(localized: "Das Ende muss nach dem Beginn liegen.")
        } else if start < now {
            errors.time = String(localized: "Der Termin liegt in der Vergangenheit.")
        }
        return errors
    }

    func send(client: APIClient?, now: Date = .now) async {
        let startDate = EventFormat.combine(day: date, time: start)
        let endDate = EventFormat.combine(day: date, time: end)
        errors = Self.validate(title: title, tagCount: selectedTags.count, start: startDate, end: endDate, now: now)
        guard errors.isEmpty, let client else { return }
        let trimmedPlace = place.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = EventSuggestionCreate(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines), time: .timed(start: startDate, end: endDate),
            place: trimmedPlace.isEmpty ? nil : trimmedPlace, details: trimmedDetails.isEmpty ? nil : trimmedDetails,
            note: nil, tagIds: tags.filter { selectedTags.contains($0.id) }.map(\.id)
        )
        let groups = tags.filter { selectedTags.contains($0.id) }.map(\.name)
        var created: EventSuggestionCreated?
        await action.perform(message: explain) { created = try await client.createEventSuggestion(body) }
        guard let created else { return }
        sent = Sent(id: created.id, title: body.title, start: startDate, end: endDate, place: body.place, groups: groups)
        AccessibilityNotification.Announcement(String(localized: "Gesendet. Du erfährst es, sobald die Leitung entschieden hat.")).post()
    }

    /// The server's reasons that belong to a field go there; everything else is the general error.
    private func explain(_ error: APIError) -> String {
        switch (error.kind, error.code) {
        case (.invalidInput, EventRules.suggestionInPastCode):
            errors.time = String(localized: "Der Termin liegt in der Vergangenheit.")
            return String(localized: "Prüfe deine Eingaben.")
        case (.invalidInput, EventRules.suggestionUnknownTagCode):
            errors.tags = String(localized: "Diese Gruppe gibt es nicht mehr. Wähle eine andere.")
            return String(localized: "Prüfe deine Eingaben.")
        case (.invalidInput, _):
            return String(localized: "Prüfe deine Eingaben.")
        default:
            return EventRules.suggestionError(error)
        }
    }

    /// «Rückgängig»: withdraws the suggestion and brings the form back with the inputs.
    func undo(client: APIClient?) async {
        guard let sent, let client else { return }
        await action.perform(message: EventRules.suggestionError) { try await client.withdrawEventSuggestion(id: sent.id) }
        if action.error == nil { self.sent = nil }
    }
}
