import Foundation
import Testing
@testable import CeviOS

@MainActor
struct BusyStateTests {
    // Short delay so the tests stay quick; the margins around it are wide to stay stable.
    private let busy = BusyState(delay: .milliseconds(50))

    @Test func shortActionNeverShowsOverlay() async throws {
        await busy.track { try? await Task.sleep(for: .milliseconds(5)) }
        try await Task.sleep(for: .milliseconds(150))
        #expect(!busy.isOverlayVisible)
    }

    @Test func longActionShowsOverlayAndHidesWhenDone() async throws {
        busy.begin()
        try await Task.sleep(for: .milliseconds(200))
        #expect(busy.isOverlayVisible)
        busy.end()
        #expect(!busy.isOverlayVisible)
    }

    @Test func overlappingActionsEndWhenTheLastFinishes() async throws {
        busy.begin()
        busy.begin()
        try await Task.sleep(for: .milliseconds(200))
        busy.end()
        #expect(busy.isOverlayVisible)
        busy.end()
        #expect(!busy.isOverlayVisible)
    }

    @Test func untrackedBackgroundWorkNeverCounts() async throws {
        try await Task.sleep(for: .milliseconds(200))
        #expect(!busy.isOverlayVisible)
        busy.end() // unbalanced end must not go negative
        busy.begin()
        busy.end()
        try await Task.sleep(for: .milliseconds(150))
        #expect(!busy.isOverlayVisible)
    }

    @Test func actionStateCountsAsUserAction() async throws {
        let action = ActionState(busy: busy)
        let observed = Task { @MainActor in
            try await Task.sleep(for: .milliseconds(200))
            return busy.isOverlayVisible
        }
        await action.perform { try await Task.sleep(for: .milliseconds(400)) }
        #expect(try await observed.value)
        #expect(!busy.isOverlayVisible)
    }
}
