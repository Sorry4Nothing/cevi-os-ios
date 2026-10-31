import SwiftUI

@MainActor @Observable
final class AttendanceModel {
    private(set) var overview: AttendanceOverview?
    private(set) var error: String?
    private(set) var saving: Set<UUID> = []
    var actionError: String?

    func load(unitId: UUID, client: APIClient?) async {
        guard let client else { return }
        do {
            overview = try await client.attendance(unitId: unitId)
            error = nil
        } catch is CancellationError {
        } catch let apiError as APIError {
            error = LeadershipMessages.message(for: apiError).text
        } catch {
            self.error = APIError.network.displayText
        }
    }

    /// `present == nil` takes the entry back. Reloads afterwards, so the numbers come from the server.
    func set(person: UUID, isChild: Bool, present: Bool?, unitId: UUID, programId: UUID, client: APIClient?) async {
        guard let client, !saving.contains(person) else { return }
        saving.insert(person)
        actionError = nil
        defer { saving.remove(person) }
        do {
            if isChild {
                try await client.setChildPresence(unitId: unitId, programId: programId, childId: person, present: present)
            } else {
                try await client.setLeaderPresence(unitId: unitId, programId: programId, userId: person, present: present)
            }
            await load(unitId: unitId, client: client)
        } catch let apiError as APIError {
            let message = LeadershipMessages.message(for: apiError)
            actionError = message.text
            if message.reload { await load(unitId: unitId, client: client) }
        } catch {
            actionError = APIError.network.displayText
        }
    }
}
