import SwiftUI

/// The camps of the person (`GET /api/v1/lager`), for the camp choice (L1) and the switcher.
@MainActor @Observable
final class CampListModel {
    enum Phase: Equatable {
        case loading
        case loaded
        /// `state` is the cross-cutting state of the error, `nil` for the general error.
        case failed(state: CampScreenState?, text: String)
    }

    private(set) var camps: [CampListEntry] = []
    private(set) var phase: Phase = .loading

    /// The switcher shows only for members of at least one camp (a failed load keeps what was loaded before).
    var showsSwitcher: Bool { !camps.isEmpty }
    /// Draft and active camps.
    var openCamps: [CampListEntry] { camps.filter { $0.camp.status.isOpen } }
    /// Completed and archived camps: read-only.
    var closedCamps: [CampListEntry] { camps.filter { !$0.camp.status.isOpen } }

    /// For previews and tests.
    func setPreview(phase: Phase, camps: [CampListEntry]) {
        self.phase = phase
        self.camps = camps
    }

    func load(client: APIClient?) async {
        guard let client else { return }
        do {
            camps = try await client.camps()
            phase = .loaded
        } catch is CancellationError {
        } catch let error as APIError {
            phase = .failed(state: CampScreenState(error: error), text: error.displayText)
        } catch {
            phase = .failed(state: .offline, text: APIError.network.displayText)
        }
    }
}

extension CampStatus {
    /// Draft and active; the other two are read-only.
    nonisolated var isOpen: Bool { self == .draft || self == .active }
}
