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

        let contract = try Self.contractOperations()
        let calls = StubProtocol.requests(host: host).map { "\($0.httpMethod ?? "GET") \(Self.normalize($0.url?.path ?? ""))" }
        #expect(calls.count >= 25)
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
