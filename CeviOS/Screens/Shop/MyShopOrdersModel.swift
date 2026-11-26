import SwiftUI

/// Meine Bestellungen im Lädeli: the own orders, newest first; an open one may be cancelled.
@MainActor @Observable
final class MyShopOrdersModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(text: String, isOffline: Bool)
    }

    private(set) var phase: Phase = .loading
    private(set) var orders: [ShopOrder] = []
    /// Order whose cancellation is on its way.
    private(set) var busyId: UUID?
    private(set) var rowErrors: [UUID: String] = [:]
    private(set) var notice: String?

    #if DEBUG
    /// Only for previews.
    init(phase: Phase = .loading, orders: [ShopOrder] = [], busyId: UUID? = nil, rowErrors: [UUID: String] = [:], notice: String? = nil) {
        self.phase = phase
        self.orders = orders
        self.busyId = busyId
        self.rowErrors = rowErrors
        self.notice = notice
    }
    #endif

    func load(client: APIClient?) async {
        guard let client else { return }
        do {
            var all: [ShopOrder] = []
            var after: UUID?
            for _ in 0..<10 {
                let page = try await client.myShopOrders(after: after)
                all += page.orders
                guard page.hasMore, let next = page.next else { break }
                after = next
            }
            orders = all
            rowErrors = rowErrors.filter { id, _ in all.contains { $0.id == id } }
            phase = .loaded
        } catch is CancellationError {
        } catch let error as APIError {
            if orders.isEmpty { phase = .failed(text: error.displayText, isOffline: error.kind == .network) }
        } catch {
            if orders.isEmpty { phase = .failed(text: APIError.network.displayText, isOffline: true) }
        }
    }

    /// Only an open order may be cancelled; the view shows the button only then.
    static func canCancel(_ order: ShopOrder) -> Bool { order.status == .open }

    func cancel(_ order: ShopOrder, client: APIClient?) async {
        guard let client, busyId == nil, Self.canCancel(order) else { return }
        busyId = order.id
        defer { busyId = nil }
        rowErrors[order.id] = nil
        do {
            try await BusyState.shared.track { try await client.cancelShopOrder(id: order.id) }
            say(String(localized: "Bestellung storniert."))
            await load(client: client)
        } catch let error as APIError {
            rowErrors[order.id] = ShopRules.cancelError(error)
            // The state changed behind our back (ready, handed over, gone): show the current one.
            if error.kind == .conflict || error.kind == .notFound { await load(client: client) }
        } catch is CancellationError {
        } catch {
            rowErrors[order.id] = APIError.network.displayText
        }
    }

    func dismissNotice() { notice = nil }

    private func say(_ text: String) {
        notice = text
        AccessibilityNotification.Announcement(text).post()
    }
}
