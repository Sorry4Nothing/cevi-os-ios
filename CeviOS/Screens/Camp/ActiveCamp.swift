import SwiftUI

/// The camp the person works in now, kept in memory only. With a camp the app shows the camp view, without it the program view.
@MainActor @Observable
final class ActiveCamp {
    private(set) var camp: Camp?
    private(set) var role: CampRole?
    /// Changes waiting to be sent (U6); refreshed with `refreshQueue()`.
    private(set) var waitingCount = 0
    private(set) var isOffline = false
    /// The camp choice (L1) is open.
    var showsChooser = false
    private(set) var outbox: CampOutbox?
    @ObservationIgnored private(set) var client: APIClient?

    var isOpen: Bool { camp != nil }
    var title: String { camp?.title ?? "" }
    /// Completed and archived camps (U8): the app shows no change buttons.
    var isReadOnly: Bool { !(camp?.status.isOpen ?? true) }

    func open(camp: Camp, role: CampRole, client: APIClient?) {
        guard self.camp?.id != camp.id else { return }
        self.camp = camp
        self.role = role
        self.client = client
        outbox = client.map { CampOutbox(campId: camp.id, client: $0) }
        waitingCount = 0
        isOffline = false
    }

    func open(_ entry: CampListEntry, client: APIClient?) { open(camp: entry.camp, role: entry.role, client: client) }

    /// Back to the program view.
    func leave() {
        camp = nil
        role = nil
        outbox = nil
        client = nil
        waitingCount = 0
        isOffline = false
    }

    func refreshQueue() async {
        waitingCount = await outbox?.waitingCount ?? 0
    }

    /// «Jetzt senden». A network failure keeps the entries and shows the banner as offline.
    func sendWaiting() async {
        guard let outbox else { return }
        do {
            try await outbox.flush()
            isOffline = false
        } catch let error as APIError {
            isOffline = error.kind == .network
        } catch {}
        await refreshQueue()
    }

    #if DEBUG
    /// For previews: the banner state without a queue.
    func setPreview(waiting: Int, offline: Bool) {
        waitingCount = waiting
        isOffline = offline
    }
    #endif
}
