import Foundation

/// Body for attendance: `{"da": true | false | null}`. `null` takes the entry back, so the key must always be written.
nonisolated struct PresenceBody: Encodable, Sendable {
    let present: Bool?

    enum CodingKeys: String, CodingKey { case present = "da" }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(present, forKey: .present)
    }
}

nonisolated struct AssignmentBody: Encodable, Sendable {
    let units: [UUID]
    let visibility: String

    enum CodingKeys: String, CodingKey { case units = "stufen", visibility = "sichtbarkeit" }
}

extension APIClient {
    private func id(_ uuid: UUID) -> String { uuid.uuidString.lowercased() }

    func units() async throws -> [UnitInfo] {
        let list: UnitList = try await load("GET", "/api/v1/stufen")
        return list.units
    }

    func participationOverview(programId: UUID) async throws -> ParticipationOverview {
        try await load("GET", "/api/v1/programme/\(id(programId))/teilnahmen")
    }

    /// The person's own answer as a leader.
    func setOwnRegistration(programId: UUID, answer: Answer) async throws {
        try await send("PUT", "/api/v1/programme/\(id(programId))/leitung", body: ["status": answer.rawValue])
    }

    func assign(programId: UUID, unitIds: [UUID], visibility: Visibility) async throws {
        try await send(
            "PUT", "/api/v1/programme/\(id(programId))/zuordnung",
            body: AssignmentBody(units: unitIds, visibility: visibility.rawValue)
        )
    }

    func attendance(unitId: UUID, count: Int = 5) async throws -> AttendanceOverview {
        try await load("GET", "/api/v1/stufen/\(id(unitId))/anwesenheit", query: [URLQueryItem(name: "anzahl", value: String(count))])
    }

    func setChildPresence(unitId: UUID, programId: UUID, childId: UUID, present: Bool?) async throws {
        try await send(
            "PUT", "/api/v1/stufen/\(id(unitId))/anwesenheit/\(id(programId))/kinder/\(id(childId))",
            body: PresenceBody(present: present)
        )
    }

    func setLeaderPresence(unitId: UUID, programId: UUID, userId: UUID, present: Bool?) async throws {
        try await send(
            "PUT", "/api/v1/stufen/\(id(unitId))/anwesenheit/\(id(programId))/leitende/\(id(userId))",
            body: PresenceBody(present: present)
        )
    }
}

/// Which controls a person gets. The API checks again; this only hides what would be refused anyway.
nonisolated struct LeadershipPermissions {
    let profile: Profile

    /// Overview of who registered: admins and leaders of an assigned unit.
    func canSeeOverview(of program: Program) -> Bool {
        profile.admin || program.units.contains { profile.isLeader(of: $0.id) }
    }

    /// Own registration is only offered when the server sent `eigeneAnmeldung` and the program has not started.
    func canRegisterAsLeader(for program: Program, now: Date = .now) -> Bool {
        guard program.ownRegistration != nil else { return false }
        guard let first = program.start ?? program.firstDay else { return true }
        return first > now
    }

    /// Assigning units and visibility: admins and unit leaders. Leaders always get 403.
    var canAssign: Bool { profile.admin || profile.isUnitLeader }

    /// Units that can be chosen: all for admins, only the own unit-leader units otherwise.
    func assignableUnits(from all: [UnitInfo]) -> [UnitInfo] {
        profile.admin ? all : all.filter { profile.isUnitLeader(of: $0.id) }
    }

    /// Unit leaders may only change units they lead. A changed visibility needs all old and new units to be theirs.
    func canSaveAssignment(
        oldUnits: Set<UUID>, newUnits: Set<UUID>, oldVisibility: Visibility, newVisibility: Visibility
    ) -> Bool {
        if profile.admin { return true }
        let changed = oldUnits.symmetricDifference(newUnits)
        let own: (UUID) -> Bool = { profile.isUnitLeader(of: $0) }
        guard changed.allSatisfy(own) else { return false }
        if oldVisibility != newVisibility { return oldUnits.union(newUnits).allSatisfy(own) }
        return true
    }

    /// A program without units may only be internal.
    nonisolated static func isValidAssignment(units: Set<UUID>, visibility: Visibility) -> Bool {
        !units.isEmpty || visibility == .internalOnly
    }

    /// Units whose attendance the person may see: leaders and unit leaders of the unit, and admins for all.
    func attendanceUnits(from units: [UnitSummary]) -> [UnitSummary] {
        profile.admin ? units : units.filter { profile.isLeader(of: $0.id) }
    }
}

nonisolated enum LeadershipMessages {
    static func message(for error: APIError) -> (text: String, reload: Bool) {
        switch (error.kind, error.code) {
        case (.conflict, "PROGRAMM_BEGONNEN"):
            (String(localized: "Das Programm hat schon begonnen. Die Anmeldung lässt sich nicht mehr ändern."), true)
        case (.conflict, "ANWESENHEIT_GESCHLOSSEN"):
            (String(localized: "Die Anwesenheit lässt sich erst nach Beginn des Programms und bis 14 Tage danach erfassen."), true)
        case (.forbidden, _):
            (String(localized: "Dafür fehlt dir die Berechtigung."), true)
        case (.notFound, _):
            (String(localized: "Das gibt es nicht mehr oder du siehst es nicht."), true)
        default:
            (error.displayText, false)
        }
    }
}
