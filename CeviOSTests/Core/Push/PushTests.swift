import Foundation
import Testing
@testable import CeviOS

struct PushTests {
    private let id = UUID()

    @Test func chatAndProgramPushesLeadToTheirTarget() {
        #expect(PushTarget.from(userInfo: ["typ": "chat", "id": id.uuidString]) == .chat(id))
        #expect(PushTarget.from(userInfo: ["typ": "programm", "id": id.uuidString]) == .program(id))
    }

    @Test func announcementNeedsNoId() {
        #expect(PushTarget.from(userInfo: ["typ": "mitteilung", "id": ""]) == .announcement)
    }

    @Test func unknownTypesAndBrokenIdsYieldNil() {
        #expect(PushTarget.from(userInfo: ["typ": "unbekannt", "id": id.uuidString]) == nil)
        #expect(PushTarget.from(userInfo: ["typ": "chat", "id": "kein-uuid"]) == nil)
        #expect(PushTarget.from(userInfo: [:]) == nil)
    }

    @Test func pushForTheOpenChatIsHidden() {
        let target = PushTarget.chat(id)
        #expect(target.isHidden(openChatId: id))
        #expect(!target.isHidden(openChatId: UUID()))
        #expect(!target.isHidden(openChatId: nil))
        #expect(!PushTarget.program(id).isHidden(openChatId: id))
    }

    @Test(arguments: [
        ("cX1y2Z3a4B5c6D7e8F9g:APA91bxxxxxxxxxxxxxxxxxxxxxxxx", true),
        (String(repeating: "a", count: 20), true),
        (String(repeating: "a", count: 19), false),
        (String(repeating: "a", count: 513), false),
        ("ExponentPushToken[abcdefghijklmnopqrstu]", false),
        ("has space has space has space", false),
    ])
    func tokenShapeFollowsTheApi(token: String, valid: Bool) {
        #expect(PushToken.isValid(token) == valid)
    }

    @Test func registrationSendsPutWithTokenAndPlatform() async throws {
        let host = "a\(UUID().uuidString.prefix(8).lowercased()).test.example.org"
        StubProtocol.register(host: host) { _ in (204, [:], Data()) }
        let client = APIClient(
            baseURL: URL(string: "https://\(host)")!, appVersion: "1.0.0", cookieStore: InMemoryCookieStore(["s": "1"]),
            session: APIClient.makeSession(protocolClasses: [StubProtocol.self])
        )
        let token = "cX1y2Z3a4B5c6D7e8F9g:APA91bxxxxxxxxxxxxxxxxxxxxxxxx"
        try await client.registerPushToken(token)
        try await client.registerPushToken("ExponentPushToken[abcdefghijklmnopqrstu]")
        let requests = StubProtocol.requests(host: host)
        #expect(requests.count == 1)
        #expect(requests[0].httpMethod == "PUT")
        #expect(requests[0].url?.path == "/api/v1/push-token")
        let body = String(decoding: try JSONEncoder().encode(PushTokenBody(token: token)), as: UTF8.self)
        #expect(body.contains(#""plattform":"ios""#))
    }
}
