import Foundation

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
}

nonisolated enum LeadershipMessages {
    static func message(for error: APIError) -> (text: String, reload: Bool) {
        switch (error.kind, error.code) {
        case (.conflict, "PROGRAMM_BEGONNEN"):
            (String(localized: "Das Programm hat schon begonnen. Die Anmeldung lässt sich nicht mehr ändern."), true)
        case (.forbidden, _):
            (String(localized: "Dafür fehlt dir die Berechtigung."), true)
        case (.notFound, _):
            (String(localized: "Das gibt es nicht mehr oder du siehst es nicht."), true)
        default:
            (error.displayText, false)
        }
    }
}
