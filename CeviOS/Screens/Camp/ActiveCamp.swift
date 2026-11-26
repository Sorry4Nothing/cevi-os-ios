import SwiftUI

/// Where a tapped push leads inside the camp (`CampRouter`); the tab bar or the «Mehr» sheet consumes it.
nonisolated enum CampDestination: Hashable, Sendable {
    case notices, mentions, inbox
    /// Only in the «Mehr» sheet (no push leads there).
    case meetings, notifications
    /// The roster screens (B3). Only the swaps are the target of a push (`lager_einteilung`).
    case rooms, trips, groups, swaps, count, shifts
    /// The on-site screens (B4). Only the attendance is the target of a push (`lager_anwesenheit`).
    case attendance, dayPages, shopping, packing, emergency, infos
    /// The storage and search screens (B5). No push leads there.
    case documents, addressBook, search
    /// The camp check; no push leads there.
    case check
}

/// The emergency window as it was last loaded, with the time of loading.
nonisolated struct CampEmergencySnapshot: Equatable, Sendable {
    let data: CampEmergency
    let loadedAt: Date
}

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
    /// Set by a tapped push, cleared by the screen that opens it.
    var destination: CampDestination?
    private(set) var outbox: CampOutbox?
    /// The last loaded emergency window, kept in memory only so it opens without network (no local storage yet).
    var emergencySnapshot: CampEmergencySnapshot?
    /// Display names of the members by person id, for screens where a list gives only the id. Empty if the role may not read them.
    private(set) var memberNames: [UUID: String] = [:]
    @ObservationIgnored private var namesLoadedFor: UUID?
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
        destination = nil
        emergencySnapshot = nil
        memberNames = [:]
        namesLoadedFor = nil
    }

    /// Loads the names once per camp. A refusal or a network failure leaves the directory empty (screens then say «Person»).
    func loadMemberNames() async {
        guard let client, let id = camp?.id, namesLoadedFor != id else { return }
        guard let members = try? await client.campMembers(campId: id), camp?.id == id else { return }
        namesLoadedFor = id
        memberNames = Dictionary(members.map { ($0.personId, $0.name) }, uniquingKeysWith: { first, _ in first })
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
        emergencySnapshot = nil
        memberNames = [:]
        namesLoadedFor = nil
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
