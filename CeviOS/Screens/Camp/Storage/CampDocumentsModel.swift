import SwiftUI

/// L33: the documents of the camp. Each one points to a file at the storage place; the app never loads the file.
@MainActor @Observable
final class CampDocumentsModel: CampRosterModel {
    var documents: [CampDocument] = []
    var query = ""
    var type: CampDocumentTypeFilter?
    @ObservationIgnored let debouncer = CampReloadDebouncer()

    var filter: CampDocumentFilter { CampDocumentFilter(search: CampStorageText.term(query), type: type) }
    var isFiltered: Bool { filter.search != nil || type != nil }

    override func load() async {
        guard let client = active.client, let campId = active.camp?.id else { return }
        let filter = filter
        do {
            var all: [CampDocument] = []
            var cursor: UUID?
            repeat {
                let page = try await client.campDocuments(campId: campId, filter: filter, after: cursor, limit: 100)
                all += page.documents
                cursor = page.next
            } while cursor != nil && all.count < 500
            documents = all
            loaded()
        } catch is CancellationError {
        } catch {
            // A reload that was replaced by a newer one ends here without a message.
            guard !Task.isCancelled else { return }
            failLoad(error, hasContent: !documents.isEmpty)
        }
    }

    func reloadSoon() { debouncer.schedule { [weak self] in await self?.load() } }

    func clearFilter() {
        type = nil
        query = ""
        Task { await load() }
    }
}
