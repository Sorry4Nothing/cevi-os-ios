import SwiftUI

@MainActor @Observable
final class ParticipationOverviewModel {
    private(set) var overview: ParticipationOverview?
    private(set) var error: String?

    func load(programId: UUID, client: APIClient?) async {
        guard let client else { return }
        do {
            overview = try await client.participationOverview(programId: programId)
            error = nil
        } catch is CancellationError {
        } catch let apiError as APIError {
            error = LeadershipMessages.message(for: apiError).text
        } catch {
            self.error = APIError.network.displayText
        }
    }
}
