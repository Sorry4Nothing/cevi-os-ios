import Foundation
import Testing
@testable import CeviOS

/// The simulated camp server of the UI tests (DEBUG) must answer every read the screens make in the shape the app decodes.
struct CampTestServerTests {
    private struct Credentials: Encodable { let username: String; let password: String }

    private func client(_ username: String) async throws -> APIClient {
        let client = APIClient(
            baseURL: URL(string: "https://ui-test.example.org")!, appVersion: "1.0.0", cookieStore: InMemoryCookieStore(),
            session: APIClient.makeSession(protocolClasses: [UITestBackend.self])
        )
        try await client.send("POST", "/api/auth/sign-in/username", body: Credentials(username: username, password: "geheim-geheim"))
        return client
    }

    private let camp = UUID(uuidString: World.activeCamp)!
    private let row = UUID(uuidString: "0190a000-0000-7000-8000-000000000101")!

    @Test func leadReadsEveryScreenWithoutDecodingErrors() async throws {
        let client = try await client("leitung.test")
        let camp = camp, row = row
        var failures: [String] = []
        func check(_ name: String, _ call: () async throws -> some Any) async {
            do { _ = try await call() } catch { failures.append("\(name): \(error)") }
        }
        await check("camps") { try await client.camps() }
        await check("camp") { try await client.camp(id: camp) }
        await check("rights") { try await client.campRights(campId: camp) }
        await check("notifications") { try await client.campNotifications(campId: camp) }
        await check("unread") { try await client.campUnreadCount(campId: camp) }
        await check("settings") { try await client.campNotificationSettings() }
        await check("portfolios") { try await client.campPortfolios(campId: camp) }
        await check("tasks") { try await client.campTasks(campId: camp) }
        await check("task") { try await client.campTask(campId: camp, taskId: UUID(uuidString: "0190a000-0000-7000-8000-000000000201")!) }
        await check("taskDetails") { try await client.campTaskDetails(campId: camp, taskId: row) }
        await check("taskHistory") { try await client.campTaskHistory(campId: camp, taskId: row) }
        await check("duplicates") { try await client.campTaskDuplicates(campId: camp) }
        await check("schedule") { try await client.campSchedule(campId: camp) }
        await check("scheduleProposal") { try await client.campScheduleProposal(campId: camp) }
        await check("todos") { try await client.campTodos(campId: camp) }
        await check("start") { try await client.campStart(campId: camp) }
        await check("decisions") { try await client.campDecisions(campId: camp) }
        await check("meetings") { try await client.campMeetings(campId: camp) }
        await check("meeting") { try await client.campMeeting(campId: camp, meetingId: row) }
        await check("meetingMode") { try await client.campMeetingMode(campId: camp, meetingId: row) }
        await check("waitingAgenda") { try await client.campWaitingAgendaItems(campId: camp) }
        await check("protocols") { try await client.campProtocols(campId: camp) }
        await check("resolutions") { try await client.campResolutions(campId: camp) }
        await check("mentions") { try await client.campMentions(campId: camp) }
        await check("notices") { try await client.campNotices(campId: camp) }
        await check("notice") { try await client.campNotice(campId: camp, noticeId: row) }
        await check("inbox") { try await client.campInbox(campId: camp) }
        await check("ownInbox") { try await client.campOwnInbox(campId: camp) }
        await check("participants") { try await client.campParticipants(campId: camp) }
        await check("count") { try await client.campCount(campId: camp) }
        await check("rooms") { try await client.campRooms(campId: camp) }
        await check("openRoomPeople") { try await client.campOpenRoomPeople(campId: camp) }
        await check("trips") { try await client.campTrips(campId: camp) }
        await check("trip") { try await client.campTrip(campId: camp, tripId: row) }
        await check("withoutTrip") { try await client.campPeopleWithoutTrip(campId: camp, direction: .outbound) }
        await check("groups") { try await client.campGroups(campId: camp) }
        await check("shiftPlan") { try await client.campShiftPlan(campId: camp) }
        await check("swaps") { try await client.campShiftSwaps(campId: camp) }
        await check("ownSwaps") { try await client.ownCampShiftSwaps(campId: camp) }
        await check("attendance") { try await client.campAttendance(campId: camp) }
        await check("ownAttendance") { try await client.ownCampAttendance(campId: camp) }
        await check("attendanceSummary") { try await client.campAttendanceSummary(campId: camp) }
        await check("attendanceRequests") { try await client.campAttendanceRequests(campId: camp) }
        await check("dayPages") { try await client.campDayPages(campId: camp) }
        await check("dayPage") { try await client.campDayPage(campId: camp, dayId: row) }
        await check("weather") { try await client.campWeather(campId: camp) }
        await check("today") { try await client.campToday(campId: camp) }
        await check("myWeek") { try await client.campMyWeek(campId: camp) }
        await check("shopping") { try await client.campShopping(campId: camp) }
        await check("shoppingTotals") { try await client.campShoppingTotals(campId: camp) }
        await check("shoppingSuggestions") { try await client.campShoppingSuggestions(campId: camp) }
        await check("shoppingItem") { try await client.campShoppingItem(campId: camp, itemId: row) }
        await check("packing") { try await client.campPackingList(campId: camp) }
        await check("emergency") { try await client.campEmergency(campId: camp) }
        await check("infos") { try await client.campInfos(campId: camp) }
        await check("info") { try await client.campInfo(campId: camp, infoId: row) }
        await check("documents") { try await client.campDocuments(campId: camp) }
        await check("document") { try await client.campDocument(campId: camp, documentId: row) }
        await check("contacts") { try await client.campContacts(campId: camp) }
        await check("contact") { try await client.campContact(campId: camp, contactId: row) }
        await check("members") { try await client.campMembers(campId: camp) }
        await check("templates") { try await client.campTemplates(campId: camp) }
        await check("search") { try await client.searchCamp(campId: camp, text: "Zelt") }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    @Test func parentsHaveNoCampAndTheClosedCampIsReadOnly() async throws {
        let parent = try await client("eltern.test")
        #expect(try await parent.camps().isEmpty)
        let lead = try await client("leitung.test")
        let camps = try await lead.camps()
        #expect(camps.count == 2)
        #expect(camps.first { !$0.camp.status.isOpen }.map { _ in true } == true)
        let closed = try await lead.camp(id: UUID(uuidString: World.closedCamp)!)
        #expect(closed.isReadOnly)
    }

    @Test func statusChangeMeetsOneConflictThenSucceeds() async throws {
        let client = try await client("leitung.test")
        let task = UUID(uuidString: UITestCampState.conflictTask)!
        do {
            _ = try await client.setCampTaskStatus(campId: camp, taskId: task, version: 1, status: .done)
            Issue.record("expected a conflict")
        } catch let error as APIError {
            #expect(CampRules.versionConflict(error, as: CampTask.self)?.current?.version == 2)
        }
        let done = try await client.setCampTaskStatus(campId: camp, taskId: task, version: 2, status: .done)
        #expect(done.status == .done)
    }

    @Test func teamMayNotReadTheTaskList() async throws {
        let client = try await client("team.test")
        await #expect(throws: APIError.self) { try await client.campTasks(campId: camp) }
        let start = try await client.campStart(campId: camp)
        #expect(start.progress.tasks == nil)
    }
}
