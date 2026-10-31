import Foundation
import Observation

/// Runs an action and shows its error. Prevents double taps.
@MainActor @Observable
final class ActionState {
    var isRunning = false
    var error: String?

    func perform(message: (APIError) -> String = { $0.displayText }, _ action: () async throws -> Void) async {
        guard !isRunning else { return }
        isRunning = true
        error = nil
        defer { isRunning = false }
        do {
            try await action()
        } catch let error as APIError {
            self.error = message(error)
        } catch is CancellationError {
        } catch {
            self.error = APIError.network.displayText
        }
    }
}
