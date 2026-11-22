import Foundation

nonisolated enum CampOutboxState: String, Codable, Sendable {
    case waiting
    case sent
    case rejected
    case conflict
}

/// An operation in the queue, with what the server answered. `rejected` and `conflict` stay until the person decides.
nonisolated struct CampOutboxEntry: Codable, Equatable, Identifiable, Sendable {
    var operation: CampOperation
    var state: CampOutboxState = .waiting
    /// Code of the server on `rejected` and `conflict`.
    var code: String?
    var message: String?
    /// On `conflict`: "Aktueller Stand" (the entry itself holds "Deine Änderung": `operation.payload`).
    var current: [String: CampJSON]?
    var differing: [String]?

    var id: UUID { operation.clientOpId }
}

/// Where the queue lives. The only implementation for now is in memory; the decision about local storage is open.
nonisolated protocol CampOutboxStore: Sendable {
    func load() async -> [CampOutboxEntry]
    func save(_ entries: [CampOutboxEntry]) async
}

actor CampOutboxMemoryStore: CampOutboxStore {
    private var entries: [CampOutboxEntry] = []

    func load() -> [CampOutboxEntry] { entries }
    func save(_ entries: [CampOutboxEntry]) { self.entries = entries }
}

/// Collects the changes of one camp and sends them in batches. Sending is idempotent: an entry that stays `waiting` after a
/// failure goes out again with the same `clientOpId`.
actor CampOutbox {
    private let campId: UUID
    private let client: APIClient
    private let store: any CampOutboxStore
    private var entries: [CampOutboxEntry] = []
    private var loaded = false
    private var flushing = false

    init(campId: UUID, client: APIClient, store: any CampOutboxStore = CampOutboxMemoryStore()) {
        self.campId = campId
        self.client = client
        self.store = store
    }

    var all: [CampOutboxEntry] { entries }
    /// For the banner "n Änderungen warten".
    var waitingCount: Int { entries.count { $0.state == .waiting } }

    func load() async {
        guard !loaded else { return }
        entries = await store.load()
        loaded = true
    }

    func enqueue(_ operation: CampOperation) async {
        await load()
        entries.append(CampOutboxEntry(operation: operation))
        await store.save(entries)
    }

    /// Sends all `waiting` entries (100 per request). Throws the `APIError` of a failure that says nothing about the entries
    /// (network, 401, 426, 429, 5xx): they stay `waiting`. A refusal of the whole request (400, 403, 404, 409, 410, 413) marks
    /// the entries of that request `rejected`. A call while another runs does nothing.
    func flush() async throws {
        await load()
        guard !flushing else { return }
        flushing = true
        defer { flushing = false }
        while true {
            let batch = entries.filter { $0.state == .waiting }.prefix(CampOperationBatch.maxOperations).map(\.operation)
            guard !batch.isEmpty else { return }
            do {
                let response = try await client.sendCampOperations(campId: campId, batch)
                apply(response.results)
                // An answer without a result for an entry would loop forever: leave those waiting and stop.
                if batch.contains(where: { op in entries.contains { $0.id == op.id && $0.state == .waiting } }) {
                    await store.save(entries)
                    return
                }
            } catch let error as APIError where [.invalidInput, .forbidden, .notFound, .conflict, .gone, .payloadTooLarge].contains(error.kind) {
                for operation in batch { update(operation.id) { $0.state = .rejected; $0.code = error.code; $0.message = error.message } }
            }
            await store.save(entries)
        }
    }

    /// The person saw a rejected entry.
    func confirmRejected(_ id: UUID) async {
        await remove(id) { $0.state == .rejected }
    }

    /// Removes an entry in any state (the person gives the change up).
    func discard(_ id: UUID) async {
        await remove(id) { _ in true }
    }

    /// Takes the choice for a `conflict` entry. `keepCurrent` removes the entry; the other choices replace it by a new
    /// `waiting` entry with a new `clientOpId` and the current `version`. Returns `false` (entry unchanged) if there is no
    /// conflict entry with this id or its answer carried no `version`.
    @discardableResult
    func resolve(_ id: UUID, _ choice: CampConflictChoice) async -> Bool {
        await load()
        guard let index = entries.firstIndex(where: { $0.id == id && $0.state == .conflict }) else { return false }
        if choice == .keepCurrent {
            entries.remove(at: index)
        } else if let next = entries[index].operation.resolved(choice, current: entries[index].current) {
            entries[index] = CampOutboxEntry(operation: next)
        } else {
            return false
        }
        await store.save(entries)
        return true
    }

    /// Sign-out: nothing of the camp stays behind.
    func removeAll() async {
        entries = []
        loaded = true
        await store.save([])
    }

    /// Drops the entries that were sent.
    func clearSent() async {
        await load()
        entries.removeAll { $0.state == .sent }
        await store.save(entries)
    }

    private func remove(_ id: UUID, where condition: (CampOutboxEntry) -> Bool) async {
        await load()
        entries.removeAll { $0.id == id && condition($0) }
        await store.save(entries)
    }

    private func update(_ id: UUID, _ change: (inout CampOutboxEntry) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        change(&entries[index])
    }

    private func apply(_ results: [CampOperationResult]) {
        for result in results {
            update(result.clientOpId) { entry in
                // An entry the person discarded meanwhile is gone; one that is not waiting keeps its state.
                guard entry.state == .waiting else { return }
                switch result.status {
                case .ok: entry.state = .sent
                case .conflict: entry.state = .conflict
                case .rejected: entry.state = .rejected
                }
                entry.code = result.code
                entry.message = result.message
                entry.current = result.current
                entry.differing = result.differing
            }
        }
    }
}
