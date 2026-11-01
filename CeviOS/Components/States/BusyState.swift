import Foundation
import Observation

/// Counts actions a person triggered. Shows the app-wide overlay once one runs longer than `delay`.
/// Background work (polling, older messages, mark-as-read, images, units, push registration) never goes through here.
@MainActor @Observable
final class BusyState {
    static let shared = BusyState()

    private(set) var isOverlayVisible = false
    @ObservationIgnored private var count = 0
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private let delay: Duration

    init(delay: Duration = .milliseconds(250)) {
        self.delay = delay
    }

    /// Runs a user-triggered action; the overlay appears if it is still running after `delay`.
    func track<T>(_ operation: () async throws -> T) async rethrows -> T {
        begin()
        defer { end() }
        return try await operation()
    }

    func begin() {
        count += 1
        guard count == 1 else { return }
        let delay = delay
        timer = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.isOverlayVisible = true
        }
    }

    func end() {
        guard count > 0 else { return }
        count -= 1
        guard count == 0 else { return }
        timer?.cancel()
        timer = nil
        isOverlayVisible = false
    }
}
