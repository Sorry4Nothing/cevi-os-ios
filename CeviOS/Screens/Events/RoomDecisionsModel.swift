import SwiftUI

/// K5 Raumanfragen entscheiden: the open requests of the rooms the person decides on (team of the room, without team the
/// department lead). The decision goes out at once and is never repeated on its own; a failure shows «Nochmals versuchen».
@MainActor @Observable
final class RoomDecisionsModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(text: String, isOffline: Bool)
    }

    /// What a failed decision leaves behind.
    enum Failure: Equatable {
        /// The request is gone from the list; the text says why.
        case removed(String)
        /// The request stays with this text. `bookedOnly`: the room is taken, only declining is left. `retry`: the person may try again.
        case kept(String, bookedOnly: Bool, retry: Bool)
    }

    nonisolated static let maxReason = 500

    private(set) var phase: Phase = .loading
    private(set) var requests: [RoomRequest] = []
    /// Request whose decision is on its way.
    private(set) var busyId: UUID?
    private(set) var rowErrors: [UUID: String] = [:]
    private(set) var bookedIds: Set<UUID> = []
    private(set) var retryable: [UUID: RoomDecision] = [:]
    /// Result line of the last decision or removal («Raum bestätigt.»).
    private(set) var notice: String?

    #if DEBUG
    /// Only for previews.
    init(phase: Phase = .loading, requests: [RoomRequest] = [], rowErrors: [UUID: String] = [:], bookedIds: Set<UUID> = [], retryable: [UUID: RoomDecision] = [:], notice: String? = nil) {
        self.phase = phase
        self.requests = requests
        self.rowErrors = rowErrors
        self.bookedIds = bookedIds
        self.retryable = retryable
        self.notice = notice
    }
    #endif

    /// The profile shows its row only while this is `true`.
    var hasOpen: Bool { !requests.isEmpty }

    func load(client: APIClient?) async {
        guard let client else { return }
        do {
            var all: [RoomRequest] = []
            var after: UUID?
            for _ in 0..<10 {
                let page = try await client.openRoomRequests(after: after)
                all += page.requests
                guard page.hasMore, let next = page.next else { break }
                after = next
            }
            requests = all
            rowErrors = rowErrors.filter { id, _ in all.contains { $0.id == id } }
            phase = .loaded
        } catch is CancellationError {
        } catch let error as APIError {
            if requests.isEmpty { phase = .failed(text: error.displayText, isOffline: error.kind == .network) }
        } catch {
            if requests.isEmpty { phase = .failed(text: APIError.network.displayText, isOffline: true) }
        }
    }

    func accept(_ request: RoomRequest, client: APIClient?) async {
        guard !bookedIds.contains(request.id) else { return }
        await decide(request, .accept, client: client)
    }

    /// `true` when the request was declined; the sheet then closes. The reason is 1 to 500 characters.
    func decline(_ request: RoomRequest, reason: String, client: APIClient?) async -> Bool {
        guard let text = Self.validReason(reason) else {
            rowErrors[request.id] = Self.reasonError(reason)
            return false
        }
        await decide(request, .decline(reason: text), client: client)
        // Also true when the request left the list (already decided): there is nothing left to type.
        return !requests.contains { $0.id == request.id }
    }

    /// The tap on «Nochmals versuchen».
    func retry(_ request: RoomRequest, client: APIClient?) async {
        guard let decision = retryable[request.id] else { return }
        await decide(request, decision, client: client)
    }

    private func decide(_ request: RoomRequest, _ decision: RoomDecision, client: APIClient?) async {
        guard let client, busyId == nil else { return }
        busyId = request.id
        defer { busyId = nil }
        rowErrors[request.id] = nil
        retryable[request.id] = nil
        do {
            let state = try await BusyState.shared.track { try await client.decideRoomRequest(id: request.id, decision) }
            remove(request.id)
            say(state.status == .confirmed ? String(localized: "\(request.roomName) bestätigt.") : String(localized: "\(request.roomName) abgelehnt."))
        } catch let error as APIError {
            switch Self.failure(for: error) {
            case .removed(let text):
                remove(request.id)
                say(text)
            case let .kept(text, bookedOnly, retry):
                rowErrors[request.id] = text
                if bookedOnly { bookedIds.insert(request.id) }
                if retry { retryable[request.id] = decision }
            }
        } catch {
            rowErrors[request.id] = APIError.network.displayText
            retryable[request.id] = decision
        }
    }

    private func remove(_ id: UUID) {
        requests.removeAll { $0.id == id }
        rowErrors[id] = nil
        bookedIds.remove(id)
        retryable[id] = nil
    }

    private func say(_ text: String) {
        notice = text
        AccessibilityNotification.Announcement(text).post()
    }

    func dismissNotice() { notice = nil }

    // MARK: Texts

    /// The trimmed reason if it has 1 to 500 characters.
    nonisolated static func validReason(_ reason: String) -> String? {
        let text = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return (1...maxReason).contains(text.count) ? text : nil
    }

    nonisolated static func reasonError(_ reason: String) -> String {
        reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? String(localized: "Gib einen Grund an. Die anfragende Person sieht ihn.")
            : String(localized: "Der Grund ist zu lang (höchstens 500 Zeichen).")
    }

    /// What each error of a decision means for the list and the person.
    nonisolated static func failure(for error: APIError) -> Failure {
        switch error.kind {
        case .conflict:
            switch error.code {
            case EventRules.invalidStateCode:
                return .removed(String(localized: "Diese Anfrage ist schon entschieden, zurückgezogen oder vorbei."))
            case EventRules.roomBookedCode:
                return .kept(String(localized: "Der Raum ist zu dieser Zeit schon gebucht. Du kannst die Anfrage nur ablehnen."), bookedOnly: true, retry: false)
            default:
                return .kept(error.displayText, bookedOnly: false, retry: false)
            }
        case .forbidden:
            return error.code == EventRules.ownRequestCode
                ? .kept(String(localized: "Über deine eigene Anfrage entscheidest du nicht."), bookedOnly: false, retry: false)
                : .removed(String(localized: "Du darfst über diese Anfrage nicht entscheiden."))
        case .notFound:
            return .removed(String(localized: "Diese Anfrage gibt es nicht mehr."))
        case .network:
            return .kept(error.displayText, bookedOnly: false, retry: true)
        case .invalidInput:
            return .kept(error.displayText, bookedOnly: false, retry: false)
        default:
            return .kept(error.displayText, bookedOnly: false, retry: true)
        }
    }
}
