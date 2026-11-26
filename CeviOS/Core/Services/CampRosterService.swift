import Foundation

/// Participants, counting, rooms, trips, groups, shift plan and shift swaps.
/// Rows with a `version` answer 409 `VERSION_KONFLIKT` when changed meanwhile: `CampRules.versionConflict`.
extension APIClient {
    private func lower(_ id: UUID) -> String { id.uuidString.lowercased() }

    // MARK: Members (Mitglieder)

    /// Names for ids. Needs the right `einteilung.lesen` (403 otherwise); the team sees only people it already sees in lists.
    func campMembers(campId: UUID) async throws -> [CampMember] {
        let list: CampMemberList = try await load("GET", rowPath(campId, "mitglieder"))
        return list.members
    }

    // MARK: Participants (Teilnehmende)

    /// `level` filters by level.
    func campParticipants(campId: UUID, level: String? = nil, after: UUID? = nil, limit: Int = 100) async throws -> CampParticipantPage {
        var query = pageQuery(after: after, limit: limit)
        if let level { query.append(URLQueryItem(name: "stufe", value: level)) }
        return try await load("GET", rowPath(campId, "teilnehmer"), query: query)
    }

    func campParticipant(campId: UUID, participantId: UUID) async throws -> CampParticipant {
        try await load("GET", rowPath(campId, "teilnehmer", participantId))
    }

    func createCampParticipant(campId: UUID, _ body: CampParticipantCreate) async throws -> CampParticipant {
        try await load("POST", rowPath(campId, "teilnehmer"), body: body)
    }

    func updateCampParticipant(campId: UUID, participantId: UUID, _ body: CampParticipantPatch) async throws -> CampParticipant {
        try await load("PATCH", rowPath(campId, "teilnehmer", participantId), body: body)
    }

    func deleteCampParticipant(campId: UUID, participantId: UUID, version: Int) async throws {
        try await send("DELETE", rowPath(campId, "teilnehmer", participantId), query: versionQuery(version))
    }

    /// Step 1 of the import: nothing is written. Show rows, errors and duplicates, then `importCampParticipants`.
    func previewCampParticipantImport(campId: UUID, text: String) async throws -> CampParticipantImportResult {
        try await load("POST", rowPath(campId, "teilnehmer", nil, "/import"), body: CampParticipantImportBody(text: text, confirm: false))
    }

    /// Step 2: the same text, after the person confirmed the preview.
    func importCampParticipants(campId: UUID, text: String) async throws -> CampParticipantImportResult {
        try await load("POST", rowPath(campId, "teilnehmer", nil, "/import"), body: CampParticipantImportBody(text: text, confirm: true))
    }

    // MARK: Counting (Abzählen)

    func campCount(campId: UUID, filter: CampCountFilter = CampCountFilter(), after: UUID? = nil, limit: Int = 100) async throws -> CampCountPage {
        try await load("GET", rowPath(campId, "abzaehlen"), query: pageQuery(after: after, limit: limit) + filter.queryItems)
    }

    /// Ticks or unticks the people for everybody. Returns how many changed.
    func setCampCount(campId: UUID, checked: Bool, participantIds: [UUID]? = nil, personIds: [UUID]? = nil) async throws -> Int {
        let result: CampCountChanged = try await load("PUT", rowPath(campId, "abzaehlen"), body: CampCountSetBody(checked: checked, participantIds: participantIds, personIds: personIds))
        return result.changed
    }

    /// Clears every tick for everybody. The screen asks the person first. Returns how many were cleared.
    func resetCampCount(campId: UUID) async throws -> Int {
        let result: CampCountReset = try await load("POST", rowPath(campId, "abzaehlen", nil, "/zuruecksetzen"), body: CampCountResetBody(confirmed: true))
        return result.reset
    }

    // MARK: Rooms and tents (Zimmer, Zelte)

    func campRooms(campId: UUID) async throws -> CampRoomList {
        try await load("GET", rowPath(campId, "zimmer"))
    }

    func createCampRoom(campId: UUID, _ body: CampRoomCreate) async throws -> CampRoomRow {
        try await load("POST", rowPath(campId, "zimmer"), body: body)
    }

    func updateCampRoom(campId: UUID, roomId: UUID, _ body: CampRoomPatch) async throws -> CampRoomRow {
        try await load("PATCH", rowPath(campId, "zimmer", roomId), body: body)
    }

    func deleteCampRoom(campId: UUID, roomId: UUID, version: Int) async throws {
        try await send("DELETE", rowPath(campId, "zimmer", roomId), query: versionQuery(version))
    }

    /// People not placed in any room yet.
    func campOpenRoomPeople(campId: UUID, kind: CampPeopleKind? = nil, after: UUID? = nil, limit: Int = 100) async throws -> CampRoomOpenPage {
        var query = pageQuery(after: after, limit: limit)
        if let kind { query.append(URLQueryItem(name: "art", value: kind.rawValue)) }
        return try await load("GET", rowPath(campId, "zimmer", nil, "/offen"), query: query)
    }

    func placeInCampRoom(campId: UUID, roomId: UUID, _ people: CampRoomPeople) async throws -> CampRoomOccupancy {
        try await load("POST", rowPath(campId, "zimmer", roomId, "/zuordnung"), body: people)
    }

    func removeFromCampRoom(campId: UUID, roomId: UUID, _ people: CampRoomPeople) async throws -> CampRoomOccupancy {
        try await load("POST", rowPath(campId, "zimmer", roomId, "/zuordnung/entfernen"), body: people)
    }

    // MARK: Trips (Fahrten)

    func campTrips(campId: UUID, direction: CampTripDirection? = nil, after: UUID? = nil, limit: Int = 100) async throws -> CampTripPage {
        var query = pageQuery(after: after, limit: limit)
        if let direction { query.append(URLQueryItem(name: "richtung", value: direction.rawValue)) }
        return try await load("GET", rowPath(campId, "fahrten"), query: query)
    }

    /// Not readable for the team (404).
    func campTrip(campId: UUID, tripId: UUID) async throws -> CampTrip {
        try await load("GET", rowPath(campId, "fahrten", tripId))
    }

    func createCampTrip(campId: UUID, _ body: CampTripCreate) async throws -> CampTrip {
        try await load("POST", rowPath(campId, "fahrten"), body: body)
    }

    func updateCampTrip(campId: UUID, tripId: UUID, _ body: CampTripPatch) async throws -> CampTrip {
        try await load("PATCH", rowPath(campId, "fahrten", tripId), body: body)
    }

    func deleteCampTrip(campId: UUID, tripId: UUID, version: Int) async throws {
        try await send("DELETE", rowPath(campId, "fahrten", tripId), query: versionQuery(version))
    }

    /// `after` is the text cursor `next` of the previous page.
    func campPeopleWithoutTrip(campId: UUID, direction: CampTripDirection, after: String? = nil, limit: Int = 100) async throws -> CampTripWithoutPage {
        var query = [URLQueryItem(name: "richtung", value: direction.rawValue), URLQueryItem(name: "limit", value: String(limit))]
        if let after { query.append(URLQueryItem(name: "nach", value: after)) }
        return try await load("GET", rowPath(campId, "fahrten", nil, "/ohne"), query: query)
    }

    func addCampPassenger(campId: UUID, tripId: UUID, _ body: CampTripPassengerCreate) async throws -> CampTripBoarding {
        try await load("POST", rowPath(campId, "fahrten", tripId, "/mitfahrer"), body: body)
    }

    func removeCampPassenger(campId: UUID, tripId: UUID, passengerId: UUID, version: Int) async throws {
        try await send("DELETE", rowPath(campId, "fahrten", tripId, "/mitfahrer/" + lower(passengerId)), query: versionQuery(version))
    }

    // MARK: Groups (Gruppen)

    func campGroups(campId: UUID) async throws -> CampGroupList {
        try await load("GET", rowPath(campId, "gruppen"))
    }

    func createCampGroup(campId: UUID, _ body: CampGroupCreate) async throws -> CampGroupRow {
        try await load("POST", rowPath(campId, "gruppen"), body: body)
    }

    func updateCampGroup(campId: UUID, groupId: UUID, _ body: CampGroupPatch) async throws -> CampGroupRow {
        try await load("PATCH", rowPath(campId, "gruppen", groupId), body: body)
    }

    func deleteCampGroup(campId: UUID, groupId: UUID, version: Int) async throws {
        try await send("DELETE", rowPath(campId, "gruppen", groupId), query: versionQuery(version))
    }

    /// Returns how many changed.
    func assignCampGroup(campId: UUID, _ body: CampGroupAssign) async throws -> Int {
        let result: CampCountChanged = try await load("PUT", rowPath(campId, "gruppen", nil, "/zuordnung"), body: body)
        return result.changed
    }

    /// Returns how many changed.
    func deselectCampParticipants(campId: UUID, deselected: Bool, participantIds: [UUID]) async throws -> Int {
        let result: CampCountChanged = try await load("PUT", rowPath(campId, "gruppen", nil, "/abgewaehlt"), body: CampDeselectBody(deselected: deselected, participantIds: participantIds))
        return result.changed
    }

    /// Step 1 of mixing: a suggestion for `count` groups (2 to 20), nothing is written. `seed` repeats an earlier suggestion.
    func suggestCampGroupShuffle(campId: UUID, count: Int, seed: Int? = nil) async throws -> CampGroupShuffle {
        try await load("POST", rowPath(campId, "gruppen", nil, "/mischen"), body: CampGroupShuffleBody(count: count, confirm: false, seed: seed))
    }

    /// Step 2: writes the suggestion the person confirmed (same count and seed).
    func confirmCampGroupShuffle(campId: UUID, _ suggestion: CampGroupShuffle) async throws -> CampGroupShuffle {
        try await load("POST", rowPath(campId, "gruppen", nil, "/mischen"), body: CampGroupShuffleBody(count: suggestion.groups.count, confirm: true, seed: suggestion.seed))
    }

    // MARK: Shift plan (Schichtplan)

    func campShiftPlan(campId: UUID) async throws -> CampShiftPlan {
        try await load("GET", rowPath(campId, "schichtplan"))
    }

    func createCampDuty(campId: UUID, _ body: CampDutyCreate) async throws -> CampDuty {
        try await load("POST", rowPath(campId, "schichtplan", nil, "/dienste"), body: body)
    }

    func updateCampDuty(campId: UUID, dutyId: UUID, _ body: CampDutyPatch) async throws -> CampDuty {
        try await load("PATCH", rowPath(campId, "schichtplan", nil, "/dienste/" + lower(dutyId)), body: body)
    }

    func deleteCampDuty(campId: UUID, dutyId: UUID, version: Int) async throws {
        try await send("DELETE", rowPath(campId, "schichtplan", nil, "/dienste/" + lower(dutyId)), query: versionQuery(version))
    }

    /// Sets the staff of a duty on a day. Returns how many shifts changed.
    func setCampShifts(campId: UUID, _ body: CampShiftStaff) async throws -> Int {
        let result: CampCountChanged = try await load("PUT", rowPath(campId, "schichtplan", nil, "/schichten"), body: body)
        return result.changed
    }

    /// Step 1 of «fill empty duties»: a suggestion, nothing is written.
    func suggestCampShifts(campId: UUID, options: CampShiftOptions = CampShiftOptions(), seed: Int? = nil) async throws -> CampShiftProposal {
        try await load("POST", rowPath(campId, "schichtplan", nil, "/vorschlag"), body: CampShiftProposalBody(confirm: false, seed: seed, options: options))
    }

    /// Step 2: writes the suggestion the person confirmed. `options` are the same as in step 1.
    func confirmCampShifts(campId: UUID, _ proposal: CampShiftProposal, options: CampShiftOptions = CampShiftOptions()) async throws -> CampShiftProposal {
        try await load("POST", rowPath(campId, "schichtplan", nil, "/vorschlag"), body: CampShiftProposalBody(confirm: true, seed: proposal.seed, options: options))
    }

    // MARK: Shift swaps (Diensttausch)

    func campShiftSwaps(campId: UUID, status: CampSwapStatus? = nil, after: UUID? = nil, limit: Int = 100) async throws -> CampShiftSwapPage {
        var query = pageQuery(after: after, limit: limit)
        if let status { query.append(URLQueryItem(name: "status", value: status.rawValue)) }
        return try await load("GET", rowPath(campId, "diensttausch"), query: query)
    }

    func ownCampShiftSwaps(campId: UUID) async throws -> [CampShiftSwap] {
        let result: CampShiftSwapList = try await load("GET", rowPath(campId, "diensttausch", nil, "/eigene"))
        return result.swaps
    }

    func requestCampShiftSwap(campId: UUID, _ body: CampShiftSwapCreate) async throws -> CampShiftSwap {
        try await load("POST", rowPath(campId, "diensttausch"), body: body)
    }

    func decideCampShiftSwap(campId: UUID, swapId: UUID, _ body: CampShiftSwapDecide) async throws -> CampShiftSwap {
        try await load("POST", rowPath(campId, "diensttausch", swapId, "/entscheid"), body: body)
    }

    func withdrawCampShiftSwap(campId: UUID, swapId: UUID, version: Int) async throws -> CampShiftSwap {
        try await load("POST", rowPath(campId, "diensttausch", swapId, "/zurueckziehen"), body: CampShiftSwapWithdraw(version: version))
    }
}
