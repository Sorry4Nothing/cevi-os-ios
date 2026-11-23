import SwiftUI

/// K3 Meine Raumanfragen: the person's own requests with their state.
@MainActor @Observable
final class MyRoomRequestsModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(text: String, isOffline: Bool)
    }

    private(set) var phase: Phase = .loading
    private(set) var requests: [RoomRequest] = []

    func load(client: APIClient?) async {
        guard let client else { return }
        do {
            var all: [RoomRequest] = []
            var after: UUID?
            for _ in 0..<10 {
                let page = try await client.myRoomRequests(after: after)
                all += page.requests
                guard page.hasMore, let next = page.next else { break }
                after = next
            }
            requests = all
            phase = .loaded
        } catch is CancellationError {
        } catch let error as APIError {
            if requests.isEmpty { phase = .failed(text: error.displayText, isOffline: error.kind == .network) }
        } catch {
            if requests.isEmpty { phase = .failed(text: APIError.network.displayText, isOffline: true) }
        }
    }

    nonisolated static func chip(for status: RoomRequestStatus) -> RequestStatusChip.Kind {
        switch status {
        case .requested: .open
        case .confirmed: .confirmed
        case .declined: .declined
        case .cancelled: .cancelled
        }
    }
}
