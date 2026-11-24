import SwiftUI

/// K4 Anlass-Anmeldung: the form of one occasion for the person or one of their children.
@MainActor @Observable
final class EventRegistrationModel {
    enum Phase: Equatable {
        case loading
        case ready
        /// Closed by the deadline, a switch or a cancelled event (`anmeldungOffen` false or 409).
        case closed
        case notFound
        case failed(text: String, isOffline: Bool)
    }

    struct Sent: Equatable {
        let participantName: String
        let rows: [String]
        /// A new registration can be undone; a changed one is not undone, it can be cancelled in the form.
        let canUndo: Bool
        let childId: UUID?
    }

    let occasionId: UUID
    private(set) var phase: Phase = .loading
    private(set) var form: EventRegistrationForm?
    private(set) var fieldErrors: [String: String] = [:]
    private(set) var sent: Sent?
    let action = ActionState()
    private(set) var participantIndex = 0
    var answers: [String: EventAnswerValue] = [:]

    init(occasionId: UUID) { self.occasionId = occasionId }

    var participant: EventParticipant? {
        guard let form, form.participants.indices.contains(participantIndex) else { return nil }
        return form.participants[participantIndex]
    }

    var isRegistered: Bool { participant?.registration?.status == .registered }

    var hasTextField: Bool { form?.fields.contains { $0.kind == .text } ?? false }

    func load(client: APIClient?) async {
        guard let client else { return }
        do {
            let loaded = try await client.eventRegistrationForm(occasionId: occasionId)
            form = loaded
            phase = loaded.isOpen ? .ready : .closed
            if participantIndex >= loaded.participants.count { participantIndex = 0 }
            prefill()
        } catch is CancellationError {
        } catch let error as APIError {
            phase = error.kind == .notFound ? .notFound : .failed(text: error.displayText, isOffline: error.kind == .network)
        } catch {
            phase = .failed(text: APIError.network.displayText, isOffline: true)
        }
    }

    private func prefill() {
        answers = participant?.registration?.status == .registered ? (participant?.registration?.answers ?? [:]) : [:]
        fieldErrors = [:]
    }

    func selectParticipant(_ index: Int) {
        guard index != participantIndex else { return }
        participantIndex = index
        prefill()
    }

    func set(_ value: EventAnswerValue?, for field: EventField) {
        answers[field.key] = value
        fieldErrors[field.key] = nil
    }

    /// Required fields and values the server would refuse. Maps the field key to the text below the field.
    nonisolated static func validate(fields: [EventField], answers: [String: EventAnswerValue]) -> [String: String] {
        var errors: [String: String] = [:]
        for field in fields {
            switch (field.kind, answers[field.key]) {
            case (.text, .text(let text)?):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty, field.isRequired { errors[field.key] = EventRules.answerErrorText("PFLICHT") }
                if trimmed.count > 500 { errors[field.key] = EventRules.answerErrorText("ZU_LANG") }
            case (.choice, .text(let value)?):
                if !field.options.contains(value) { errors[field.key] = EventRules.answerErrorText("OPTION") }
            case (.yesNo, .bool?):
                break
            case (.unknown, _):
                break
            case (_, nil):
                if field.isRequired { errors[field.key] = EventRules.answerErrorText("PFLICHT") }
            default:
                errors[field.key] = EventRules.answerErrorText("TYP")
            }
        }
        return errors
    }

    func send(client: APIClient?) async {
        guard let form, let participant, let client else { return }
        // Only answers of fields that exist; empty optional text is left out.
        var clean: [String: EventAnswerValue] = [:]
        for field in form.fields {
            guard let value = answers[field.key] else { continue }
            if case .text(let text) = value {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { clean[field.key] = .text(trimmed) }
            } else {
                clean[field.key] = value
            }
        }
        fieldErrors = Self.validate(fields: form.fields, answers: clean)
        guard fieldErrors.isEmpty else { return }
        let wasRegistered = isRegistered
        var saved: EventRegistration?
        await action.perform(message: explain) {
            saved = try await client.registerForEvent(occasionId: occasionId, childId: participant.childId, answers: clean)
        }
        guard saved != nil else { return }
        sent = Sent(participantName: participant.name, rows: summary(form.fields, clean), canUndo: !wasRegistered, childId: participant.childId)
        AccessibilityNotification.Announcement(String(localized: "Angemeldet.")).post()
    }

    private func explain(_ error: APIError) -> String {
        if let list = EventRules.answerErrors(error) {
            for entry in list { fieldErrors[entry.key] = EventRules.answerErrorText(entry.code) }
            return String(localized: "Prüfe deine Eingaben.")
        }
        if error.kind == .conflict, error.code == EventRules.registrationClosedCode { phase = .closed }
        return EventRules.registrationError(error)
    }

    private func summary(_ fields: [EventField], _ values: [String: EventAnswerValue]) -> [String] {
        fields.compactMap { field in
            guard let value = values[field.key] else { return nil }
            switch value {
            case .bool(let flag): return "\(field.label): \(flag ? String(localized: "Ja") : String(localized: "Nein"))"
            case .text(let text): return "\(field.label): \(text)"
            }
        }
    }

    /// «Rückgängig» after a new registration, and «Abmelden» in the form.
    func unregister(client: APIClient?) async {
        guard let participant, let client else { return }
        await action.perform(message: EventRules.registrationError) {
            try await client.unregisterFromEvent(occasionId: occasionId, childId: participant.childId)
        }
        guard action.error == nil else { return }
        // The inputs stay: «Rückgängig» brings the form back as it was.
        let kept = answers
        sent = nil
        await load(client: client)
        answers = kept
        AccessibilityNotification.Announcement(String(localized: "Abgemeldet.")).post()
    }
}

/// Dates of an occasion for the header: «17. bis 24. Juli 2027, Anmeldeschluss 31. März».
nonisolated extension EventRegistrationForm {
    var headerLine: String {
        let locale = Locale(identifier: "de_CH")
        func text(_ date: Date, _ style: Date.FormatStyle) -> String { date.formatted(style) }
        let withYear = Date.FormatStyle(locale: locale, timeZone: DateFormats.timeZone).day().month(.wide).year()
        let withoutYear = Date.FormatStyle(locale: locale, timeZone: DateFormats.timeZone).day().month(.wide)
        let first = dayFrom ?? start
        let last = dayTo ?? end.map { $0.addingTimeInterval(-1) } ?? first
        var parts: [String] = []
        if let first {
            if let last, !DateFormats.calendar.isDate(first, inSameDayAs: last) {
                parts.append(String(localized: "\(text(first, withoutYear)) bis \(text(last, withYear))"))
            } else {
                parts.append(text(first, withYear))
            }
        }
        if let deadline {
            parts.append(isOpen ? String(localized: "Anmeldeschluss \(text(deadline, withoutYear))")
                : String(localized: "Anmeldeschluss war am \(text(deadline, withoutYear))"))
        }
        return parts.joined(separator: ", ")
    }
}
