import Foundation

extension APIClient {
    func campPath(_ id: UUID) -> String { "/api/v1/lager/\(id.uuidString.lowercased())" }

    /// The camps of the person (only camps where the person is a member).
    func camps() async throws -> [CampListEntry] {
        let list: CampList = try await load("GET", "/api/v1/lager")
        return list.camps
    }

    func camp(id: UUID) async throws -> CampDetail {
        try await load("GET", campPath(id))
    }

    /// Only the camp lead may read the matrix (403 for the other roles).
    func campRights(campId: UUID) async throws -> CampRights {
        try await load("GET", campPath(campId) + "/rechte")
    }

    /// Newest first; `after` is the cursor `next` of the previous page.
    func campNotifications(campId: UUID, after: UUID? = nil, limit: Int = 50) async throws -> CampNotificationPage {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let after { query.append(URLQueryItem(name: "nach", value: after.uuidString.lowercased())) }
        return try await load("GET", campPath(campId) + "/benachrichtigungen", query: query)
    }

    func campUnreadCount(campId: UUID) async throws -> Int {
        let unread: CampUnreadCount = try await load("GET", campPath(campId) + "/benachrichtigungen/ungelesen")
        return unread.count
    }

    /// `ids` `nil`: all unread entries of the person in this camp.
    func markCampNotificationsRead(campId: UUID, ids: [UUID]? = nil) async throws {
        try await send("POST", campPath(campId) + "/benachrichtigungen/gelesen", body: CampMarkReadBody(ids: ids))
    }

    /// In which camp the object of a push lies. 404 if the person was not notified or is no member any more.
    func resolveCampPush(type: CampPushType, objectId: UUID) async throws -> CampPushResolution {
        try await load("GET", "/api/v1/lager/aufloesen/\(type.rawValue)/\(objectId.uuidString.lowercased())")
    }

    /// Where the change feed stands now (no `seit`).
    func campFeedState(campId: UUID) async throws -> CampFeedState {
        try await load("GET", campPath(campId) + "/aenderungen")
    }

    /// Changes after sequence number `since` (exclusive). 410 means the feed no longer reaches back: `.reload`.
    func campChanges(campId: UUID, since: Int, limit: Int = 100) async throws -> CampChangesResult {
        let query = [URLQueryItem(name: "seit", value: String(since)), URLQueryItem(name: "limit", value: String(limit))]
        do {
            return .page(try await load("GET", campPath(campId) + "/aenderungen", query: query))
        } catch let error as APIError where error.kind == .gone {
            return .reload
        }
    }
}

/// Texts for a camp that is read-only or an action the server refuses, and the error codes of the camp routes.
nonisolated enum CampRules {
    static let closedCode = "LAGER_GESCHLOSSEN"
    static let versionConflictCode = "VERSION_KONFLIKT"
    /// Maintenance: the camp module answers 503, with this code if the server names it.
    static let maintenanceCode = "WARTUNG"
    /// Codes of an operation answered `abgelehnt` by `POST …/aenderungen`.
    static let rejectionCodes = ["OPERATION_UNBEKANNT", "UNGUELTIGE_EINGABE", "KEINE_BERECHTIGUNG", "NICHT_GEFUNDEN", "KONFLIKT"]
    /// 429 of the event stream (header `Retry-After`).
    static let tooManyConnectionsCode = "ZU_VIELE_VERBINDUNGEN"
    /// The preview of a milestone move is out of date: the app asks for a new preview.
    static let stalePreviewCode = "VORSCHAU_VERALTET"
    static let portfolioCodeTakenCode = "KUERZEL_VERGEBEN"
    static let portfolioHasChildrenCode = "RESSORT_HAT_UNTERRESSORTS"
    static let portfolioCycleCode = "RESSORT_ZYKLUS"
    static let notAMemberCode = "KEIN_MITGLIED"
    static let limitReachedCode = "LIMIT_ERREICHT"
    static let participantUnknownCode = "TEILNEHMER_UNBEKANNT"
    /// 409 on the own attendance: the fields need a request (see `attendanceBlocked`).
    static let attendanceRequestNeededCode = "ANFRAGE_NOETIG"
    /// 409 on a request: the field can be set directly, or a request for it is already waiting.
    static let noAttendanceRequestNeededCode = "KEINE_ANFRAGE_NOETIG"
    static let attendanceRequestOpenCode = "ANFRAGE_OFFEN"
    /// 409 on a decision: a request was decided before.
    static let alreadyDecidedCode = "BEREITS_ENTSCHIEDEN"
    /// 409 on creating a day page: the day has one already.
    static let dayPageExistsCode = "SEITE_VORHANDEN"
    static let phoneMissingCode = "TELEFON_FEHLT"
    /// 400 on a file link: not a valid `https` address, or the host is not on the list of the department.
    static let linkInvalidCode = "LINK_UNGUELTIG"
    static let linkHostNotAllowedCode = "LINK_HOST_NICHT_ERLAUBT"

    /// Shown for 409 `LAGER_GESCHLOSSEN`; other errors show the server text.
    static func writeError(_ error: APIError) -> String {
        error.code == closedCode ? String(localized: "Das Lager ist abgeschlossen. Es lässt sich nur noch lesen.") : error.displayText
    }

    /// The details of a 409 `VERSION_KONFLIKT` ("my version" is what the person typed, "current" is `current`).
    /// `nil` for any other error. `Row` is the type of the row the request wrote, for example `CampTask`.
    static func versionConflict<Row: Decodable & Sendable>(_ error: APIError, as row: Row.Type) -> CampVersionConflict<Row>? {
        guard error.kind == .conflict, error.code == versionConflictCode, let body = error.conflictBody else { return nil }
        return try? JSONDecoder.api.decode(CampVersionConflict<Row>.self, from: body)
    }

    /// The blocked fields of a 409 `ANFRAGE_NOETIG`: nothing was written, the app sends a request for these fields instead.
    /// `nil` for any other error.
    static func attendanceBlocked(_ error: APIError) -> [CampAttendanceBlocked]? {
        guard error.kind == .conflict, error.code == attendanceRequestNeededCode, let body = error.conflictBody else { return nil }
        return try? JSONDecoder.api.decode(CampAttendanceBlockedBody.self, from: body).blocked
    }
}
