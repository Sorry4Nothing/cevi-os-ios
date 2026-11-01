import Foundation
import Observation

/// Runs a user action and shows its error. Prevents double taps; counts for the app-wide busy overlay.
@MainActor @Observable
final class ActionState {
    var isRunning = false
    var error: String?
    private let busy: BusyState

    init(busy: BusyState? = nil) {
        self.busy = busy ?? .shared
    }

    func perform(message: (APIError) -> String = { $0.displayText }, _ action: () async throws -> Void) async {
        guard !isRunning else { return }
        isRunning = true
        error = nil
        defer { isRunning = false }
        do {
            try await busy.track(action)
        } catch let error as APIError {
            self.error = message(error)
        } catch is CancellationError {
        } catch {
            self.error = APIError.network.displayText
        }
    }
}
