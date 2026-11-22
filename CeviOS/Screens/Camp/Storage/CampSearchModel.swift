import SwiftUI

/// L36: full text search over everything the role may see. The server tolerates typos and filters by role;
/// the app shows what it returns, grouped by kind.
@MainActor @Observable
final class CampSearchModel: CampRosterModel {
    /// The server needs at least two characters.
    static let minimumLength = 2

    var query = ""
    var type: CampSearchType?
    var hits: [CampSearchHit] = []
    @ObservationIgnored let debouncer = CampReloadDebouncer()

    var groups: [CampSearchGroup] { CampSearchGroup.group(hits) }
    var term: String? { CampStorageText.term(query).flatMap { $0.count >= Self.minimumLength ? $0 : nil } }
    var storage: CampStorageRights { CampStorageRights(role: active.role, readOnly: active.isReadOnly) }

    override func load() async {
        guard let term else {
            hits = []
            loaded()
            return
        }
        guard let client = active.client, let campId = active.camp?.id else { return }
        if hits.isEmpty { phase = .loading }
        do {
            hits = try await client.searchCamp(campId: campId, text: term, type: type).hits
            loaded()
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return }
            failLoad(error, hasContent: !hits.isEmpty)
        }
    }

    func reloadSoon() { debouncer.schedule { [weak self] in await self?.load() } }
}
