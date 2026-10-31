import Foundation

nonisolated struct DirectChatBody: Encodable, Sendable {
    let unitId: UUID
    let parentUserId: UUID?

    enum CodingKeys: String, CodingKey { case unitId = "stufeId", parentUserId = "elternUserId" }
}

nonisolated struct MessageBody: Encodable, Sendable {
    let text: String
    let programId: UUID?

    enum CodingKeys: String, CodingKey { case text, programId = "programmId" }
}

extension APIClient {
    private func chatPath(_ id: UUID) -> String { "/api/v1/chats/\(id.uuidString.lowercased())" }

    func chats() async throws -> [ChatSummary] {
        let list: ChatList = try await load("GET", "/api/v1/chats")
        return list.chats
    }

    /// Opens or creates the direct chat. Parents leave `parentUserId` out, unit leaders set it.
    func openDirectChat(unitId: UUID, parentUserId: UUID? = nil) async throws -> UUID {
        let chat: ChatID = try await load("POST", "/api/v1/chats/direkt", body: DirectChatBody(unitId: unitId, parentUserId: parentUserId))
        return chat.id
    }

    /// Newest page first; `before` is the cursor from the previous page's `next`.
    func messages(chatId: UUID, before: String? = nil) async throws -> ChatMessagePage {
        let query = before.map { [URLQueryItem(name: "vor", value: $0)] } ?? []
        return try await load("GET", chatPath(chatId) + "/nachrichten", query: query)
    }

    func sendMessage(chatId: UUID, text: String, programId: UUID? = nil) async throws {
        try await send("POST", chatPath(chatId) + "/nachrichten", body: MessageBody(text: text, programId: programId))
    }

    func markRead(chatId: UUID) async throws {
        try await send("PUT", chatPath(chatId) + "/gelesen")
    }
}

nonisolated enum ChatRules {
    static let maxLength = 2000
    /// Over this length the app shows a counter.
    static let counterFrom = 1800
    static let openChatPollInterval: Duration = .seconds(5)
    static let listPollInterval: Duration = .seconds(30)

    /// Text to send: trimmed, `nil` if empty or too long.
    static func sendableText(_ input: String) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.isEmpty && text.count <= maxLength ? text : nil
    }

    /// Merges the newest page into the known messages: no duplicates, newest first. UUIDv7 sorts by time.
    static func merge(existing: [ChatMessage], newest: [ChatMessage]) -> [ChatMessage] {
        var byId: [UUID: ChatMessage] = [:]
        for message in existing + newest { byId[message.id] = message }
        return byId.values.sorted { $0.id.uuidString > $1.id.uuidString }
    }

    /// For the chat the server's text is shown for rejections (word filter 400) and the rate limit (429).
    static func sendError(_ error: APIError) -> String {
        error.message ?? error.displayText
    }

    static func totalUnread(_ chats: [ChatSummary]) -> Int {
        chats.reduce(0) { $0 + $1.unread }
    }
}
