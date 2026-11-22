import Foundation

/// Meetings, agenda, protocols, decisions, mentions, notice board, polls, reactions and inbox.
/// Rows with a `version` answer 409 `VERSION_KONFLIKT` when changed meanwhile: `CampRules.versionConflict`.
extension APIClient {
    private func lower(_ id: UUID) -> String { id.uuidString.lowercased() }

    // MARK: Meetings (Höcks)

    /// `from` and `to` limit the dates (calendar days).
    func campMeetings(campId: UUID, from: Date? = nil, to: Date? = nil, after: UUID? = nil, limit: Int = 50) async throws -> CampMeetingPage {
        var query = pageQuery(after: after, limit: limit)
        if let from { query.append(URLQueryItem(name: "von", value: DateFormats.calendarDayText(from))) }
        if let to { query.append(URLQueryItem(name: "bis", value: DateFormats.calendarDayText(to))) }
        return try await load("GET", rowPath(campId, "hoecks"), query: query)
    }

    func campMeeting(campId: UUID, meetingId: UUID) async throws -> CampMeetingView<CampMeeting> {
        try await load("GET", rowPath(campId, "hoecks", meetingId))
    }

    func createCampMeeting(campId: UUID, _ body: CampMeetingCreate) async throws -> CampMeeting {
        try await load("POST", rowPath(campId, "hoecks"), body: body)
    }

    func updateCampMeeting(campId: UUID, meetingId: UUID, _ body: CampMeetingPatch) async throws -> CampMeeting {
        try await load("PATCH", rowPath(campId, "hoecks", meetingId), body: body)
    }

    func deleteCampMeeting(campId: UUID, meetingId: UUID, version: Int) async throws {
        try await send("DELETE", rowPath(campId, "hoecks", meetingId), query: versionQuery(version))
    }

    /// The calendar file (`.ics`) of the meeting, as the server sends it.
    func campMeetingCalendar(campId: UUID, meetingId: UUID) async throws -> Data {
        try await send("GET", rowPath(campId, "hoecks", meetingId, ".ics"))
    }

    /// Everything for the meeting: agenda, members to tick off, round of portfolios.
    func campMeetingMode(campId: UUID, meetingId: UUID) async throws -> CampMeetingMode {
        try await load("GET", rowPath(campId, "hoecks", meetingId, "/modus"))
    }

    func markCampMeetingPresent(campId: UUID, meetingId: UUID, personId: UUID) async throws {
        try await send("PUT", rowPath(campId, "hoecks", meetingId, "/anwesende/" + lower(personId)))
    }

    func unmarkCampMeetingPresent(campId: UUID, meetingId: UUID, personId: UUID) async throws {
        try await send("DELETE", rowPath(campId, "hoecks", meetingId, "/anwesende/" + lower(personId)))
    }

    /// Moves the items that wait for the next meeting (all, or `itemIds`) into this meeting. Returns how many.
    func adoptCampAgendaItems(campId: UUID, meetingId: UUID, itemIds: [UUID]? = nil) async throws -> Int {
        let result: CampAgendaAdopted = try await load("POST", rowPath(campId, "hoecks", meetingId, "/traktanden/uebernehmen"), body: CampAgendaAdoptBody(itemIds: itemIds))
        return result.adopted
    }

    // MARK: Agenda items (Traktanden)

    /// The items that wait for the next meeting.
    func campWaitingAgendaItems(campId: UUID) async throws -> [CampAgendaItem] {
        let result: CampAgendaWaiting = try await load("GET", rowPath(campId, "traktanden", nil, "/naechster"))
        return result.items
    }

    func createCampAgendaItem(campId: UUID, _ body: CampAgendaItemCreate) async throws -> CampAgendaItem {
        try await load("POST", rowPath(campId, "traktanden"), body: body)
    }

    func updateCampAgendaItem(campId: UUID, itemId: UUID, _ body: CampAgendaItemPatch) async throws -> CampAgendaItem {
        try await load("PATCH", rowPath(campId, "traktanden", itemId), body: body)
    }

    func deleteCampAgendaItem(campId: UUID, itemId: UUID, version: Int) async throws {
        try await send("DELETE", rowPath(campId, "traktanden", itemId), query: versionQuery(version))
    }

    /// `meetingId` `nil`: the order in the list for the next meeting.
    func reorderCampAgenda(campId: UUID, meetingId: UUID?, _ entries: [CampVersionRef]) async throws {
        try await send("PUT", rowPath(campId, "traktanden", nil, "/reihenfolge"), body: CampAgendaOrderBody(meetingId: meetingId, entries: entries))
    }

    // MARK: Protocols and decisions

    func campProtocols(campId: UUID, filter: CampProtocolFilter = CampProtocolFilter(), after: UUID? = nil, limit: Int = 50) async throws -> CampProtocolPage {
        try await load("GET", rowPath(campId, "protokolle"), query: pageQuery(after: after, limit: limit) + filter.queryItems)
    }

    func campProtocol(campId: UUID, protocolId: UUID) async throws -> CampProtocol {
        try await load("GET", rowPath(campId, "protokolle", protocolId))
    }

    func createCampProtocol(campId: UUID, _ body: CampProtocolCreate) async throws -> CampProtocol {
        try await load("POST", rowPath(campId, "protokolle"), body: body)
    }

    func updateCampProtocol(campId: UUID, protocolId: UUID, _ body: CampProtocolPatch) async throws -> CampProtocol {
        try await load("PATCH", rowPath(campId, "protokolle", protocolId), body: body)
    }

    func deleteCampProtocol(campId: UUID, protocolId: UUID, version: Int) async throws {
        try await send("DELETE", rowPath(campId, "protokolle", protocolId), query: versionQuery(version))
    }

    func campResolutions(campId: UUID, meetingId: UUID? = nil, protocolId: UUID? = nil, after: UUID? = nil, limit: Int = 50) async throws -> CampResolutionPage {
        var query = pageQuery(after: after, limit: limit)
        if let meetingId { query.append(URLQueryItem(name: "hoeckId", value: lower(meetingId))) }
        if let protocolId { query.append(URLQueryItem(name: "protokollId", value: lower(protocolId))) }
        return try await load("GET", rowPath(campId, "beschluesse"), query: query)
    }

    func campResolution(campId: UUID, resolutionId: UUID) async throws -> CampResolution {
        try await load("GET", rowPath(campId, "beschluesse", resolutionId))
    }

    func createCampResolution(campId: UUID, _ body: CampResolutionCreate) async throws -> CampResolution {
        try await load("POST", rowPath(campId, "beschluesse"), body: body)
    }

    func updateCampResolution(campId: UUID, resolutionId: UUID, _ body: CampResolutionPatch) async throws -> CampResolution {
        try await load("PATCH", rowPath(campId, "beschluesse", resolutionId), body: body)
    }

    func deleteCampResolution(campId: UUID, resolutionId: UUID, version: Int) async throws {
        try await send("DELETE", rowPath(campId, "beschluesse", resolutionId), query: versionQuery(version))
    }

    // MARK: Mentions (Erwähnungen)

    /// The own mentions. `open`: only the ones not done (`true`) or only the done ones (`false`).
    func campMentions(campId: UUID, open: Bool? = nil, after: UUID? = nil, limit: Int = 50) async throws -> CampMentionPage {
        var query = pageQuery(after: after, limit: limit)
        if let open { query.append(URLQueryItem(name: "offen", value: String(open))) }
        return try await load("GET", rowPath(campId, "erwaehnungen"), query: query)
    }

    /// Call after saving a text with `@` mentions: the server matches the mentions of the content and notifies new persons.
    func syncCampMentions(campId: UUID, source: CampMentionSourceKind, sourceId: UUID) async throws -> CampMentionSync {
        try await load("PUT", rowPath(campId, "erwaehnungen/" + source.rawValue, sourceId))
    }

    func setCampMentionDone(campId: UUID, mentionId: UUID, done: Bool) async throws -> CampMention {
        try await load("PATCH", rowPath(campId, "erwaehnungen", mentionId), body: CampMentionDoneBody(done: done))
    }

    /// Returns the task: a new one (201) or the one that existed already (200); the app does not tell them apart.
    func makeCampMentionTask(campId: UUID, mentionId: UUID) async throws -> UUID {
        let result: CampMentionTask = try await load("POST", rowPath(campId, "erwaehnungen", mentionId, "/als-aufgabe"))
        return result.taskId
    }

    // MARK: Notice board (Pinnwand), polls, reactions

    func campNotices(campId: UUID, scope: CampNoticeScope = .active, after: UUID? = nil, limit: Int = 50) async throws -> CampNoticePage {
        let query = pageQuery(after: after, limit: limit) + [URLQueryItem(name: "status", value: scope.rawValue)]
        return try await load("GET", rowPath(campId, "pinnwand"), query: query)
    }

    func campNotice(campId: UUID, noticeId: UUID) async throws -> CampNotice {
        try await load("GET", rowPath(campId, "pinnwand", noticeId))
    }

    func createCampNotice(campId: UUID, _ body: CampNoticeCreate) async throws -> CampNotice {
        try await load("POST", rowPath(campId, "pinnwand"), body: body)
    }

    func updateCampNotice(campId: UUID, noticeId: UUID, _ body: CampNoticePatch) async throws -> CampNotice {
        try await load("PATCH", rowPath(campId, "pinnwand", noticeId), body: body)
    }

    func deleteCampNotice(campId: UUID, noticeId: UUID, version: Int) async throws {
        try await send("DELETE", rowPath(campId, "pinnwand", noticeId), query: versionQuery(version))
    }

    func createCampPoll(campId: UUID, noticeId: UUID, _ body: CampPollCreate) async throws -> CampPoll {
        try await load("POST", rowPath(campId, "pinnwand", noticeId, "/umfrage"), body: body)
    }

    /// Close, reopen or change the closing time or the visibility of names.
    func updateCampPoll(campId: UUID, noticeId: UUID, _ body: CampPollPatch) async throws -> CampPoll {
        try await load("PATCH", rowPath(campId, "pinnwand", noticeId, "/umfrage"), body: body)
    }

    func deleteCampPoll(campId: UUID, noticeId: UUID, version: Int) async throws {
        try await send("DELETE", rowPath(campId, "pinnwand", noticeId, "/umfrage"), query: versionQuery(version))
    }

    /// Replaces the own vote (one option, or several if the poll allows it).
    func voteCampPoll(campId: UUID, noticeId: UUID, optionIds: [UUID]) async throws -> CampPoll {
        try await load("PUT", rowPath(campId, "pinnwand", noticeId, "/umfrage/stimme"), body: CampPollVoteBody(optionIds: optionIds))
    }

    func withdrawCampPollVote(campId: UUID, noticeId: UUID) async throws {
        try await send("DELETE", rowPath(campId, "pinnwand", noticeId, "/umfrage/stimme"))
    }

    func setCampReaction(campId: UUID, target: CampReactionTarget = .notice, targetId: UUID, _ reaction: CampReactionKey) async throws -> CampReactions {
        try await load("PUT", rowPath(campId, "reaktionen/" + target.rawValue, targetId), body: CampReactionBody(reaction: reaction))
    }

    func removeCampReaction(campId: UUID, target: CampReactionTarget = .notice, targetId: UUID) async throws {
        try await send("DELETE", rowPath(campId, "reaktionen/" + target.rawValue, targetId))
    }

    /// A printable sheet as PDF (the whole file in memory).
    func campHandout(campId: UUID, _ handout: CampHandout) async throws -> Data {
        try await send("GET", rowPath(campId, "aushaenge/" + handout.rawValue))
    }

    // MARK: Inbox (Eingang)

    /// For the camp leadership.
    func campInbox(campId: UUID, filter: CampInboxFilter = CampInboxFilter(), after: UUID? = nil, limit: Int = 50) async throws -> CampInboxPage {
        try await load("GET", rowPath(campId, "eingang"), query: pageQuery(after: after, limit: limit) + filter.queryItems)
    }

    func campInboxEntry(campId: UUID, entryId: UUID) async throws -> CampInboxEntry {
        try await load("GET", rowPath(campId, "eingang", entryId))
    }

    /// Anonymous or not. An anonymous answer carries the code once (`CampInboxSent.followUpCode`).
    func sendCampInbox(campId: UUID, _ body: CampInboxSend) async throws -> CampInboxSent {
        try await load("POST", rowPath(campId, "eingang"), body: body)
    }

    /// The own entries that are not anonymous.
    func campOwnInbox(campId: UUID, after: UUID? = nil, limit: Int = 50) async throws -> CampOwnInboxPage {
        try await load("GET", rowPath(campId, "eingang/eigene"), query: pageQuery(after: after, limit: limit))
    }

    /// Status and reply of an anonymous entry. The code goes in the body; a wrong code is always 404, at most 120 queries per hour.
    func campInboxStatus(campId: UUID, code: String) async throws -> CampInboxCodeView {
        try await load("POST", rowPath(campId, "eingang/status"), body: CampInboxCodeBody(code: code))
    }

    func updateCampInboxEntry(campId: UUID, entryId: UUID, _ body: CampInboxPatch) async throws -> CampInboxEntry {
        try await load("PATCH", rowPath(campId, "eingang", entryId), body: body)
    }

    func deleteCampInboxEntry(campId: UUID, entryId: UUID, version: Int) async throws {
        try await send("DELETE", rowPath(campId, "eingang", entryId), query: versionQuery(version))
    }

    /// Makes an agenda item from the entry; answers the entry with `agendaItemId` set.
    func makeCampInboxAgendaItem(campId: UUID, entryId: UUID, _ body: CampInboxToAgenda) async throws -> CampInboxEntry {
        try await load("POST", rowPath(campId, "eingang", entryId, "/traktandum"), body: body)
    }
}
