import Foundation

extension APIClient {
    private func dayQuery(_ dayIds: [UUID]) -> [URLQueryItem] {
        dayIds.isEmpty ? [] : [URLQueryItem(name: "lagertagIds", value: dayIds.map { $0.uuidString.lowercased() }.joined(separator: ","))]
    }

    // MARK: Matrix (camp leadership)

    /// The whole matrix. Needs the right to read all attendance (403 for the team: it reads `ownCampAttendance`).
    /// `dayIds` (at most 40) limits the days; no entry for a field means open.
    func campAttendance(campId: UUID, dayIds: [UUID] = [], after: UUID? = nil, limit: Int = 1000) async throws -> CampAttendancePage {
        try await load("GET", rowPath(campId, "anwesenheit"), query: dayQuery(dayIds) + pageQuery(after: after, limit: limit))
    }

    /// The camp leadership sets fields for any person, also set ones and after the deadline (at most 100 fields).
    func setCampAttendance(campId: UUID, _ fields: [CampAttendanceLeaderField]) async throws -> [CampAttendanceEntry] {
        let result: CampAttendanceEntryList = try await load("PUT", rowPath(campId, "anwesenheit"), body: CampAttendanceLeaderBody(entries: fields))
        return result.entries
    }

    func campAttendanceSummary(campId: UUID) async throws -> CampAttendanceSummary {
        try await load("GET", rowPath(campId, "anwesenheit", nil, "/zusammenfassung"))
    }

    /// `nil` lifts the deadline.
    func setCampAttendanceDeadline(campId: UUID, _ deadline: Date?) async throws -> Date? {
        let result: CampAttendanceDeadline = try await load("PUT", rowPath(campId, "anwesenheit", nil, "/frist"), body: CampAttendanceDeadlineBody(deadline: deadline))
        return result.deadline
    }

    // MARK: Own attendance (team)

    func ownCampAttendance(campId: UUID, dayIds: [UUID] = []) async throws -> CampOwnAttendance {
        try await load("GET", rowPath(campId, "anwesenheit", nil, "/eigene"), query: dayQuery(dayIds))
    }

    /// Sets open fields of the signed-in person until the deadline (at most 100, all or nothing). A field that is set
    /// already, or a passed deadline, answers 409 `ANFRAGE_NOETIG`: read the fields with `CampRules.attendanceBlocked`
    /// and send `requestCampAttendanceChange`.
    func setOwnCampAttendance(campId: UUID, _ fields: [CampAttendanceField]) async throws -> [CampAttendanceEntry] {
        let result: CampAttendanceEntryList = try await load("PUT", rowPath(campId, "anwesenheit", nil, "/eigene"), body: CampAttendanceFieldsBody(entries: fields))
        return result.entries
    }

    // MARK: Requests (Anfragen)

    /// Step 1 of a change: the team asks for it. One request per field (at most 100, all or nothing); the camp
    /// leadership gets one notification per call. 409 `KEINE_ANFRAGE_NOETIG` or `ANFRAGE_OFFEN` name the `felder`.
    func requestCampAttendanceChange(campId: UUID, _ fields: [CampAttendanceField], note: String? = nil) async throws -> [CampAttendanceRequest] {
        let result: CampAttendanceRequestList = try await load("POST", rowPath(campId, "anwesenheit", nil, "/anfragen"), body: CampAttendanceFieldsBody(entries: fields, note: note))
        return result.requests
    }

    /// The requests of the whole team, oldest first. Camp leadership only.
    func campAttendanceRequests(campId: UUID, status: CampAttendanceRequestStatus? = nil, after: UUID? = nil, limit: Int = 100) async throws -> CampAttendanceRequestPage {
        var query = pageQuery(after: after, limit: limit)
        if let status { query.append(URLQueryItem(name: "status", value: status.rawValue)) }
        return try await load("GET", rowPath(campId, "anwesenheit", nil, "/anfragen"), query: query)
    }

    /// Step 2: the camp leadership accepts or rejects open requests (at most 50, all or nothing). Accepting sets the field.
    /// 409 `VERSION_KONFLIKT` or `BEREITS_ENTSCHIEDEN`.
    func decideCampAttendanceRequests(campId: UUID, _ decision: CampAttendanceDecisionKind, requests: [CampVersionRef]) async throws -> [CampAttendanceRequest] {
        let result: CampAttendanceRequestList = try await load("POST", rowPath(campId, "anwesenheit", nil, "/anfragen/entscheid"), body: CampAttendanceDecisionBody(decision: decision, requests: requests))
        return result.requests
    }
}
