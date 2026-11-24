import Foundation

nonisolated private func lower(_ id: UUID) -> String { id.uuidString.lowercased() }

extension APIClient {
    // MARK: Mein Kalender

    /// The events of the person in a period (Swiss calendar days, both inclusive, at most 400 days), sorted by start.
    /// `after` is `next` of the previous page; the period stays the same when paging. Only "Mein Kalender": the app never
    /// reads "Alle Termine".
    func calendarEvents(from: Date, to: Date, after: String? = nil, limit: Int = 50) async throws -> CalendarEventPage {
        var query = [
            URLQueryItem(name: "von", value: DateFormats.calendarDayText(from)),
            URLQueryItem(name: "bis", value: DateFormats.calendarDayText(to)),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let after { query.append(URLQueryItem(name: "nach", value: after)) }
        return try await load("GET", "/api/v1/termine/mein", query: query)
    }

    /// 404 if the event does not exist, belongs to another department or is not visible to the person.
    func calendarEvent(id: UUID) async throws -> CalendarEventDetail {
        try await load("GET", "/api/v1/termine/\(lower(id))")
    }

    // MARK: Personal calendar link

    func calendarLinkStatus() async throws -> CalendarLinkStatus {
        try await load("GET", "/api/v1/ich/kalender-link")
    }

    /// Creates a new link; an active one stops working at once. The answer holds the secret, once: the caller shows it
    /// through the share sheet and keeps it nowhere. At most 10 calls of create and revoke together per 10 minutes (429).
    func createCalendarLink() async throws -> CalendarLinkNew {
        try await load("POST", "/api/v1/ich/kalender-link")
    }

    /// Revokes the active link. 204 as well if there was none.
    func revokeCalendarLink() async throws {
        try await send("DELETE", "/api/v1/ich/kalender-link")
    }

    // MARK: Suggestions

    func eventSuggestionOptions() async throws -> EventSuggestionOptions {
        try await load("GET", "/api/v1/termin-vorschlaege/optionen")
    }

    /// The own suggestions, newest first.
    func myEventSuggestions(after: UUID? = nil, limit: Int = 50) async throws -> EventSuggestionPage {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let after { query.append(URLQueryItem(name: "nach", value: lower(after))) }
        return try await load("GET", "/api/v1/termin-vorschlaege/meine", query: query)
    }

    /// 400 with the server text for wrong input, `TERMIN_VERGANGEN` and `TAG_UNBEKANNT`; 409 `VORSCHLAG_LIMIT`; 403 without the right.
    func createEventSuggestion(_ body: EventSuggestionCreate) async throws -> EventSuggestionCreated {
        try await load("POST", "/api/v1/termin-vorschlaege", body: body)
    }

    func eventSuggestion(id: UUID) async throws -> EventSuggestion {
        try await load("GET", "/api/v1/termin-vorschlaege/\(lower(id))")
    }

    /// Only the own suggestion, only while it is open (409 `VORSCHLAG_ENTSCHIEDEN`).
    func withdrawEventSuggestion(id: UUID) async throws {
        try await send("DELETE", "/api/v1/termin-vorschlaege/\(lower(id))")
    }

    // MARK: Rooms

    /// The active rooms of the department by name.
    func rooms(after: String? = nil, limit: Int = 50) async throws -> RoomPage {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let after { query.append(URLQueryItem(name: "nach", value: after)) }
        return try await load("GET", "/api/v1/raeume", query: query)
    }

    /// 409 `RAUM_BELEGT` and `ANFRAGE_LIMIT`; 400 with the server text, also `ZEIT_VERGANGEN` and `ZEIT_ZU_LANG`.
    func requestRoom(roomId: UUID, _ body: RoomRequestCreate) async throws -> RoomRequestState {
        try await load("POST", "/api/v1/raeume/\(lower(roomId))/anfragen", body: body)
    }

    /// The own requests in every state, newest first. A confirmed one is the booking.
    func myRoomRequests(after: UUID? = nil, limit: Int = 50) async throws -> RoomRequestPage {
        try await roomRequestPage("meine", after: after, limit: limit)
    }

    /// Open requests the person decides on (team of the room; without team the department lead), oldest first.
    func openRoomRequests(after: UUID? = nil, limit: Int = 50) async throws -> RoomRequestPage {
        try await roomRequestPage("offen", after: after, limit: limit)
    }

    /// Withdraws an open request or cancels a confirmed booking whose time is not over. Idempotent; 409 `STATUS_UNGUELTIG`.
    func cancelRoomRequest(id: UUID) async throws {
        try await send("DELETE", "/api/v1/raeume/anfragen/\(lower(id))")
    }

    /// 409 `STATUS_UNGUELTIG` and `RAUM_BELEGT`; 403 `EIGENE_ANFRAGE` for the own request.
    func decideRoomRequest(id: UUID, _ decision: RoomDecision) async throws -> RoomRequestState {
        try await load("POST", "/api/v1/raeume/anfragen/\(lower(id))/entscheid", body: decision)
    }

    private func roomRequestPage(_ kind: String, after: UUID?, limit: Int) async throws -> RoomRequestPage {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let after { query.append(URLQueryItem(name: "nach", value: lower(after))) }
        return try await load("GET", "/api/v1/raeume/anfragen/\(kind)", query: query)
    }

    // MARK: Registration for an occasion

    /// The form with the own registrations. 404 if the occasion does not exist or is not visible.
    func eventRegistrationForm(occasionId: UUID) async throws -> EventRegistrationForm {
        try await load("GET", "/api/v1/anlaesse/\(lower(occasionId))")
    }

    /// Registers or changes the answers (idempotent; also registers again after an unregistration).
    /// 400 `ANTWORTEN_UNGUELTIG` (see `EventRules.answerErrors`), 409 `ANMELDUNG_GESCHLOSSEN`.
    func registerForEvent(occasionId: UUID, childId: UUID?, answers: [String: EventAnswerValue]) async throws -> EventRegistration {
        try await load("PUT", "/api/v1/anlaesse/\(lower(occasionId))/anmeldung", body: EventRegistrationBody(childId: childId, answers: answers))
    }

    /// Idempotent. Also closed after the deadline (409 `ANMELDUNG_GESCHLOSSEN`).
    func unregisterFromEvent(occasionId: UUID, childId: UUID?) async throws {
        let query = childId.map { [URLQueryItem(name: "kindId", value: lower($0))] } ?? []
        try await send("DELETE", "/api/v1/anlaesse/\(lower(occasionId))/anmeldung", query: query)
    }
}

/// Error codes and texts of the event routes. For everything not named here the app shows the text of the server (`displayText`).
nonisolated enum EventRules {
    // Room requests
    /// 409: the time overlaps a confirmed booking of the room.
    static let roomBookedCode = "RAUM_BELEGT"
    /// 409: ten open requests already.
    static let requestLimitCode = "ANFRAGE_LIMIT"
    /// 409: the request cannot change in this state (decided, cancelled or over).
    static let invalidStateCode = "STATUS_UNGUELTIG"
    /// 400: the time is not in the future.
    static let timeInPastCode = "ZEIT_VERGANGEN"
    /// 400: longer than 14 days.
    static let timeTooLongCode = "ZEIT_ZU_LANG"
    /// 403: nobody decides on the own request.
    static let ownRequestCode = "EIGENE_ANFRAGE"
    // Suggestions
    static let suggestionInPastCode = "TERMIN_VERGANGEN"
    static let suggestionUnknownTagCode = "TAG_UNBEKANNT"
    static let suggestionLimitCode = "VORSCHLAG_LIMIT"
    static let suggestionDecidedCode = "VORSCHLAG_ENTSCHIEDEN"
    // Registration
    static let registrationClosedCode = "ANMELDUNG_GESCHLOSSEN"
    static let answersInvalidCode = "ANTWORTEN_UNGUELTIG"
    static let childIdRequiredCode = "KIND_ID_PFLICHT"
    static let childIdForbiddenCode = "KIND_ID_VERBOTEN"

    /// Text of a failed room request, a cancellation or a decision. The 409 codes get an own text, the rest (also the 400 of
    /// `ZEIT_VERGANGEN` and `ZEIT_ZU_LANG`) shows what the server says.
    static func roomError(_ error: APIError) -> String {
        guard error.kind == .conflict else { return error.displayText }
        switch error.code {
        case roomBookedCode: return String(localized: "Der Raum ist zu dieser Zeit schon gebucht. Bitte eine andere Zeit wählen.")
        case requestLimitCode: return String(localized: "Du hast schon zehn offene Anfragen. Bitte warte auf einen Entscheid.")
        case invalidStateCode: return String(localized: "Diese Anfrage lässt sich nicht mehr ändern. Sie ist schon entschieden, storniert oder vorbei.")
        default: return error.displayText
        }
    }

    /// Text of a failed suggestion or withdrawal; input errors (400) keep the server text.
    static func suggestionError(_ error: APIError) -> String {
        guard error.kind == .conflict else { return error.displayText }
        switch error.code {
        case suggestionLimitCode: return String(localized: "Du hast schon zehn offene Vorschläge. Bitte warte auf einen Entscheid.")
        case suggestionDecidedCode: return String(localized: "Über diesen Vorschlag ist schon entschieden. Er lässt sich nicht mehr zurückziehen.")
        default: return error.displayText
        }
    }

    /// Text of a failed registration or unregistration.
    static func registrationError(_ error: APIError) -> String {
        error.kind == .conflict && error.code == registrationClosedCode
            ? String(localized: "Die Anmeldung ist geschlossen. Die Frist ist vorbei oder der Anlass ist abgesagt oder vorbei.")
            : error.displayText
    }

    /// The wrong answers of a 400 `ANTWORTEN_UNGUELTIG`, by field key. `nil` for any other error.
    static func answerErrors(_ error: APIError) -> [EventAnswerError]? {
        guard error.kind == .invalidInput, error.code == answersInvalidCode, let body = error.conflictBody else { return nil }
        return try? JSONDecoder.api.decode(EventAnswerErrorBody.self, from: body).errors
    }

    /// Text of one wrong answer (the server sends only the code).
    static func answerErrorText(_ code: String) -> String {
        switch code {
        case "PFLICHT": String(localized: "Diese Angabe ist nötig.")
        case "TYP": String(localized: "Diese Angabe hat die falsche Form.")
        case "OPTION": String(localized: "Bitte eine der Möglichkeiten wählen.")
        case "ZU_LANG": String(localized: "Der Text ist zu lang (höchstens 500 Zeichen).")
        case "STEUERZEICHEN": String(localized: "Der Text darf keine Zeilenumbrüche oder Sonderzeichen enthalten.")
        default: String(localized: "Diese Angabe ist ungültig.")
        }
    }
}
