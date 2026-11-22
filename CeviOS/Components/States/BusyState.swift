import Foundation
import Observation

/// Counts actions a person triggered. Shows the app-wide overlay once one runs longer than `delay`.
/// Background work (polling, older messages, mark-as-read, images, units, push registration) never goes through here.
@MainActor @Observable
final class BusyState {
    static let shared = BusyState()

    private(set) var isOverlayVisible = false
    /// The action runs much longer than usual (U5): the overlay adds a second line.
    private(set) var isSlow = false
    @ObservationIgnored private var count = 0
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private let delay: Duration
    @ObservationIgnored private let slowDelay: Duration
    /// Waits for `delay`; the tests replace it, so they run without real time.
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void

    init(delay: Duration = .milliseconds(250), slowDelay: Duration = .seconds(5), sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.delay = delay
        self.slowDelay = slowDelay
        self.sleep = sleep
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
        let delay = delay, slowDelay = slowDelay, sleep = sleep
        timer = Task { [weak self] in
            try? await sleep(delay)
            guard !Task.isCancelled else { return }
            self?.isOverlayVisible = true
            try? await sleep(slowDelay)
            guard !Task.isCancelled else { return }
            self?.isSlow = true
        }
    }

    func end() {
        guard count > 0 else { return }
        count -= 1
        guard count == 0 else { return }
        timer?.cancel()
        timer = nil
        isOverlayVisible = false
        isSlow = false
    }
}
