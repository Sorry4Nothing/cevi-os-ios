import Foundation

/// Opens the camp of a tapped push. The push carries no camp id, so the server resolves it.
@MainActor
enum CampRouter {
    /// Returns `nil` when the camp is open, otherwise the state to show.
    /// Notices, mentions and the inbox have a screen; the other objects open the camp only (shortcut: open them when their slice lands).
    static func open(type: CampPushType, objectId: UUID, client: APIClient?, list: CampListModel, active: ActiveCamp) async -> CampScreenState? {
        guard let client else { return nil }
        do {
            let resolution = try await client.resolveCampPush(type: type, objectId: objectId)
            if list.camps.isEmpty { await list.load(client: client) }
            if let entry = list.camps.first(where: { $0.id == resolution.campId }) {
                active.open(entry, client: client)
            } else {
                let detail = try await client.camp(id: resolution.campId)
                active.open(camp: detail.camp, role: detail.role, client: client)
            }
            active.destination = switch type {
            case .notice: .notices
            case .mention: .mentions
            case .feedback: CampCommsRights(role: active.role, readOnly: false).readsInbox ? .inbox : nil
            default: nil
            }
            return nil
        } catch let error as APIError {
            // 404 on resolving: not notified or no longer a member.
            if error.kind == .notFound { return .noAccess }
            return CampScreenState(error: error) ?? .maintenance
        } catch {
            return .offline
        }
    }
}
