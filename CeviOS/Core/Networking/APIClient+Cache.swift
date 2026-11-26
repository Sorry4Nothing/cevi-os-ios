import Foundation
import Synchronization

extension APIClient {
    nonisolated func setCacheObserver(_ observer: (@MainActor @Sendable (Date?) -> Void)?) { cacheObserver.withLock { $0 = observer } }

    private func report(_ stamp: Date?) async { await cacheObserver.withLock { $0 }?(stamp) }

    /// Sign-out and end of the session: nothing of the camps stays on the device.
    func clearCampCache() async {
        openCampIds = nil
        await campCache?.removeAll()
    }

    /// GET of a camp route. The answer is kept in the cache if the policy allows it. Without network the last kept answer
    /// is returned. 404 and 403 delete what was kept (the camp is gone or the access was lost).
    func sendCaching(_ path: String, query: [URLQueryItem]) async throws -> Data {
        guard path.hasPrefix(CampCachePolicy.root) else { return try await send("GET", path, query: query) }
        let target = CampCachePolicy.target(path: path, query: query)
        do {
            let data = try await send("GET", path, query: query)
            if let target { await keep(data, target) }
            if !(target.map { $0.scope == nil } ?? false) { await report(nil) }
            return data
        } catch let error as APIError {
            guard let target, let cache = campCache else { throw error }
            switch error.kind {
            case .network:
                if let hit = await cache.entry(scope: target.scope, key: target.key) {
                    await report(hit.storedAt)
                    return hit.data
                }
            case .notFound, .forbidden:
                if let scope = target.scope, target.isCampDetail { await cache.removeCamp(scope) } else { await cache.remove(scope: target.scope, key: target.key) }
            default:
                break
            }
            throw error
        }
    }

    private func keep(_ data: Data, _ target: CampCachePolicy.Target) async {
        guard let cache = campCache, data.count <= CampCachePolicy.maxEntryBytes else { return }
        if target.scope == nil {
            // The fresh list says which camps are open: the data of all others goes.
            guard let list = try? JSONDecoder.api.decode(CampList.self, from: data) else { return }
            let open = Set(list.camps.filter { $0.camp.status.isOpen }.map(\.id))
            openCampIds = open
            await cache.keepOnly(campIds: open)
        } else if let scope = target.scope, openCampIds?.contains(scope) != true {
            // Closed, unknown or not yet listed: nothing is written (fail secure).
            return
        }
        await cache.store(CampCacheEntry(data: data, storedAt: Date()), scope: target.scope, key: target.key)
    }
}
