import Foundation

/// One cached answer of the server: the raw bytes exactly as the server sent them, and when they were loaded.
nonisolated struct CampCacheEntry: Codable, Equatable, Sendable {
    let data: Data
    let storedAt: Date
}

/// Cache of the last loaded camp data (read only). `scope` is the camp, `nil` the list of camps. Implementations only
/// store; what may be stored is decided by `CampCachePolicy` and the client.
nonisolated protocol CampCache: Sendable {
    func entry(scope: UUID?, key: String) async -> CampCacheEntry?
    func store(_ entry: CampCacheEntry, scope: UUID?, key: String) async
    func remove(scope: UUID?, key: String) async
    func removeCamp(_ id: UUID) async
    /// Deletes the data of every camp not in `ids` (the camp list stays).
    func keepOnly(campIds ids: Set<UUID>) async
    func removeAll() async
}

/// What the cache may hold. A whitelist: whatever is not named here is never written (fail secure).
nonisolated enum CampCachePolicy {
    static let root = "/api/v1/lager"

    /// First path segment after the camp id. Camp detail, tasks, notice board, day pages, today, schedule, packing list,
    /// shopping list, emergency, infos, weather. Never: participants, rooms, trips, groups, attendance, count list,
    /// address book, anonymous inbox, search, rights table, members, shift plan.
    static let allowedAreas: Set<String> = [
        "aufgaben", "pinnwand", "tagesseiten", "heute", "meine-woche", "zeitplan", "packliste", "einkauf", "notfall", "infos", "wetter",
    ]
    /// Entries bigger than this are not stored.
    static let maxEntryBytes = 1_000_000

    nonisolated struct Target: Equatable, Sendable {
        /// `nil`: the camp list.
        let scope: UUID?
        let key: String
        /// The camp itself (`GET /api/v1/lager/{id}`).
        let isCampDetail: Bool
    }

    static func target(path: String, query: [URLQueryItem]) -> Target? {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 3, parts[0] == "api", parts[1] == "v1", parts[2] == "lager" else { return nil }
        let suffix = query.isEmpty ? "" : "?" + query.sorted { $0.name < $1.name }.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
        if parts.count == 3 { return Target(scope: nil, key: "list" + suffix, isCampDetail: false) }
        guard let id = UUID(uuidString: parts[3]) else { return nil }
        if parts.count == 4 { return Target(scope: id, key: "detail" + suffix, isCampDetail: true) }
        guard allowedAreas.contains(parts[4]) else { return nil }
        return Target(scope: id, key: parts.dropFirst(4).joined(separator: "/") + suffix, isCampDetail: false)
    }
}

/// For tests and previews: the same rules as the file cache, in memory and unencrypted.
actor CampMemoryCache: CampCache {
    private var scopes: [UUID?: [String: CampCacheEntry]] = [:]

    func entry(scope: UUID?, key: String) -> CampCacheEntry? { scopes[scope]?[key] }
    func store(_ entry: CampCacheEntry, scope: UUID?, key: String) { scopes[scope, default: [:]][key] = entry }
    func remove(scope: UUID?, key: String) { scopes[scope]?[key] = nil }
    func removeCamp(_ id: UUID) { scopes[id] = nil }
    func keepOnly(campIds ids: Set<UUID>) { scopes = scopes.filter { $0.key == nil || ids.contains($0.key!) } }
    func removeAll() { scopes = [:] }

    /// For tests: the camps that hold data.
    var campIds: Set<UUID> { Set(scopes.keys.compactMap { $0 }) }
    var hasListEntry: Bool { scopes[nil] != nil }
}
