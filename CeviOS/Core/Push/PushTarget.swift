import Foundation

/// Where a tap on a push leads. A push carries only `typ` and `id`, never message text or names.
nonisolated enum PushTarget: Equatable, Sendable {
    case chat(UUID)
    case program(UUID)
    /// Announcement from the administration: no target, the app just opens.
    case announcement

    /// Reads the push data. Unknown types and malformed IDs yield `nil`.
    static func from(userInfo: [AnyHashable: Any]) -> PushTarget? {
        guard let type = userInfo["typ"] as? String else { return nil }
        let id = (userInfo["id"] as? String).flatMap { UUID(uuidString: $0) }
        switch type {
        case "chat": return id.map(PushTarget.chat)
        case "programm": return id.map(PushTarget.program)
        case "mitteilung": return .announcement
        default: return nil
        }
    }

    /// Whether a push arriving in the foreground is hidden: pushes for the open chat are not shown.
    func isHidden(openChatId: UUID?) -> Bool {
        if case .chat(let id) = self, let openChatId { return id == openChatId }
        return false
    }
}

nonisolated enum PushToken {
    /// FCM registration token: 20 to 512 characters from letters, digits and `_ : . -`.
    static func isValid(_ token: String) -> Bool {
        token.wholeMatch(of: /[A-Za-z0-9_:.\-]{20,512}/) != nil
    }
}
