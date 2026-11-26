import Foundation

/// Opens the camp of a tapped push. The push carries no camp id, so the server resolves it.
@MainActor
enum CampRouter {
    /// Opens a camp for a tap on a widget and goes to the page; the same errors as a push.
    static func open(area: CampWidgetArea, campId: UUID, client: APIClient?, list: CampListModel, active: ActiveCamp) async -> CampScreenState? {
        guard let client else { return nil }
        do {
            if list.camps.isEmpty { await list.load(client: client) }
            if let entry = list.camps.first(where: { $0.id == campId }) {
                active.open(entry, client: client)
            } else {
                let detail = try await client.camp(id: campId)
                active.open(camp: detail.camp, role: detail.role, client: client)
            }
            active.destination = switch area {
            case .today: nil
            case .tasks: .tasks
            case .emergency: .emergency
            }
            return nil
        } catch let error as APIError {
            if error.kind == .notFound { return .noAccess }
            return CampScreenState(error: error) ?? .maintenance
        } catch {
            return .offline
        }
    }

    /// Returns `nil` when the camp is open, otherwise the state to show.
    /// Notices, mentions, the inbox, the swaps and the attendance have a screen; the other objects open the camp only (shortcut: open them when their slice lands).
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
            // The notifications about the roster are swap requests and their decisions.
            case .planning: .swaps
            case .attendance: .attendance
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
