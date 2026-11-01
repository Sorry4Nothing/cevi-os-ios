import Foundation

nonisolated enum ChatTitle {
    /// Group chat: the unit. Direct chat: for parents the unit leaders, for unit leaders the parent.
    static func title(for chat: ChatSummary, profile: Profile) -> String {
        switch chat.kind {
        case .group:
            String(localized: "Gruppenchat \(chat.unit.name)")
        case .direct:
            if let parent = chat.parent, profile.isUnitLeader(of: chat.unit.id) {
                parent.shortName
            } else {
                String(localized: "Stufenleitung \(chat.unit.name)")
            }
        }
    }
}
