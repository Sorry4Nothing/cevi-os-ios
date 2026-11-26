import Foundation

extension APIClient {
    /// Needs `check.lesen` (403 otherwise). The server calculates on every request.
    func campCheck(campId: UUID) async throws -> CampCheck {
        try await load("GET", rowPath(campId, "check"))
    }

    /// The own points by order, at most 100.
    func campCheckPoints(campId: UUID) async throws -> CampCheckPoints {
        try await load("GET", rowPath(campId, "check", nil, "/punkte"))
    }

    /// Needs `zeitplan.bearbeiten` and `check.lesen`.
    func createCampCheckPoint(campId: UUID, _ body: CampCheckPointCreate) async throws -> CampCheckPoint {
        try await load("POST", rowPath(campId, "check", nil, "/punkte"), body: body)
    }

    /// 409 `VERSION_KONFLIKT` if the row changed.
    func updateCampCheckPoint(campId: UUID, pointId: UUID, _ body: CampCheckPointPatch) async throws -> CampCheckPoint {
        try await load("PATCH", rowPath(campId, "check", nil, "/punkte/" + pointId.uuidString.lowercased()), body: body)
    }

    func deleteCampCheckPoint(campId: UUID, pointId: UUID, version: Int) async throws {
        try await send("DELETE", rowPath(campId, "check", nil, "/punkte/" + pointId.uuidString.lowercased()), query: versionQuery(version))
    }
}
