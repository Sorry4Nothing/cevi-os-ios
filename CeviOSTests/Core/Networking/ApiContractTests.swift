import Foundation
import Testing
@testable import CeviOS

/// Every call of the app must exist in the API description (`api-vertrag/openapi.yaml`, copy from the backend).
struct ApiContractTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// "METHOD /path/{}" for every operation in the description.
    static func contractOperations() throws -> Set<String> {
        let text = try String(contentsOf: root.appending(path: "api-vertrag/openapi.yaml"), encoding: .utf8)
        var operations: Set<String> = []
        var path: String?
        var inPaths = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("paths:") { inPaths = true; continue }
            if inPaths, !line.isEmpty, !line.hasPrefix(" ") { break }
            guard inPaths else { continue }
            if line.hasPrefix("  /"), line.hasSuffix(":") {
                path = normalize(String(line.dropFirst(2).dropLast()))
            } else if let path, line.hasPrefix("    "), !line.hasPrefix("     "), line.hasSuffix(":") {
                let method = line.trimmingCharacters(in: .whitespaces).dropLast().uppercased()
                if ["GET", "POST", "PUT", "PATCH", "DELETE"].contains(method) { operations.insert("\(method) \(path)") }
            }
        }
        return operations
    }

    /// `{id}` and concrete UUIDs both become `{}`.
    static func normalize(_ path: String) -> String {
        var result = path.replacing(/\{[^}]+\}/, with: "{}")
        result = result.replacing(/\/aufloesen\/lager_[a-z]+\//, with: "/aufloesen/{}/")
        result = result.replacing(/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/, with: "{}")
        return result
    }

    @Test func descriptionIsReadable() throws {
        let operations = try Self.contractOperations()
        #expect(operations.contains("GET /api/v1/ich"))
        #expect(operations.contains("POST /api/auth/sign-in/username"))
        #expect(operations.count > 40)
    }

    @Test func everyCallOfTheAppIsInTheDescription() async throws {
        let host = "a\(UUID().uuidString.prefix(8).lowercased()).test.example.org"
        StubProtocol.register(host: host) { _ in (200, [:], Data("{}".utf8)) }
        let client = APIClient(
            baseURL: URL(string: "https://\(host)")!, appVersion: "1.0.0", cookieStore: InMemoryCookieStore(["s": "1"]),
            session: APIClient.makeSession(protocolClasses: [StubProtocol.self])
        )
        let id = UUID(), other = UUID()
        let token = "cX1y2Z3a4B5c6D7e8F9g:APA91bxxxxxxxxxxxxxxxxxxxxxxxx"

        // Answers do not matter, only which requests the app sends.
        _ = try? await client.signIn(username: "a", password: "b")
        _ = try? await client.checkSession()
        _ = try? await client.loadProfile()
        try? await client.changePassword(current: "a", new: "b")
        try? await client.acknowledgePrivacy()
        await client.signOut()
        try? await client.updateProfile(ProfilePatch(pushPrograms: false))
        try? await client.uploadProfileImage(Data([0xFF, 0xD8]))
        try? await client.deleteProfileImage()
        _ = try? await client.image(path: "/api/v1/personen/\(id.uuidString.lowercased())/bild")
        _ = try? await client.image(path: "/api/v1/stufen/\(id.uuidString.lowercased())/logo")
        _ = try? await client.units()
        _ = try? await client.programs(from: .now, to: .now)
        _ = try? await client.program(id: id)
        _ = try? await client.contacts(programId: id)
        try? await client.setParticipation(programId: id, childId: other, answer: .yes)
        try? await client.setOwnRegistration(programId: id, answer: .no)
        _ = try? await client.participationOverview(programId: id)
        try? await client.assign(programId: id, unitIds: [other], visibility: .parents)
        _ = try? await client.chats()
        _ = try? await client.openDirectChat(unitId: id)
        _ = try? await client.messages(chatId: id)
        try? await client.sendMessage(chatId: id, text: "x")
        try? await client.markRead(chatId: id)
        try? await client.registerPushToken(token)
        _ = try? await client.camps()
        _ = try? await client.camp(id: id)
        _ = try? await client.campRights(campId: id)
        _ = try? await client.campNotifications(campId: id, after: other)
        _ = try? await client.campUnreadCount(campId: id)
        try? await client.markCampNotificationsRead(campId: id, ids: [other])
        _ = try? await client.resolveCampPush(type: .task, objectId: id)
        _ = try? await client.campFeedState(campId: id)
        _ = try? await client.campChanges(campId: id, since: 0)

        // Start and tasks (A1)
        _ = try? await client.campPortfolios(campId: id)
        _ = try? await client.campPortfolio(campId: id, portfolioId: other)
        _ = try? await client.createCampPortfolio(campId: id, CampPortfolioCreate(code: "A", name: "B"))
        _ = try? await client.updateCampPortfolio(campId: id, portfolioId: other, CampPortfolioPatch(version: 1))
        try? await client.deleteCampPortfolio(campId: id, portfolioId: other, version: 1)
        try? await client.reorderCampPortfolios(campId: id, [])
        _ = try? await client.campPortfolioLinks(campId: id, portfolioId: other)
        _ = try? await client.createCampPortfolioLink(campId: id, portfolioId: other, CampLinkCreate(title: "A", url: "https://example.org"))
        _ = try? await client.updateCampPortfolioLink(campId: id, portfolioId: other, linkId: id, CampLinkPatch(version: 1))
        try? await client.deleteCampPortfolioLink(campId: id, portfolioId: other, linkId: id, version: 1)
        _ = try? await client.campPortfolioNotes(campId: id, portfolioId: other)
        _ = try? await client.createCampPortfolioNote(campId: id, portfolioId: other, text: "x")
        _ = try? await client.updateCampPortfolioNote(campId: id, portfolioId: other, noteId: id, version: 1, text: "x")
        try? await client.deleteCampPortfolioNote(campId: id, portfolioId: other, noteId: id, version: 1)
        _ = try? await client.campTasks(campId: id)
        _ = try? await client.campTask(campId: id, taskId: other)
        _ = try? await client.createCampTask(campId: id, CampTaskCreate(title: "x"))
        _ = try? await client.updateCampTask(campId: id, taskId: other, CampTaskPatch(version: 1))
        try? await client.deleteCampTask(campId: id, taskId: other, version: 1)
        try? await client.reorderCampTasks(campId: id, [])
        _ = try? await client.setCampTaskStatus(campId: id, taskId: other, version: 1, status: .done)
        _ = try? await client.campTaskDuplicates(campId: id)
        _ = try? await client.campTaskDetails(campId: id, taskId: other)
        _ = try? await client.campTaskHistory(campId: id, taskId: other)
        _ = try? await client.createCampChecklistItem(campId: id, taskId: other, CampChecklistCreate(text: "x"))
        _ = try? await client.updateCampChecklistItem(campId: id, taskId: other, itemId: id, CampChecklistPatch(version: 1))
        try? await client.deleteCampChecklistItem(campId: id, taskId: other, itemId: id, version: 1)
        try? await client.reorderCampChecklist(campId: id, taskId: other, [])
        _ = try? await client.createCampTaskLink(campId: id, taskId: other, CampLinkCreate(title: "A", url: "https://example.org"))
        _ = try? await client.updateCampTaskLink(campId: id, taskId: other, linkId: id, CampLinkPatch(version: 1))
        try? await client.deleteCampTaskLink(campId: id, taskId: other, linkId: id, version: 1)
        _ = try? await client.setCampTaskKeywords(campId: id, taskId: other, version: 1, keywords: [])
        _ = try? await client.mergeCampTasks(campId: id, taskId: other, version: 1, withId: id, withVersion: 1)
        _ = try? await client.suggestCampTasks(campId: id, text: "x")
        _ = try? await client.campSchedule(campId: id)
        _ = try? await client.campScheduleProposal(campId: id)
        _ = try? await client.adoptCampSchedule(campId: id, CampScheduleAdopt())
        _ = try? await client.createCampMilestone(campId: id, CampMilestoneCreate(title: "x", date: CampCalendarDay(.now)))
        _ = try? await client.updateCampMilestone(campId: id, milestoneId: other, CampMilestonePatch(version: 1))
        try? await client.deleteCampMilestone(campId: id, milestoneId: other, version: 1)
        _ = try? await client.previewCampMilestoneMove(campId: id, milestoneId: other, version: 1, to: .now)
        _ = try? await client.confirmCampMilestoneMove(campId: id, milestoneId: other, version: 1, to: .now, tasks: [])
        _ = try? await client.createCampDay(campId: id, CampDayCreate(date: CampCalendarDay(.now)))
        _ = try? await client.updateCampDay(campId: id, dayId: other, CampDayPatch(version: 1))
        try? await client.deleteCampDay(campId: id, dayId: other, version: 1)
        _ = try? await client.createCampDaySection(campId: id, CampSectionCreate(name: "x"))
        _ = try? await client.updateCampDaySection(campId: id, sectionId: other, CampSectionPatch(version: 1))
        try? await client.deleteCampDaySection(campId: id, sectionId: other, version: 1)
        _ = try? await client.campTodos(campId: id)
        _ = try? await client.createCampTodo(campId: id, CampTodoCreate(text: "x"))
        _ = try? await client.updateCampTodo(campId: id, todoId: other, CampTodoPatch(done: true))
        try? await client.deleteCampTodo(campId: id, todoId: other)
        _ = try? await client.applyCampTemplate(campId: id, templateId: other)
        _ = try? await client.campStart(campId: id)
        _ = try? await client.campDecisions(campId: id)

        let contract = try Self.contractOperations()
        let calls = StubProtocol.requests(host: host).map { "\($0.httpMethod ?? "GET") \(Self.normalize($0.url?.path ?? ""))" }
        #expect(calls.count >= 89)
        let missing = Set(calls).subtracting(contract)
        #expect(missing.isEmpty, "Not in the API description: \(missing.sorted())")
    }

    @Test func appNeverCallsTheAdminArea() throws {
        // The app has no admin functions (owner decision); nothing in the services may reach /api/v1/admin.
        let services = Self.root.appending(path: "CeviOS/Core/Services")
        let files = try FileManager.default.contentsOfDirectory(at: services, includingPropertiesForKeys: nil)
        for file in files where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(!text.contains("/api/v1/admin"), "\(file.lastPathComponent) calls the admin area")
        }
    }
}
