import Foundation
import Testing
@testable import CeviOS

/// A wait that ends only when the test says so, so the overlay delay needs no real time.
private actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Error>] = []

    func wait() async throws {
        if isOpen { return }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { waiters.append($0) }
        } onCancel: {
            Task { await self.cancelWaiters() }
        }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }

    private func cancelWaiters() {
        waiters.forEach { $0.resume(throwing: CancellationError()) }
        waiters = []
    }
}

@MainActor
struct BusyStateTests {
    private let delayGate = Gate()
    private let busy: BusyState

    init() {
        let gate = delayGate
        busy = BusyState(delay: .milliseconds(250), sleep: { _ in try await gate.wait() })
    }

    /// Waits until the condition holds (limit 5 s); only the positive cases poll, the negative ones need no time at all.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<5_000 where !condition() { try? await Task.sleep(for: .milliseconds(1)) }
    }

    @Test func shortActionNeverShowsOverlay() async {
        await busy.track { await Task.yield() }
        await delayGate.open() // the delay ends after the action: the timer was cancelled by then
        await Task.yield()
        #expect(!busy.isOverlayVisible)
    }

    @Test func longActionShowsOverlayAndHidesWhenDone() async {
        busy.begin()
        await delayGate.open()
        await waitUntil { busy.isOverlayVisible }
        #expect(busy.isOverlayVisible)
        busy.end()
        #expect(!busy.isOverlayVisible)
    }

    @Test func overlappingActionsEndWhenTheLastFinishes() async {
        busy.begin()
        busy.begin()
        await delayGate.open()
        await waitUntil { busy.isOverlayVisible }
        busy.end()
        #expect(busy.isOverlayVisible)
        busy.end()
        #expect(!busy.isOverlayVisible)
    }

    @Test func untrackedBackgroundWorkNeverCounts() async {
        await delayGate.open()
        await Task.yield()
        #expect(!busy.isOverlayVisible)
        busy.end() // unbalanced end must not go negative
        busy.begin()
        busy.end()
        await Task.yield()
        #expect(!busy.isOverlayVisible)
    }

    @Test func actionStateCountsAsUserAction() async {
        let action = ActionState(busy: busy)
        let actionGate = Gate()
        let running = Task { @MainActor in await action.perform { try await actionGate.wait() } }
        await delayGate.open()
        await waitUntil { busy.isOverlayVisible }
        #expect(busy.isOverlayVisible)
        await actionGate.open()
        await running.value
        #expect(!busy.isOverlayVisible)
    }
}
