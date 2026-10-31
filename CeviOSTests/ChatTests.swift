import Foundation
import Testing
@testable import CeviOS

struct ChatTests {
    private static func message(_ id: String, text: String = "x") -> ChatMessage {
        let json = """
        {"id":"\(id)","text":"\(text)","erstelltAm":"2026-05-02T12:30:00Z","programm":null,"eigene":false,
         "autor":{"id":"00000000-0000-7000-8000-000000000001","name":"A","ceviName":null,"bildUrl":null,"stufenleitung":false}}
        """
        return try! JSONDecoder.api.decode(ChatMessage.self, from: Data(json.utf8))
    }

    private let m1 = message("0190a000-0000-7000-8000-000000000001")
    private let m2 = message("0190a000-0000-7000-8000-000000000002")
    private let m3 = message("0190a000-0000-7000-8000-000000000003")

    @Test func mergeKeepsNewestFirstWithoutDuplicates() {
        let merged = ChatRules.merge(existing: [m2, m1], newest: [m3, m2])
        #expect(merged.map(\.id) == [m3.id, m2.id, m1.id])
    }

    @Test func mergeAddsOlderPagesBehindTheKnownOnes() {
        let merged = ChatRules.merge(existing: [m3], newest: [m2, m1])
        #expect(merged.map(\.id) == [m3.id, m2.id, m1.id])
    }

    @Test func sendableTextIsTrimmedAndLimited() {
        #expect(ChatRules.sendableText("  Hallo \n") == "Hallo")
        #expect(ChatRules.sendableText("   ") == nil)
        #expect(ChatRules.sendableText(String(repeating: "a", count: 2000)) != nil)
        #expect(ChatRules.sendableText(String(repeating: "a", count: 2001)) == nil)
    }

    @Test func rejectionsAndRateLimitShowTheServerText() {
        let filter = APIError.from(status: 400, data: Data(#"{"code":"WORTFILTER","message":"Bitte freundlich bleiben."}"#.utf8))
        #expect(ChatRules.sendError(filter) == "Bitte freundlich bleiben.")
        let limit = APIError.from(status: 429, data: Data(#"{"code":"ZU_VIELE_ANFRAGEN","message":"Zu viele Nachrichten."}"#.utf8))
        #expect(ChatRules.sendError(limit) == "Zu viele Nachrichten.")
    }

    @Test func chatListIsDecodedAndUnreadIsSummed() throws {
        let json = """
        {"chats":[{"id":"0190a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b","typ":"stufe","stufe":{"id":"0190a1b2-0000-7e5f-8a9b-0c1d2e3f4a5b","name":"Pfadi","kuerzel":"PF"},
          "eltern":null,"ungelesen":2,"letzteNachricht":{"text":"Hallo","erstelltAm":"2026-05-02T12:30:00Z","eigene":false,
          "autor":{"id":"0190a1b2-1111-7e5f-8a9b-0c1d2e3f4a5b","name":"L","ceviName":"Wolke"}},"stufenleitung":[]},
         {"id":"0190a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5c","typ":"direkt","stufe":{"id":"0190a1b2-0000-7e5f-8a9b-0c1d2e3f4a5b","name":"Pfadi","kuerzel":"PF"},
          "eltern":{"id":"0190a1b2-2222-7e5f-8a9b-0c1d2e3f4a5b","name":"E","ceviName":null},"ungelesen":3,"letzteNachricht":null,"stufenleitung":[]}]}
        """
        let list = try JSONDecoder.api.decode(ChatList.self, from: Data(json.utf8))
        #expect(list.chats.map(\.kind) == [.group, .direct])
        #expect(list.chats[0].lastMessage?.author.displayName == "L (Wolke)")
        #expect(ChatRules.totalUnread(list.chats) == 5)
    }

    @Test func pageCursorIsPassedAsVorAndEndIsNil() async throws {
        let host = "a\(UUID().uuidString.prefix(8).lowercased()).test.example.org"
        StubProtocol.register(host: host) { request in
            let hasCursor = request.url?.query?.contains("vor=") == true
            let body = hasCursor ? #"{"nachrichten":[],"naechster":null}"# : #"{"nachrichten":[],"naechster":"0190a000-0000-7000-8000-000000000001"}"#
            return (200, [:], Data(body.utf8))
        }
        let client = APIClient(
            baseURL: URL(string: "https://\(host)")!, appVersion: "1.0.0", cookieStore: InMemoryCookieStore(["s": "1"]),
            session: APIClient.makeSession(protocolClasses: [StubProtocol.self])
        )
        let chat = UUID()
        let first = try await client.messages(chatId: chat)
        #expect(first.next == "0190a000-0000-7000-8000-000000000001")
        let second = try await client.messages(chatId: chat, before: first.next)
        #expect(second.next == nil)
        let requests = StubProtocol.requests(host: host)
        #expect(requests.count == 2)
        #expect(requests[1].url?.query == "vor=0190a000-0000-7000-8000-000000000001")
    }

    @Test func directChatBodyOmitsParentForParents() throws {
        let unit = UUID()
        let parent = String(decoding: try JSONEncoder().encode(DirectChatBody(unitId: unit, parentUserId: nil)), as: UTF8.self)
        #expect(parent == #"{"stufeId":"\#(unit.uuidString)"}"#)
    }
}
