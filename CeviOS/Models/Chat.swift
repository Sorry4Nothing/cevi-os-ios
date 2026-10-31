import Foundation

nonisolated enum ChatKind: String, Decodable, Sendable {
    case group = "stufe"
    case direct = "direkt"
}

nonisolated struct ChatPerson: Decodable, Hashable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let ceviName: String?

    /// "Name (Cevi name)" if there is a Cevi name.
    var displayName: String { ceviName.map { "\(name) (\($0))" } ?? name }
}

nonisolated struct ChatUnit: Decodable, Hashable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let abbreviation: String

    enum CodingKeys: String, CodingKey { case id, name, abbreviation = "kuerzel" }
}

nonisolated struct ChatLastMessage: Decodable, Hashable, Sendable {
    /// Cut to 120 characters by the server.
    let text: String
    let createdAt: Date
    let isOwn: Bool
    let author: ChatPerson

    enum CodingKeys: String, CodingKey { case text, createdAt = "erstelltAm", isOwn = "eigene", author = "autor" }
}

nonisolated struct ChatSummary: Decodable, Hashable, Identifiable, Sendable {
    let id: UUID
    let kind: ChatKind
    let unit: ChatUnit
    /// The parent of a direct chat, `nil` in group chats.
    let parent: ChatPerson?
    let unitLeaders: [ChatPerson]
    let unread: Int
    let lastMessage: ChatLastMessage?

    enum CodingKeys: String, CodingKey {
        case id, kind = "typ", unit = "stufe", parent = "eltern", unitLeaders = "stufenleitung"
        case unread = "ungelesen", lastMessage = "letzteNachricht"
    }
}

nonisolated struct ChatList: Decodable, Sendable {
    let chats: [ChatSummary]
}

nonisolated struct ChatProgramRef: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String

    enum CodingKeys: String, CodingKey { case id, title = "titel" }
}

nonisolated struct ChatAuthor: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let ceviName: String?
    let imageURL: String?
    let isUnitLeader: Bool

    enum CodingKeys: String, CodingKey { case id, name, ceviName, imageURL = "bildUrl", isUnitLeader = "stufenleitung" }

    var displayName: String { ceviName.map { "\(name) (\($0))" } ?? name }
}

nonisolated struct ChatMessage: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let text: String
    let createdAt: Date
    let author: ChatAuthor
    let program: ChatProgramRef?
    let isOwn: Bool

    enum CodingKeys: String, CodingKey {
        case id, text, createdAt = "erstelltAm", author = "autor", program = "programm", isOwn = "eigene"
    }
}

/// One page of messages, newest first. `next` is the cursor (`vor`) for the next older page; `nil` is the end.
nonisolated struct ChatMessagePage: Decodable, Sendable {
    let messages: [ChatMessage]
    let next: String?

    enum CodingKeys: String, CodingKey { case messages = "nachrichten", next = "naechster" }
}

nonisolated struct ChatID: Decodable, Sendable {
    let id: UUID
}
